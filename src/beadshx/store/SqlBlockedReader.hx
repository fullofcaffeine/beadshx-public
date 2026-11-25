package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.RelatedIssue;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueBatchReader.readIssuesByIds;

/** One blocked issue and the open issues that block it, in upstream's order. */
typedef BlockedIssue = {
	final issue:RelatedIssue;
	final blockedBy:Array<String>;
}

/**
	Lists blocked issues as upstream issueops.GetBlockedIssuesInTx does, for `bd blocked` and
	the blocked list of `ready --explain`.

	Upstream does not recompute blocking: the stored `is_blocked` column selects the
	issues, open `blocks`, `waits-for` and `conditional-blocks` targets name their
	blockers, and an issue with no open direct blocker names its parent instead.
	`parentId` keeps only that parent's children and IDs below it. The result is
	sorted by priority, then newest first; upstream breaks remaining ties at random,
	so this port breaks them by ID. Optional wisp tables may be missing. The caller
	owns the transaction.
**/
@:goNative
final class SqlBlockedReader {
	static final DEP_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	public static function readSqlBlocked(context:Context, transaction:Tx, parentId:String):StoreResult<Array<BlockedIssue>> {
		final blockedIds = new Array<String>();
		final seen = new Map<String, Bool>();
		for (table in ["issues", "wisps"]) {
			final queried = transaction.queryNativeContext(context,
				'SELECT id FROM $table WHERE is_blocked = 1 AND status <> \'closed\' AND status <> \'pinned\'');
			if (queried.error != null) {
				if (table == "wisps" && isTableNotExist(queried.error))
					continue;
				return Failure('read blocked ids from $table: ${queried.error.text()}');
			}
			final rows = queried.rows;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final scanError = rows.scan(id);
				if (scanError != null) {
					rows.close();
					return Failure('scan blocked id from $table: ${scanError.toString()}');
				}
				if (!seen.exists(id.get())) {
					seen.set(id.get(), true);
					blockedIds.push(id.get());
				}
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('blocked id rows from $table: ${rowError.toString()}');
		}
		if (blockedIds.length == 0)
			return Success([]);

		final blockers = new Map<String, Array<String>>();
		final blockerOrder = new Array<String>();
		final edges = switch readBlockingEdges(context, transaction, blockedIds) {
			case Failure(message): return Failure('get blocking deps: $message');
			case Success(value): value;
		};
		if (edges.length > 0) {
			final targets = new Array<String>();
			final seenTargets = new Map<String, Bool>();
			for (edge in edges)
				if (!seenTargets.exists(edge.target)) {
					seenTargets.set(edge.target, true);
					targets.push(edge.target);
				}
			final statuses = switch readStatuses(context, transaction, targets) {
				case Failure(message): return Failure('blocker target status: $message');
				case Success(value): value;
			};
			for (edge in edges) {
				final status = statuses.get(edge.target);
				if (status == null || status == "closed" || status == "pinned")
					continue;
				var list = blockers.get(edge.issue);
				if (list == null) {
					list = [];
					blockers.set(edge.issue, list);
					blockerOrder.push(edge.issue);
				}
				list.push(edge.target);
			}
		}

		final inherited = [for (id in blockedIds) if (!blockers.exists(id)) id];
		if (inherited.length > 0)
			switch readParents(context, transaction, inherited) {
				case Failure(_):
					// Upstream ignores parent lookup errors here.
				case Success(parents):
					for (child in inherited) {
						final parent = parents.get(child);
						if (parent != null && !blockers.exists(child)) {
							blockers.set(child, [parent]);
							blockerOrder.push(child);
						}
					}
			}

		final issues = switch readIssuesByIds(context, transaction, blockerOrder) {
			case Failure(message): return Failure('batch-fetch blocked issues: $message');
			case Success(value): value;
		};
		var children:Null<Map<String, Bool>> = null;
		if (parentId != "") {
			final kept = switch readChildren(context, transaction, parentId) {
				case Failure(_): new Map<String, Bool>();
				case Success(value): value;
			};
			for (id in blockerOrder)
				if (StringTools.startsWith(id, parentId + "."))
					kept.set(id, true);
			children = kept;
		}
		final result = new Array<BlockedIssue>();
		for (issue in issues) {
			final list = blockers.get(issue.id);
			if (list == null || (children != null && !children.exists(issue.id)))
				continue;
			result.push({issue: issue, blockedBy: list});
		}
		result.sort(compareBlocked);
		return Success(result);
	}

	/** Priority ascending, then created_at descending, then ID as the tie-break. */
	static function compareBlocked(left:BlockedIssue, right:BlockedIssue):Int {
		final priority = left.issue.priority.compare(right.issue.priority);
		if (priority != 0)
			return priority;
		if (left.issue.createdAt != right.issue.createdAt)
			return left.issue.createdAt > right.issue.createdAt ? -1 : 1;
		return left.issue.id < right.issue.id ? -1 : (left.issue.id > right.issue.id ? 1 : 0);
	}

	/** One query per blocked ID and table, like upstream; the row order decides `blocked_by` order. */
	static function readBlockingEdges(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Array<{issue:String, target:String}>> {
		final edges = new Array<{issue:String, target:String}>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final query = 'SELECT issue_id, $DEP_TARGET AS depends_on_id, type, metadata FROM $table '
				+ "WHERE issue_id = ? AND (type = 'blocks' OR type = 'waits-for' OR type = 'conditional-blocks')";
			for (id in ids) {
				final queried = transaction.queryNativeContext(context, query, id);
				if (queried.error != null) {
					if (table == "wisp_dependencies" && isTableNotExist(queried.error))
						break;
					return Failure('compute blocked IDs: deps from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final issue = go.NativePointer.of("");
					final target = go.NativePointer.of("");
					final kind = go.NativePointer.of("");
					final metadata = go.NativePointer.of("");
					final scanError = rows.scan(issue, target, kind, metadata);
					if (scanError != null) {
						rows.close();
						return Failure('compute blocked IDs: scan dep: ${scanError.toString()}');
					}
					edges.push({issue: issue.get(), target: target.get()});
				}
				rows.close();
				final rowError = rows.err();
				if (rowError != null)
					return Failure('compute blocked IDs: dep rows from $table: ${rowError.toString()}');
			}
		}
		return Success(edges);
	}

	/** Ports loadStatusByIDInTx: when an ID is in both tables, the wisps status wins. */
	static function readStatuses(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, String>> {
		final statuses = new Map<String, String>();
		for (table in ["issues", "wisps"]) {
			for (id in ids) {
				final queried = transaction.queryNativeContext(context, 'SELECT id, status FROM $table WHERE id = ?', id);
				if (queried.error != null) {
					if (table == "wisps" && isTableNotExist(queried.error))
						break;
					return Failure('status from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final rowId = go.NativePointer.of("");
					final status = go.NativePointer.of("");
					final scanError = rows.scan(rowId, status);
					if (scanError != null) {
						rows.close();
						return Failure('scan status: ${scanError.toString()}');
					}
					statuses.set(rowId.get(), status.get());
				}
				rows.close();
				final rowError = rows.err();
				if (rowError != null)
					return Failure('status rows from $table: ${rowError.toString()}');
			}
		}
		return Success(statuses);
	}

	/** Ports loadParentIDsForChildrenInTx: a later row or table replaces an earlier parent. */
	static function readParents(context:Context, transaction:Tx, children:Array<String>):StoreResult<Map<String, String>> {
		final parents = new Map<String, String>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final query = 'SELECT issue_id, $DEP_TARGET AS depends_on_id FROM $table WHERE issue_id = ? AND type = \'parent-child\'';
			for (child in children) {
				final queried = transaction.queryNativeContext(context, query, child);
				if (queried.error != null) {
					if (table == "wisp_dependencies" && isTableNotExist(queried.error))
						break;
					return Failure('candidate parents from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final childId = go.NativePointer.of("");
					final parentId = go.NativePointer.of("");
					final scanError = rows.scan(childId, parentId);
					if (scanError != null) {
						rows.close();
						return Failure('scan candidate parent: ${scanError.toString()}');
					}
					parents.set(childId.get(), parentId.get());
				}
				rows.close();
				final rowError = rows.err();
				if (rowError != null)
					return Failure('candidate parent rows from $table: ${rowError.toString()}');
			}
		}
		return Success(parents);
	}

	/** Ports GetChildrenOfIssuesInTx for one parent. */
	static function readChildren(context:Context, transaction:Tx, parentId:String):StoreResult<Map<String, Bool>> {
		final children = new Map<String, Bool>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final queried = transaction.queryNativeContext(context, 'SELECT issue_id FROM $table WHERE type = \'parent-child\' AND $DEP_TARGET = ?', parentId);
			if (queried.error != null) {
				if (table == "wisp_dependencies" && isTableNotExist(queried.error))
					break;
				return Failure('get children of issues from $table: ${queried.error.text()}');
			}
			final rows = queried.rows;
			while (rows.next()) {
				final child = go.NativePointer.of("");
				final scanError = rows.scan(child);
				if (scanError != null) {
					rows.close();
					return Failure('scan child: ${scanError.toString()}');
				}
				children.set(child.get(), true);
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('children rows from $table: ${rowError.toString()}');
		}
		return Success(children);
	}
}
