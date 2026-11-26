package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.DatabaseErrors.isTableNotExist;

/** The blocking decoration of one listed issue (upstream issueops.IssueBlocking). */
typedef IssueBlocking = {
	/** The open issues that block it, in byte order, each once. */
	final blockedBy:Array<String>;

	/** The issues that it blocks while it is open, in byte order, each once. */
	final blocks:Array<String>;

	/** Its open parent, or "". */
	final parent:String;
}

/**
	Reads the blocking decoration that `bd list` prints after each issue, as
	upstream's embedded BlockingAnnotator does (internal/storage/issueops,
	ExecuteBlockingAnnotation and GetBlockingInfoForIssuesInTx).

	What: the request's IDs, each once, in first-mention order. Each ID is
	routed to the wisp or the issue dependency table (PartitionWispIDsInTx);
	its outbound `blocks` and `parent-child` rows name its blockers and its
	parent, and the inbound `blocks` rows of both dependency tables name the
	issues that it blocks. A closed blocker, or a closed issue for its inbound
	rows, counts for nothing. A missing wisp table means no wisps.
	How: batched IN queries of 200 IDs in the caller's read transaction.
	Upstream's list ignores every failure of this read, so the caller does too.
**/
@:goNative
final class SqlBlockingAnnotation {
	/** Upstream queryBatchSize. */
	static inline final BATCH_SIZE = 200;

	static final BLOCKED_BY_TARGET = "COALESCE(d.depends_on_issue_id, d.depends_on_wisp_id, d.depends_on_external)";

	public static function annotate(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, IssueBlocking>> {
		// ValidateBlockingRequest refuses an empty ID.
		for (index in 0...ids.length)
			if (ids[index] == "")
				return Failure('validation failed: annotate blocking id $index is empty');
		final anchors = new Array<String>();
		final seen = new Map<String, Bool>();
		for (id in ids)
			if (!seen.exists(id)) {
				seen.set(id, true);
				anchors.push(id);
			}
		final blockedBy = new Map<String, Array<String>>();
		final blocks = new Map<String, Array<String>>();
		final parents = new Map<String, String>();
		if (anchors.length > 0) {
			final wispIds = switch SqlIssueBatchReader.readWispIdSet(context, transaction, anchors) {
				case Failure(message): return Failure('partition wisp ids: $message');
				case Success(value): value;
			};
			final wisps = [for (id in anchors) if (wispIds.exists(id)) id];
			final permanent = [for (id in anchors) if (!wispIds.exists(id)) id];
			if (wisps.length > 0)
				switch readBlockedBy(context, transaction, wisps, "wisp_dependencies", blockedBy, parents) {
					case Failure(message):
						return Failure(message);
					case Success(_):
				}
			if (permanent.length > 0)
				switch readBlockedBy(context, transaction, permanent, "dependencies", blockedBy, parents) {
					case Failure(message):
						return Failure(message);
					case Success(_):
				}
			switch readBlocks(context, transaction, anchors, blocks) {
				case Failure(message):
					return Failure(message);
				case Success(_):
			}
		}
		final result = new Map<String, IssueBlocking>();
		for (id in anchors) {
			final parent = parents.get(id);
			result.set(id, {
				blockedBy: sortedDistinct(blockedBy.get(id)),
				blocks: sortedDistinct(blocks.get(id)),
				parent: parent == null ? "" : parent
			});
		}
		return Success(result);
	}

	/** Upstream queryBlockedByInfo: the outbound rows of one dependency table; a later parent row wins. */
	static function readBlockedBy(context:Context, transaction:Tx, ids:Array<String>, table:String, blockedBy:Map<String, Array<String>>,
			parents:Map<String, String>):StoreResult<Bool> {
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final queried = transaction.queryNativeContext(context,
				'SELECT d.issue_id, $BLOCKED_BY_TARGET AS depends_on_id, d.type FROM $table d ' +
				'WHERE d.issue_id IN (${placeholders(batch)}) AND d.type IN (\'blocks\', \'parent-child\')',
				...arguments);
			if (queried.error != null) {
				if (table == "wisp_dependencies" && isTableNotExist(queried.error))
					continue;
				return Failure('get blocked-by info from $table: ${queried.error.text()}');
			}
			final rows = queried.rows;
			final edges = new Array<{issue:String, blocker:String, kind:String}>();
			while (rows.next()) {
				final issue = go.NativePointer.of("");
				final blocker = go.NativePointer.of("");
				final kind = go.NativePointer.of("");
				final scanError = rows.scan(issue, blocker, kind);
				if (scanError != null) {
					rows.close();
					return Failure('get blocking info: scan blocked-by: ${scanError.toString()}');
				}
				edges.push({issue: issue.get(), blocker: blocker.get(), kind: kind.get()});
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('get blocking info: blocked-by rows: ${rowError.toString()}');
			final statuses = switch readStatuses(context, transaction, [for (edge in edges) edge.blocker]) {
				case Failure(message): return Failure('get blocking info: blocker status: $message');
				case Success(value): value;
			};
			for (edge in edges) {
				if (statuses.get(edge.blocker) == "closed")
					continue;
				if (edge.kind == "parent-child") {
					parents.set(edge.issue, edge.blocker);
					continue;
				}
				var list = blockedBy.get(edge.issue);
				if (list == null) {
					list = [];
					blockedBy.set(edge.issue, list);
				}
				list.push(edge.blocker);
			}
		}
		return Success(true);
	}

	/** Upstream queryBlocksInfo: the inbound `blocks` rows of both dependency tables; a closed issue blocks nothing. */
	static function readBlocks(context:Context, transaction:Tx, ids:Array<String>, blocks:Map<String, Array<String>>):StoreResult<Bool> {
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final statuses = switch readStatuses(context, transaction, batch) {
				case Failure(message): return Failure('get blocking info: blocker status: $message');
				case Success(value): value;
			};
			final arguments:Array<Dynamic> = [for (id in batch) id];
			for (table in ["dependencies", "wisp_dependencies"]) {
				final queried = transaction.queryNativeContext(context,
					'SELECT $BLOCKED_BY_TARGET AS depends_on_id, d.issue_id, d.type FROM $table d ' +
					'WHERE $BLOCKED_BY_TARGET IN (${placeholders(batch)}) AND d.type IN (\'blocks\', \'parent-child\')',
					...arguments);
				if (queried.error != null) {
					if (table == "wisp_dependencies" && isTableNotExist(queried.error))
						continue;
					return Failure('get blocks info from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final blocker = go.NativePointer.of("");
					final blocked = go.NativePointer.of("");
					final kind = go.NativePointer.of("");
					final scanError = rows.scan(blocker, blocked, kind);
					if (scanError != null) {
						rows.close();
						return Failure('get blocking info: scan blocks: ${scanError.toString()}');
					}
					if (statuses.get(blocker.get()) == "closed" || kind.get() == "parent-child")
						continue;
					var list = blocks.get(blocker.get());
					if (list == null) {
						list = [];
						blocks.set(blocker.get(), list);
					}
					list.push(blocked.get());
				}
				rows.close();
				final rowError = rows.err();
				if (rowError != null)
					return Failure('get blocking info: blocks rows: ${rowError.toString()}');
			}
		}
		return Success(true);
	}

	/** Upstream loadStatusByIDInTx: an ID in both tables takes its wisps status. */
	static function readStatuses(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, String>> {
		final statuses = new Map<String, String>();
		if (ids.length == 0)
			return Success(statuses);
		for (table in ["issues", "wisps"]) {
			var start = 0;
			while (start < ids.length) {
				final batch = ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				final arguments:Array<Dynamic> = [for (id in batch) id];
				final queried = transaction.queryNativeContext(context, 'SELECT id, status FROM $table WHERE id IN (${placeholders(batch)})', ...arguments);
				if (queried.error != null) {
					if (table == "wisps" && isTableNotExist(queried.error))
						break;
					return Failure('status from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final id = go.NativePointer.of("");
					final status = go.NativePointer.of("");
					final scanError = rows.scan(id, status);
					if (scanError != null) {
						rows.close();
						return Failure('scan status: ${scanError.toString()}');
					}
					statuses.set(id.get(), status.get());
				}
				rows.close();
				final rowError = rows.err();
				if (rowError != null)
					return Failure('status rows from $table: ${rowError.toString()}');
			}
		}
		return Success(statuses);
	}

	static function placeholders(batch:Array<String>):String {
		return [for (_ in batch) "?"].join(",");
	}

	/** Upstream sortedDistinctIDs: byte order, each ID once, never null. */
	static function sortedDistinct(ids:Null<Array<String>>):Array<String> {
		if (ids == null)
			return [];
		final seen = new Map<String, Bool>();
		final distinct = new Array<String>();
		for (id in ids)
			if (!seen.exists(id)) {
				seen.set(id, true);
				distinct.push(id);
			}
		distinct.sort(compareUtf8);
		return distinct;
	}
}
