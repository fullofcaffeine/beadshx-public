package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.NullTime;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.Time;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;

/** One dependency row, as upstream `scanDependencyRow` reads it for export. */
typedef ExportDependency = {
	final issueId:String;
	final dependsOnId:String;
	final type:String;

	/** RFC 3339 with nanoseconds, or Go's zero time when the column is NULL. */
	final createdAt:String;

	final createdBy:String;
	final metadata:String;
	final threadId:String;
}

/** One comment row, as upstream `getCommentsForIDsInto` reads it. */
typedef ExportComment = {
	final id:String;
	final issueId:String;
	final author:String;
	final text:String;
	final createdAt:String;
}

/** One issue and everything that upstream `bd export` attaches to it. */
typedef ExportIssue = {
	final fields:SqlIssueFields;

	/** Labels in upstream's `ORDER BY issue_id, label` order. */
	final labels:Array<String>;

	/** Dependencies in upstream's `ORDER BY issue_id, depends_on_id, type, id` order. */
	final dependencies:Array<ExportDependency>;

	/** Comments in upstream's `ORDER BY issue_id, created_at, id` order. */
	final comments:Array<ExportComment>;

	/** `blocks` edges from this issue, in both dependency tables. */
	final dependencyCount:Int;

	/** `blocks` edges to this issue, in both dependency tables. */
	final dependentCount:Int;

	final commentCount:Int;

	/** Upstream's `wisp_plane` marker: a no-history row that lives in the wisps table. */
	final wispPlane:Bool;
}

/** One plane of issue tables: durable or wisp. */
private typedef ExportPlane = {
	final labels:String;
	final dependencies:String;
	final comments:String;
}

/**
	The read half of upstream `bd export --all` in embedded mode, in one
	caller-owned read transaction.

	Why: the snapshot artifact (BHX-M08-09) prints, for each issue, the line
	that upstream v1.2.1 `bd export --all` prints. This ports the reads that
	produce that line, so authored Haxe owns them instead of upstream Go.

	What: a port of `runExportFromSource` (cmd/bd/export.go) with `--all`, up
	to the records it marshals, and of the queries it reaches through the
	classic store: `SearchIssues` with an empty filter (`issueops.searchInTx`),
	`LoadExportRelations` (cmd/bd/export_source.go), which calls
	`GetLabelsForIssuesInTx`, `GetDependencyRecordsForIssuesInTx`,
	`GetCommentsForIssuesInTx`, `GetCommentCountsInTx` and
	`GetDependencyCountsInTx`, and `WispPlaneIDs`
	(`PartitionWispIDsInTx`). Every relation query keeps upstream's SQL,
	including its `ORDER BY`, so each issue's lists keep upstream's order.

	How, and where this differs from upstream on purpose:
	- The record set is every issue. `--all` adds no type, template or wisp
	  filter. The owner exclusion (`export.exclude_owners`) is not applied: the
	  snapshot covers every issue.
	- Upstream orders each table's search by priority, creation time and ID;
	  callers here sort the result themselves, so the search has no ORDER BY.
	- Upstream's embedded store runs each bulk load in its own transaction and
	  treats a failed load as empty. This read runs in one transaction, reads
	  the wisp partition once for every loader, and fails on any error, so a
	  partial read can never pass for a complete one.
**/
@:goNative
final class SqlExportReader {
	static inline final BATCH_SIZE = 200;

	/** Upstream `issueops.DepTargetExpr`. */
	static inline final DEPENDENCY_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	/** Go's `time.RFC3339Nano`, the layout of `time.Time.MarshalJSON`. */
	static inline final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";

	/** `json.Marshal` of Go's zero `time.Time`. */
	static inline final GO_ZERO_TIME = "0001-01-01T00:00:00Z";

	static final DURABLE:ExportPlane = {labels: "labels", dependencies: "dependencies", comments: "comments"};
	static final WISP:ExportPlane = {labels: "wisp_labels", dependencies: "wisp_dependencies", comments: "wisp_comments"};

	/** Every issue and its relations, in the search's table order (durable rows first). */
	public static function readAllIssues(context:Context, transaction:Tx):StoreResult<Array<ExportIssue>> {
		final rows = switch searchAllIssues(context, transaction) {
			case Failure(message): return Failure('failed to search issues: $message');
			case Success(value): value;
		};
		final ids = [for (row in rows) row.id];
		final wisps = switch partitionWispIds(context, transaction, ids) {
			case Failure(message): return Failure('failed to load relational data: $message');
			case Success(value): value;
		};
		final durableIds = [for (id in ids) if (!wisps.exists(id)) id];
		final wispIds = [for (id in ids) if (wisps.exists(id)) id];

		final labels = new Map<String, Array<String>>();
		final dependencies = new Map<String, Array<ExportDependency>>();
		final comments = new Map<String, Array<ExportComment>>();
		final commentCounts = new Map<String, Int>();
		// Upstream's loaders read the wisp table first, except for comments, which read the durable table first.
		final loaders:Array<() -> RelationLoad> = [
			() -> loadLabels(context, transaction, WISP, wispIds, labels),
			() -> loadLabels(context, transaction, DURABLE, durableIds, labels),
			() -> loadDependencies(context, transaction, WISP, wispIds, dependencies),
			() -> loadDependencies(context, transaction, DURABLE, durableIds, dependencies),
			() -> loadComments(context, transaction, DURABLE, durableIds, comments),
			() -> loadComments(context, transaction, WISP, wispIds, comments),
			() -> loadCommentCounts(context, transaction, WISP, wispIds, commentCounts),
			() -> loadCommentCounts(context, transaction, DURABLE, durableIds, commentCounts)
		];
		for (load in loaders)
			switch load() {
				case LoadFailed(message):
					return Failure('failed to load relational data: $message');
				case Loaded:
			}
		final counts = switch readDependencyCounts(context, transaction, ids) {
			case Failure(message): return Failure('failed to load relational data: $message');
			case Success(value): value;
		};

		final issues = new Array<ExportIssue>();
		for (row in rows) {
			final issueLabels = labels.get(row.id);
			final issueDependencies = dependencies.get(row.id);
			final issueComments = comments.get(row.id);
			final commentCount = commentCounts.get(row.id);
			final count = counts.get(row.id);
			issues.push({
				fields: row,
				labels: issueLabels == null ? [] : issueLabels,
				dependencies: issueDependencies == null ? [] : issueDependencies,
				comments: issueComments == null ? [] : issueComments,
				dependencyCount: count == null ? 0 : count.dependencies,
				dependentCount: count == null ? 0 : count.dependents,
				commentCount: commentCount == null ? 0 : commentCount,
				// Upstream asks for the plane only of no-history rows that are not ephemeral.
				wispPlane: row.noHistory && !row.ephemeral && wisps.exists(row.id)
			});
		}
		return Success(issues);
	}

	/**
		Upstream `searchInTx` with an empty filter: the issues table, then, when
		the wisps table has a row, the wisps table, whose row wins when an ID is
		in both. A missing wisps table is no wisps.
	**/
	static function searchAllIssues(context:Context, transaction:Tx):StoreResult<Array<SqlIssueFields>> {
		final durable = switch searchTable(context, transaction, "issues") {
			case SearchFailed(message, _): return Failure('search issues: $message');
			case Searched(rows): rows;
		};
		final empty = switch wispsEmptyOrMissing(context, transaction) {
			case Failure(message): return Failure('search wisps (merge): probe: $message');
			case Success(value): value;
		};
		if (empty)
			return Success(durable);
		final wisps = switch searchTable(context, transaction, "wisps") {
			case SearchFailed(_, true): [];
			case SearchFailed(message, false): return Failure('search wisps (merge): $message');
			case Searched(rows): rows;
		};
		if (wisps.length == 0)
			return Success(durable);
		final wispIds = new Map<String, Bool>();
		for (wisp in wisps)
			wispIds.set(wisp.id, true);
		return Success([for (row in durable) if (!wispIds.exists(row.id)) row].concat(wisps));
	}

	/** Upstream `searchTableInTxT` for one table, without a filter, order or limit. */
	static function searchTable(context:Context, transaction:Tx, table:String):SearchResult {
		final queried = transaction.queryNativeContext(context, 'SELECT $SQL_ISSUE_COLUMNS FROM $table LEFT JOIN leases ON leases.issue_id = $table.id');
		if (queried.error != null)
			return SearchFailed('search $table: ${queried.error.text()}', isTableNotExist(queried.error));
		final rows = queried.rows;
		final results = new Array<SqlIssueFields>();
		final seen = new Map<String, Bool>();
		while (rows.next())
			switch scanSqlIssueFieldsNative(rows, "") {
				case SqlIssueScanned(fields):
					// Upstream skips a repeated ID (GH#3567).
					if (!seen.exists(fields.id)) {
						seen.set(fields.id, true);
						results.push(fields);
					}
				case SqlIssueScanFailure(error):
					rows.close();
					return SearchFailed('search $table: scan: ${error.text()}', isTableNotExist(error));
				case SqlIssueDecodeFailure(message):
					rows.close();
					return SearchFailed('search $table: scan: $message', false);
			}
		rows.close();
		final rowError = rows.errNative();
		if (rowError != null)
			return SearchFailed('search $table: rows: ${rowError.text()}', isTableNotExist(rowError));
		return Searched(results);
	}

	/** Upstream `wispsTableEmptyOrMissingInTx`: `SELECT 1 FROM wisps LIMIT 1` through `QueryRow.Scan`. */
	static function wispsEmptyOrMissing(context:Context, transaction:Tx):StoreResult<Bool> {
		final probe = transaction.queryNativeContext(context, "SELECT 1 FROM wisps LIMIT 1");
		if (probe.error != null)
			return isTableNotExist(probe.error) ? Success(true) : Failure(probe.error.text());
		final present = probe.rows.next();
		final rowError = probe.rows.errNative();
		final closeError = probe.rows.closeNative();
		final failure = rowError != null ? rowError : closeError;
		if (failure != null)
			return isTableNotExist(failure) ? Success(true) : Failure(failure.text());
		return Success(!present);
	}

	/** Upstream `PartitionWispIDsInTx`, as the set of IDs in the wisps table. */
	public static function partitionWispIds(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, Bool>> {
		final wisps = new Map<String, Bool>();
		if (ids.length == 0)
			return Success(wisps);
		switch wispsEmptyOrMissing(context, transaction) {
			case Failure(message):
				return Failure('partition wisp ids: probe: $message');
			case Success(true):
				return Success(wisps);
			case Success(false):
		}
		for (batch in batches(ids)) {
			final queried = transaction.queryNativeContext(context, 'SELECT id FROM wisps WHERE id IN (${placeholders(batch)})', ...arguments(batch));
			if (queried.error != null) {
				// The wisps table may not exist yet on older schemas: no wisps.
				if (isTableNotExist(queried.error))
					return Success(new Map<String, Bool>());
				return Failure('partition wisp ids: ${queried.error.text()}');
			}
			final rows = queried.rows;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final scanError = rows.scan(id);
				if (scanError != null) {
					rows.close();
					return Failure('partition wisp ids: scan: ${scanError.toString()}');
				}
				wisps.set(id.get(), true);
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('partition wisp ids: rows: ${rowError.toString()}');
		}
		return Success(wisps);
	}

	/** Upstream `getLabelsIntoFromTable`. */
	static function loadLabels(context:Context, transaction:Tx, plane:ExportPlane, ids:Array<String>, into:Map<String, Array<String>>):RelationLoad {
		final table = plane.labels;
		for (batch in batches(ids)) {
			final queried = transaction.queryContext(context,
				'SELECT issue_id, label FROM $table WHERE issue_id IN (${placeholders(batch)}) ORDER BY issue_id, label', ...arguments(batch));
			if (queried.value2 != null)
				return LoadFailed('get labels for issues from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = rows.scan(issueId, label);
				if (scanError != null) {
					rows.close();
					return LoadFailed('get labels for issues: scan: ${scanError.toString()}');
				}
				append(into, issueId.get(), label.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return LoadFailed('get labels for issues: rows: ${rowError.toString()}');
		}
		return Loaded;
	}

	/** Upstream `getDependencyRecordsIntoFromTable` with `scanDependencyRow`. */
	static function loadDependencies(context:Context, transaction:Tx, plane:ExportPlane, ids:Array<String>,
			into:Map<String, Array<ExportDependency>>):RelationLoad {
		final table = plane.dependencies;
		for (batch in batches(ids)) {
			final queried = transaction.queryContext(context,
				'SELECT issue_id, $DEPENDENCY_TARGET AS depends_on_id, type, created_at, created_by, metadata, thread_id FROM $table WHERE issue_id IN (${placeholders(batch)}) ORDER BY issue_id, depends_on_id, type, id',
				...arguments(batch));
			if (queried.value2 != null)
				return LoadFailed('get dependency records from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final dependsOnId = go.NativePointer.of("");
				final type = go.NativePointer.of("");
				final createdAt = new NullTime();
				final createdBy = go.NativePointer.of("");
				final metadata = new NullString();
				final threadId = new NullString();
				final scanError = rows.scan(issueId, dependsOnId, type, createdAt, createdBy, metadata, threadId);
				if (scanError != null) {
					rows.close();
					return LoadFailed('get dependency records: scan: scan dependency: ${scanError.toString()}');
				}
				append(into, issueId.get(), {
					issueId: issueId.get(),
					dependsOnId: dependsOnId.get(),
					type: type.get(),
					createdAt: createdAt.valid ? goTime(createdAt.time) : GO_ZERO_TIME,
					createdBy: createdBy.get(),
					metadata: SqlIssueRow.value(metadata),
					threadId: SqlIssueRow.value(threadId)
				});
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return LoadFailed('get dependency records: rows: ${rowError.toString()}');
		}
		return Loaded;
	}

	/** Upstream `getCommentsForIDsInto`. */
	static function loadComments(context:Context, transaction:Tx, plane:ExportPlane, ids:Array<String>, into:Map<String, Array<ExportComment>>):RelationLoad {
		final table = plane.comments;
		for (batch in batches(ids)) {
			final queried = transaction.queryContext(context,
				'SELECT id, issue_id, author, text, created_at FROM $table WHERE issue_id IN (${placeholders(batch)}) ORDER BY issue_id, created_at ASC, id ASC',
				...arguments(batch));
			if (queried.value2 != null)
				return LoadFailed('get comments from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final issueId = go.NativePointer.of("");
				final author = go.NativePointer.of("");
				final text = go.NativePointer.of("");
				final createdAt = new Time();
				final scanError = rows.scan(id, issueId, author, text, createdAt);
				if (scanError != null) {
					rows.close();
					return LoadFailed('scan comment: ${scanError.toString()}');
				}
				append(into, issueId.get(), {
					id: id.get(),
					issueId: issueId.get(),
					author: author.get(),
					text: text.get(),
					createdAt: goTime(createdAt)
				});
			}
			final rowError = rows.err();
			rows.close();
			if (rowError != null)
				return LoadFailed(rowError.toString());
		}
		return Loaded;
	}

	/** The comment count loop of upstream `GetCommentCountsInTx`. */
	static function loadCommentCounts(context:Context, transaction:Tx, plane:ExportPlane, ids:Array<String>, into:Map<String, Int>):RelationLoad {
		final table = plane.comments;
		for (batch in batches(ids)) {
			final queried = transaction.queryContext(context,
				'SELECT issue_id, COUNT(*) as cnt FROM $table WHERE issue_id IN (${placeholders(batch)}) GROUP BY issue_id', ...arguments(batch));
			if (queried.value2 != null)
				return LoadFailed('get comment counts from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final count = go.NativePointer.of(0);
				final scanError = rows.scan(issueId, count);
				if (scanError != null) {
					rows.close();
					return LoadFailed('get comment counts: scan: ${scanError.toString()}');
				}
				into.set(issueId.get(), count.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return LoadFailed('get comment counts: rows: ${rowError.toString()}');
		}
		return Loaded;
	}

	/**
		Upstream `GetDependencyCountsInTx`: `blocks` edges from and to each ID in
		`dependencies`, and in `wisp_dependencies` unless the wisps table is
		empty or missing. A missing `wisp_dependencies` table counts nothing.
	**/
	static function readDependencyCounts(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, DependencyCounts>> {
		final counts = new Map<String, DependencyCounts>();
		for (id in ids)
			counts.set(id, {dependencies: 0, dependents: 0});
		if (ids.length == 0)
			return Success(counts);
		final tables = switch wispsEmptyOrMissing(context, transaction) {
			case Failure(message): return Failure('get dependency counts: probe: $message');
			case Success(true): ["dependencies"];
			case Success(false): ["dependencies", "wisp_dependencies"];
		};
		for (batch in batches(ids))
			for (table in tables) {
				final optional = table == "wisp_dependencies";
				final blockers = 'SELECT issue_id, COUNT(*) as cnt FROM $table WHERE issue_id IN (${placeholders(batch)}) AND type = \'blocks\' GROUP BY issue_id';
				switch addCounts(context, transaction, blockers, batch, counts, true) {
					case CountsAdded:
					case CountsTableMissing(_) if (optional):
						continue;
					case CountsTableMissing(message) | CountsFailed(message):
						return Failure('get dependency counts (blockers from $table): $message');
				}
				final dependents = 'SELECT $DEPENDENCY_TARGET AS depends_on_id, COUNT(*) as cnt FROM $table WHERE $DEPENDENCY_TARGET IN (${placeholders(batch)}) AND type = \'blocks\' GROUP BY $DEPENDENCY_TARGET';
				switch addCounts(context, transaction, dependents, batch, counts, false) {
					case CountsAdded:
					case CountsTableMissing(_) if (optional):
						continue;
					case CountsTableMissing(message) | CountsFailed(message):
						return Failure('get dependency counts (dependents from $table): $message');
				}
			}
		return Success(counts);
	}

	/** One count query of `GetDependencyCountsInTx`; only IDs of the export set count. */
	static function addCounts(context:Context, transaction:Tx, query:String, batch:Array<String>, counts:Map<String, DependencyCounts>,
			blockers:Bool):CountsRead {
		final queried = transaction.queryNativeContext(context, query, ...arguments(batch));
		if (queried.error != null)
			return isTableNotExist(queried.error) ? CountsTableMissing(queried.error.text()) : CountsFailed(queried.error.text());
		final rows = queried.rows;
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final count = go.NativePointer.of(0);
			final scanError = rows.scan(id, count);
			if (scanError != null) {
				rows.close();
				return CountsFailed(blockers ? 'scan blocker: ${scanError.toString()}' : 'scan dependent: ${scanError.toString()}');
			}
			final current = counts.get(id.get());
			if (current != null)
				counts.set(id.get(), blockers ? {dependencies: current.dependencies + count.get(), dependents: current.dependents} : {
					dependencies: current.dependencies,
					dependents: current.dependents + count.get()
				});
		}
		rows.close();
		final rowError = rows.err();
		if (rowError != null)
			return CountsFailed(blockers ? 'blocker rows: ${rowError.toString()}' : 'dependent rows: ${rowError.toString()}');
		return CountsAdded;
	}

	/** Go's `json.Marshal` of a `time.Time`: RFC 3339 with the nanoseconds that are not zero. */
	static inline function goTime(time:Time):String {
		return time.format(GO_RFC3339_NANO);
	}

	static function batches(ids:Array<String>):Array<Array<String>> {
		return [
			for (start in 0...Math.ceil(ids.length / BATCH_SIZE))
				ids.slice(start * BATCH_SIZE, (start + 1) * BATCH_SIZE)
		];
	}

	static function placeholders(batch:Array<String>):String {
		return [for (_ in batch) "?"].join(",");
	}

	/** database/sql binds the IDs as variadic `any` values. */
	static function arguments(batch:Array<String>):Array<Dynamic> {
		return [for (id in batch) id];
	}

	static function append<T>(into:Map<String, Array<T>>, id:String, value:T):Void {
		final values = into.get(id);
		if (values == null)
			into.set(id, [value]);
		else
			values.push(value);
	}
}

private typedef DependencyCounts = {
	final dependencies:Int;
	final dependents:Int;
}

private enum SearchResult {
	Searched(rows:Array<SqlIssueFields>);

	/** `tableMissing`: upstream tolerates this failure for the wisps table. */
	SearchFailed(message:String, tableMissing:Bool);
}

private enum CountsRead {
	CountsAdded;
	CountsTableMissing(message:String);
	CountsFailed(message:String);
}

/** The outcome of one relation loader. */
private enum RelationLoad {
	Loaded;
	LoadFailed(message:String);
}
