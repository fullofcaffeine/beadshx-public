package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueFilter.IssueFilterTables;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;

/** One count step: its value, or upstream's error text and the driver error that the missing-table checks read. */
enum IssueCountRead<T> {
	CountValue(value:T);
	CountFailed(message:String, error:Null<go.NativeError>);
}

/** The buckets of a grouped count: each display key once, in the order it was first counted. */
@:goNative
final class IssueCountBuckets {
	public final keys = new Array<String>();

	final counts = new Map<String, Int>();

	public function new() {}

	/** Go's `counts[key] += count`, added in Go's `int`. */
	public function add(key:String, count:Int):Void {
		final known = counts.get(key);
		if (known == null)
			keys.push(key);
		counts.set(key, known == null ? count : GoInt.add(known, count));
	}

	/** Go's `counts[key] = count`. */
	public function set(key:String, count:Int):Void {
		if (!counts.exists(key))
			keys.push(key);
		counts.set(key, count);
	}

	public function count(key:String):Int {
		final known = counts.get(key);
		return known == null ? 0 : known;
	}

	/** The sum of the buckets, as Go adds them in `int`. */
	public function total():Int {
		var sum = 0;
		for (key in keys)
			sum = GoInt.add(sum, count(key));
		return sum;
	}
}

/**
	Counts issues as upstream's store-backed issueops.Counter does
	(internal/workapi/storecounter/counter.go).

	What: workapi.BuildCountFilter (internal/workapi/count.go), then
	issueops.CountIssuesInTx and CountIssuesByGroupInTx
	(internal/storage/issueops/count.go): the issues table, the wisps table
	merged in unless the filter skips it, and an ephemeral filter routed to the
	wisps table first. A missing wisps table counts as none.
	How: each count runs in one read transaction that the caller owns.
**/
@:goNative
final class SqlIssueCountReader {
	/**
		Upstream BuildCountFilter. `infraTypes` is the workspace's infra
		vocabulary, which only a request with --include-infra reads: counting
		an infra type then routes to the wisps tier.
	**/
	public static function buildCountFilter(request:CountRequest, infraTypes:Array<String>):StoreResult<IssueSearchFilter> {
		final filter = new IssueSearchFilter();
		filter.titleSearch = request.titleSearch;
		filter.titleContains = request.titleContains;
		filter.descriptionContains = request.descriptionContains;
		filter.notesContains = request.notesContains;
		switch SqlIssueFilter.filterTimes([for (bound in request.timeFilters) if (countsTime(bound)) bound]) {
			case Failure(message):
				return Failure(message);
			case Success(times):
				filter.times = times;
		}
		filter.emptyDescription = request.emptyDescription;
		filter.noAssignee = request.noAssignee;
		filter.noLabels = request.noLabels;
		filter.priority = request.priority;
		filter.priorityMin = request.priorityMin;
		filter.priorityMax = request.priorityMax;
		// Status and type are taken as written: an unknown name matches nothing.
		if (request.status != "" && request.status != "all")
			filter.status = request.status;
		if (request.issueType != "")
			filter.issueType = request.issueType;
		if (request.assignee != "")
			filter.assignee = request.assignee;
		filter.labels = SqlIssueFilter.normalizedEntries(request.labels);
		filter.labelsAny = SqlIssueFilter.normalizedEntries(request.labelsAny);
		filter.ids = SqlIssueFilter.normalizedEntries(request.idFilter.split(","));
		if (request.includeInfra) {
			// applyCountIncludeInfra: the cardinality of `bd list --include-infra --all`.
			filter.skipWisps = false;
			filter.isTemplate = FlagFalse;
			if (request.issueType != "gate")
				filter.excludeTypes.push("gate");
			if (request.issueType != "" && infraTypes.indexOf(request.issueType) >= 0)
				filter.ephemeral = FlagTrue;
		} else {
			filter.skipWisps = true;
		}
		return Success(filter);
	}

	/** The time bounds of a count request: created, updated and closed. */
	static function countsTime(bound:IssueListTimeFilter):Bool {
		return switch bound {
			case CreatedAfter(_) | CreatedBefore(_) | UpdatedAfter(_) | UpdatedBefore(_) | ClosedAfter(_) | ClosedBefore(_): true;
			case DeferAfter(_) | DeferBefore(_) | DueAfter(_) | DueBefore(_): false;
		};
	}

	/** Upstream CountIssuesInTx with no query text. */
	public static function countIssues(context:Context, transaction:Tx, filter:IssueSearchFilter):StoreResult<Int> {
		if (filter.ephemeral.match(FlagTrue)) {
			var wisps = 0;
			switch countTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES) {
				case CountValue(value):
					wisps = value;
				case CountFailed(message, error) if (!isTableNotExist(error)):
					return Failure('count wisps (ephemeral filter): $message');
				case CountFailed(_, _):
			}
			if (wisps > 0)
				return Success(wisps);
			// The wisps table is missing or matched nothing: count the issues table, as the search does.
			return switch countTable(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES) {
				case CountValue(value): Success(value);
				case CountFailed(message, _): Failure('count issues (ephemeral fall-through): $message');
			};
		}
		final issues = switch countTable(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES) {
			case CountValue(value): value;
			case CountFailed(message, _): return Failure('count issues: $message');
		};
		if (filter.skipWisps)
			return Success(issues);
		return switch countTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES) {
			case CountValue(wisps): Success(GoInt.add(issues, wisps));
			case CountFailed(message, error) if (!isTableNotExist(error)): Failure('count wisps (merge): $message');
			case CountFailed(_, _): Success(issues);
		};
	}

	/** Upstream CountIssuesByGroupInTx: each display key with its count, in no particular order. */
	public static function countIssuesByGroup(context:Context, transaction:Tx, filter:IssueSearchFilter, group:CountGroup):StoreResult<IssueCountBuckets> {
		final name = groupName(group);
		if (filter.ephemeral.match(FlagTrue)) {
			var wisps = new IssueCountBuckets();
			switch countGroupForTables(context, transaction, filter, group, SqlIssueFilter.WISP_TABLES) {
				case CountValue(value):
					wisps = value;
				case CountFailed(message, error) if (!isTableNotExist(error)):
					return Failure('count wisps by $name (ephemeral filter): $message');
				case CountFailed(_, _):
			}
			if (wisps.total() > 0)
				return Success(wisps);
			return switch countGroupForTables(context, transaction, filter, group, SqlIssueFilter.ISSUE_TABLES) {
				case CountValue(value): Success(value);
				case CountFailed(message, _): Failure('count issues by $name (ephemeral fall-through): $message');
			};
		}
		final counts = switch countGroupForTables(context, transaction, filter, group, SqlIssueFilter.ISSUE_TABLES) {
			case CountValue(value): value;
			case CountFailed(message, _): return Failure(message);
		};
		if (filter.skipWisps)
			return Success(counts);
		switch countGroupForTables(context, transaction, filter, group, SqlIssueFilter.WISP_TABLES) {
			case CountValue(wisps):
				for (key in wisps.keys)
					counts.add(key, wisps.count(key));
			case CountFailed(message, error) if (!isTableNotExist(error)):
				return Failure('count wisps by $name (merge): $message');
			case CountFailed(_, _):
		}
		return Success(counts);
	}

	/** The storage name of a grouping (upstream workapi.ValidateCountGroup), which the errors print. */
	static function groupName(group:CountGroup):String {
		return switch group {
			case ByStatus: "status";
			case ByPriority: "priority";
			case ByType: "type";
			case ByAssignee: "assignee";
			case ByLabel | Ungrouped: "label";
		};
	}

	/** Upstream countGroupForTablesInTx: one table's grouped count, its keys as `bd count` prints them. */
	static function countGroupForTables(context:Context, transaction:Tx, filter:IssueSearchFilter, group:CountGroup,
			tables:IssueFilterTables):IssueCountRead<IssueCountBuckets> {
		final column = switch group {
			case ByStatus: "status";
			case ByPriority: "priority";
			case ByType: "issue_type";
			case ByAssignee: "assignee";
			case ByLabel | Ungrouped: return countByLabel(context, transaction, filter, tables);
		};
		final raw = switch countByColumn(context, transaction, filter, column, tables) {
			case CountValue(value): value;
			case CountFailed(message, error): return CountFailed(message, error);
		};
		final counts = new IssueCountBuckets();
		for (key in raw.keys) {
			final display = switch group {
				case ByPriority: 'P$key';
				case ByAssignee if (key == ""): "(unassigned)";
				case _: key;
			};
			counts.add(display, raw.count(key));
		}
		return CountValue(counts);
	}

	/** Upstream countTableInTx: `SELECT COUNT(*)` of one table under the filter. */
	static function countTable(context:Context, transaction:Tx, filter:IssueSearchFilter, tables:IssueFilterTables):IssueCountRead<Int> {
		final where = SqlIssueFilter.buildFilterClauses(filter, tables);
		return countRow(context, transaction, 'SELECT COUNT(*) FROM ${tables.main}${whereSql(where.clauses)}', where.arguments);
	}

	/** Upstream countByColumnInTx: the raw column values, NULL read as empty, with their counts. */
	static function countByColumn(context:Context, transaction:Tx, filter:IssueSearchFilter, column:String,
			tables:IssueFilterTables):IssueCountRead<IssueCountBuckets> {
		final where = SqlIssueFilter.buildFilterClauses(filter, tables);
		final query = 'SELECT COALESCE(CAST($column AS CHAR), \'\'), COUNT(*) FROM ${tables.main}${whereSql(where.clauses)} GROUP BY $column';
		final queried = transaction.queryNativeContext(context, query, ...where.arguments);
		if (queried.error != null)
			return CountFailed('count by column $column: ${queried.error.text()}', queried.error);
		final rows = queried.rows;
		final counts = new IssueCountBuckets();
		while (rows.next()) {
			final key = go.NativePointer.of("");
			final count = go.NativePointer.of(0);
			final scanError = rows.scanNative(key, count);
			if (scanError != null) {
				rows.closeNative();
				return CountFailed('scan count row: ${scanError.text()}', scanError);
			}
			counts.add(key.get(), count.get());
		}
		final rowError = rows.errNative();
		rows.closeNative();
		return rowError != null ? CountFailed(rowError.text(), rowError) : CountValue(counts);
	}

	/**
		Upstream countByLabelInTx: each label of the matching issues, from a
		subquery rather than a join, then the matching issues without a label
		as `(no labels)` when there are any.
	**/
	static function countByLabel(context:Context, transaction:Tx, filter:IssueSearchFilter, tables:IssueFilterTables):IssueCountRead<IssueCountBuckets> {
		final where = SqlIssueFilter.buildFilterClauses(filter, tables);
		final filterSql = whereSql(where.clauses);
		final queried = transaction.queryNativeContext(context,
			'SELECT l.label, COUNT(*) FROM ${tables.labels} l WHERE l.issue_id IN (SELECT id FROM ${tables.main}$filterSql) GROUP BY l.label',
			...where.arguments);
		if (queried.error != null)
			return CountFailed('count by label: ${queried.error.text()}', queried.error);
		final rows = queried.rows;
		final counts = new IssueCountBuckets();
		while (rows.next()) {
			final label = go.NativePointer.of("");
			final count = go.NativePointer.of(0);
			final scanError = rows.scanNative(label, count);
			if (scanError != null) {
				rows.closeNative();
				return CountFailed('scan label count: ${scanError.text()}', scanError);
			}
			counts.add(label.get(), count.get());
		}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return CountFailed(rowError.text(), rowError);
		final unlabeled = 'id NOT IN (SELECT DISTINCT issue_id FROM ${tables.labels})';
		final unlabeledSql = filterSql == "" ? ' WHERE $unlabeled' : '$filterSql AND $unlabeled';
		return switch countRow(context, transaction, 'SELECT COUNT(*) FROM ${tables.main}$unlabeledSql', where.arguments) {
			case CountValue(unlabeledCount):
				if (unlabeledCount > 0)
					counts.set("(no labels)", unlabeledCount);
				CountValue(counts);
			case CountFailed(message, error):
				CountFailed('count no-label issues: $message', error);
		};
	}

	/** ` WHERE <clauses>` joined with AND, or nothing for no clauses. */
	static function whereSql(clauses:Array<String>):String {
		return clauses.length == 0 ? "" : " WHERE " + clauses.join(" AND ");
	}

	/** One `COUNT(*)` row, read as `QueryRowContext(...).Scan` reads it, with the same errors. */
	static function countRow(context:Context, transaction:Tx, query:String, arguments:Array<Dynamic>):IssueCountRead<Int> {
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return CountFailed(queried.error.text(), queried.error);
		final rows = queried.rows;
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			return rowError != null ? CountFailed(rowError.text(), rowError) : CountFailed("sql: no rows in result set", null);
		}
		final count = go.NativePointer.of(0);
		final scanError = rows.scanNative(count);
		final closeError = rows.closeNative();
		if (scanError != null)
			return CountFailed(scanError.text(), scanError);
		if (closeError != null)
			return CountFailed(closeError.text(), closeError);
		return CountValue(count.get());
	}
}
