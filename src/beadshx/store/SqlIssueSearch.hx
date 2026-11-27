package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueFilter.IssueFilterTables;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;

/** One issue as upstream's SearchIssues returns it: its row and its labels. */
typedef SearchedIssue = {
	final fields:SqlIssueFields;
	final labels:Array<String>;
}

/** The issues of a search, or how the search stopped. */
enum SearchedIssues {
	IssuesFound(issues:Array<SearchedIssue>);
	IssuesNotSearched(failure:IssueSearchFailure);
}

/** The IDs of a search, or how the search stopped. */
enum SearchedIssueIds {
	IssueIdsFound(ids:Array<String>);
	IssueIdsNotSearched(failure:IssueSearchFailure);
}

/** What one search leg selects: upstream's idProjection or issueProjection. */
private enum SearchProjection {
	/** `<table>.id`, scanned alone and never hydrated. */
	IdOnly;

	/** IssueSelectColumns with the lease join; labels hydrated, and Pattern B under a limit. */
	FullIssue;
}

/** One row of a leg: the ID always, the issue columns and labels for FullIssue. */
private typedef SearchRow = {
	final id:String;
	final fields:Null<SqlIssueFields>;
	var labels:Array<String>;
}

/** The rows of one leg, or how it stopped. */
private enum SearchLeg {
	LegRows(rows:Array<SearchRow>);
	LegStopped(failure:IssueSearchFailure);
}

/**
	Upstream issueops.SearchIssuesInTx and SearchIssueIDsInTx
	(internal/storage/issueops/search.go), the store call behind `SearchIssues`.

	Why: a failed read must stop where upstream's stops and say what upstream's
	says, and Dolt words a failed query after its SQL, so each query here is
	upstream's query. `ping`, the closed-gate search of `ready --gated` and the
	partial-ID lookup make this call upstream.
	What: searchInTx's legs and words: the issues leg ("search issues: "), then,
	unless the filter skips wisps, the wisp probe ("search wisps (merge):
	probe: ") and the wisps leg ("search wisps (merge): "), whose row wins over
	an issue with the same ID; an ephemeral-only filter searches the wisps
	first ("search wisps (ephemeral filter): "). Each leg is
	searchTableInTxT: the label joins of BuildLabelDrivenSearch, the filter
	clauses, the order, the limit and the scan; with a limit, the full issue
	projection first scans the IDs and then fetches and hydrates their rows
	(Pattern B). The merged rows are sorted as sqlbuild.Less sorts them, cut to
	the limit and checked against the row cap. Dependencies are never
	hydrated: no caller asks for them.
	How: one read transaction that the caller owns.
**/
@:goNative
final class SqlIssueSearch {
	/** Upstream queryBatchSize, the size of each label batch. */
	static inline final BATCH_SIZE = 200;

	/** Upstream SearchIssuesInTx: the issues with their labels. */
	public static function searchIssues(context:Context, transaction:Tx, filter:IssueSearchFilter):SearchedIssues {
		return switch search(context, transaction, filter, FullIssue) {
			case LegStopped(failure): IssuesNotSearched(failure);
			case LegRows(rows): IssuesFound([for (row in rows) {fields: issueFields(row), labels: row.labels}]);
		};
	}

	/** Upstream SearchIssueIDsInTx: the IDs alone. */
	public static function searchIssueIds(context:Context, transaction:Tx, filter:IssueSearchFilter):SearchedIssueIds {
		return switch search(context, transaction, filter, IdOnly) {
			case LegStopped(failure): IssueIdsNotSearched(failure);
			case LegRows(rows): IssueIdsFound([for (row in rows) row.id]);
		};
	}

	/** A FullIssue row always holds its columns. */
	static function issueFields(row:SearchRow):SqlIssueFields {
		final fields = row.fields;
		if (fields == null)
			throw 'search row ${row.id} has no issue columns';
		return fields;
	}

	/** Upstream searchInTx, the wisp-merge wrapper of both projections. */
	static function search(context:Context, transaction:Tx, filter:IssueSearchFilter, projection:SearchProjection):SearchLeg {
		if (filter.ephemeral.match(FlagTrue)) {
			switch searchTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES, projection) {
				case LegStopped(SearchFailed(_, error)) if (isTableNotExist(error)):
				case LegStopped(SearchFailed(message, error)):
					return failed('search wisps (ephemeral filter): $message', error);
				case LegStopped(failure):
					return LegStopped(failure);
				case LegRows(rows) if (rows.length > 0):
					return finish(rows, filter);
				case LegRows(_):
			}
		}
		final issues = switch searchTable(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES, projection) {
			case LegStopped(SearchFailed(message, error)): return failed('search issues: $message', error);
			case LegStopped(failure): return LegStopped(failure);
			case LegRows(rows): rows;
		};
		if (filter.skipWisps || filter.ephemeral.match(FlagTrue))
			return finish(issues, filter);
		switch SqlIssueListReader.probeTable(context, transaction, "wisps") {
			case TableHasRows:
			case TableEmpty | TableMissing:
				return finish(issues, filter);
			case TableProbeFailed(error):
				return failed('search wisps (merge): probe: ${error.text()}', error);
		}
		final wisps = switch searchTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES, projection) {
			case LegStopped(SearchFailed(_, error)) if (isTableNotExist(error)): [];
			case LegStopped(SearchFailed(message, error)): return failed('search wisps (merge): $message', error);
			case LegStopped(failure): return LegStopped(failure);
			case LegRows(rows): rows;
		};
		if (wisps.length == 0)
			return finish(issues, filter);
		final wispIds = new Map<String, Bool>();
		for (wisp in wisps)
			wispIds.set(wisp.id, true);
		final merged = [for (issue in issues) if (!wispIds.exists(issue.id)) issue];
		for (wisp in wisps)
			merged.push(wisp);
		sortMerged(merged, filter.sortBy, filter.sortDesc, projection);
		return finish(merged, filter);
	}

	/** Upstream trimToSearchLimit, then EnforceMaxRowsCap. */
	static function finish(rows:Array<SearchRow>, filter:IssueSearchFilter):SearchLeg {
		final kept = filter.limit > 0 && rows.length > filter.limit ? rows.slice(0, filter.limit) : rows;
		if (filter.maxRows > 0 && kept.length > filter.maxRows)
			return LegStopped(SearchRowCap(kept.length, filter.maxRowsSource, filter.maxRows));
		return LegRows(kept);
	}

	/** Upstream searchTableInTxT for one table family. */
	static function searchTable(context:Context, transaction:Tx, filter:IssueSearchFilter, tables:IssueFilterTables, projection:SearchProjection):SearchLeg {
		if (projection.match(FullIssue) && filter.limit > 0)
			return searchTablePatternB(context, transaction, filter, tables);
		// BuildIssueFilterClauses refuses an invalid metadata key before it builds the query.
		final metadataError = SqlIssueFilter.metadataClauseError(filter.metadataFields, filter.hasMetadataKey);
		if (metadataError != null)
			return failed(metadataError, null);
		// BuildLabelDrivenSearch: each label of the AND set, then the any set, as a join.
		final labels = [for (label in filter.labels) if (label != "") label];
		final labelsAny = [for (label in filter.labelsAny) if (label != "") label];
		final joins = new Array<String>();
		final clauses = new Array<String>();
		final arguments = new Array<Dynamic>();
		for (index in 0...labels.length) {
			final alias = 'label_filter_$index';
			joins.push('JOIN ${tables.labels} $alias ON $alias.issue_id = ${tables.main}.id');
			clauses.push('$alias.label = ?');
			arguments.push(labels[index]);
		}
		if (labelsAny.length > 0) {
			joins.push('JOIN ${tables.labels} label_filter_any ON label_filter_any.issue_id = ${tables.main}.id');
			clauses.push('label_filter_any.label IN (${[for (_ in labelsAny) "?"].join(", ")})');
			for (label in labelsAny)
				arguments.push(label);
		}
		final labelDriven = joins.length > 0;
		final filtered = SqlIssueFilter.buildFilterClauses(filter, tables, !labelDriven);
		for (clause in filtered.clauses)
			clauses.push(clause);
		for (argument in filtered.arguments)
			arguments.push(argument);
		final whereSql = clauses.length == 0 ? "" : "WHERE " + clauses.join(" AND ");
		final idSort = filter.sortBy == "id";
		final bound = SqlIssueListReader.effectiveSearchLimit(filter.limit, filter.maxRows);
		final limitSql = bound > 0 && !idSort ? ' LIMIT $bound' : "";
		var fromSql = labelDriven ? tables.main + " " + joins.join(" ") : tables.main;
		final columns = switch projection {
			case IdOnly: '${tables.main}.id';
			case FullIssue:
				fromSql += ' LEFT JOIN leases ON leases.issue_id = ${tables.main}.id';
				SQL_ISSUE_COLUMNS;
		};
		final select = labelDriven ? "SELECT DISTINCT " : "SELECT ";
		final query = '$select$columns FROM $fromSql $whereSql ${orderBy(filter.sortBy, filter.sortDesc)} $limitSql';
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return failed('search ${tables.main}: ${queried.error.text()}', queried.error);
		final rows = queried.rows;
		final found = new Array<SearchRow>();
		final seen = new Map<String, Bool>();
		while (rows.next()) {
			final row = switch scanRow(rows, projection) {
				case StepDone(value): value;
				case StepFailed(failure):
					rows.closeNative();
					return failed('search ${tables.main}: scan: ${failure.message}', failure.error);
			};
			// GH#3567: a dependency subquery can repeat a row.
			if (seen.exists(row.id))
				continue;
			seen.set(row.id, true);
			found.push(row);
		}
		rows.closeNative();
		final rowError = rows.errNative();
		if (rowError != null)
			return failed('search ${tables.main}: rows: ${rowError.text()}', rowError);
		var results = found;
		if (idSort) {
			// goSideSortAndTrim: byte order by ID, then the bound that the query could not apply.
			results.sort((left, right) -> filter.sortDesc ? compareUtf8(right.id, left.id) : compareUtf8(left.id, right.id));
			if (bound > 0 && results.length > bound)
				results = results.slice(0, bound);
		}
		if (projection.match(FullIssue) && results.length > 0 && !filter.skipLabels)
			switch hydrateLabels(context, transaction, tables, results) {
				case StepFailed(failure):
					return failed('search ${tables.main}: ${failure.message}', failure.error);
				case StepDone(_):
			}
		return LegRows(results);
	}

	/**
		Upstream searchTablePatternBT: the ID leg under the limit, then the rows
		of those IDs, in the ID leg's order, and their labels.
	**/
	static function searchTablePatternB(context:Context, transaction:Tx, filter:IssueSearchFilter, tables:IssueFilterTables):SearchLeg {
		final ids = switch searchTable(context, transaction, filter, tables, IdOnly) {
			case LegStopped(failure): return LegStopped(failure);
			case LegRows(rows): [for (row in rows) row.id];
		};
		if (ids.length == 0)
			return LegRows([]);
		final arguments:Array<Dynamic> = [for (id in ids) id];
		final query = 'SELECT $SQL_ISSUE_COLUMNS FROM ${tables.main} LEFT JOIN leases ON leases.issue_id = ${tables.main}.id WHERE id IN (${[for (_ in ids) "?"].join(",")})';
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return failed('search ${tables.main} (hydrate): ${queried.error.text()}', queried.error);
		final rows = queried.rows;
		final byId = new Map<String, SearchRow>();
		while (rows.next())
			switch scanRow(rows, FullIssue) {
				case StepDone(row):
					byId.set(row.id, row);
				case StepFailed(failure):
					rows.closeNative();
					return failed('search ${tables.main} (hydrate): scan: ${failure.message}', failure.error);
			}
		rows.closeNative();
		final rowError = rows.errNative();
		if (rowError != null)
			return failed('search ${tables.main} (hydrate): rows: ${rowError.text()}', rowError);
		final results = [for (id in ids) if (byId.exists(id)) byId.get(id)];
		if (results.length > 0 && !filter.skipLabels)
			switch hydrateLabels(context, transaction, tables, results) {
				case StepFailed(failure):
					return failed('search ${tables.main} (pattern B): ${failure.message}', failure.error);
				case StepDone(_):
			}
		return LegRows(results);
	}

	/** One scanned row of the projection; a failure keeps the driver's error. */
	static function scanRow(rows:beadshx.nativeextern.database.sql.Rows, projection:SearchProjection):SearchStep<SearchRow> {
		return switch projection {
			case IdOnly:
				final id = go.NativePointer.of("");
				final scanError = rows.scanNative(id);
				scanError != null ? StepFailed({message: scanError.text(), error: scanError}) : StepDone({id: id.get(), fields: null, labels: []});
			case FullIssue:
				switch scanSqlIssueFieldsNative(rows, "") {
					case SqlIssueScanned(fields): StepDone({id: fields.id, fields: fields, labels: []});
					case SqlIssueScanFailure(error): StepFailed({message: error.text(), error: error});
					case SqlIssueDecodeFailure(message): StepFailed({message: message, error: null});
				};
		};
	}

	/**
		Upstream hydrateIssueLabelsAndDeps without dependencies:
		GetLabelsForIssuesFromTableInTx in batches, each issue's labels in the
		order the query gives them ("hydrate labels: ").
	**/
	static function hydrateLabels(context:Context, transaction:Tx, tables:IssueFilterTables, rows:Array<SearchRow>):SearchStep<Bool> {
		final labels = new Map<String, Array<String>>();
		final ids = [for (row in rows) row.id];
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final queried = transaction.queryNativeContext(context,
				'SELECT issue_id, label FROM ${tables.labels} WHERE issue_id IN (${[for (_ in batch) "?"].join(",")}) ORDER BY issue_id, label', ...arguments);
			if (queried.error != null)
				return StepFailed({message: 'hydrate labels: get labels for issues from ${tables.labels}: ${queried.error.text()}', error: queried.error});
			final labelRows = queried.rows;
			while (labelRows.next()) {
				final issueId = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = labelRows.scanNative(issueId, label);
				if (scanError != null) {
					labelRows.closeNative();
					return StepFailed({message: 'hydrate labels: get labels for issues: scan: ${scanError.text()}', error: scanError});
				}
				final values = labels.get(issueId.get());
				if (values == null)
					labels.set(issueId.get(), [label.get()]);
				else
					values.push(label.get());
			}
			labelRows.closeNative();
			final rowError = labelRows.errNative();
			if (rowError != null)
				return StepFailed({message: 'hydrate labels: get labels for issues: rows: ${rowError.text()}', error: rowError});
		}
		for (row in rows) {
			final issueLabels = labels.get(row.id);
			if (issueLabels != null)
				row.labels = issueLabels;
		}
		return StepDone(true);
	}

	/** Upstream sqlbuild.OrderBy without a table qualifier; the `id` key sorts after the query. */
	static function orderBy(sortBy:String, descending:Bool):String {
		if (sortBy == "id")
			return "";
		final key = sortColumn(sortBy) == null ? "" : sortBy;
		final defaultDescending = key == "created" || key == "updated" || key == "closed";
		final direction = defaultDescending != descending ? "DESC" : "ASC";
		final flipped = direction == "ASC" ? "DESC" : "ASC";
		if (key == "" || key == "priority")
			return 'ORDER BY priority $direction, created_at DESC, id ASC';
		final column = key == "title" ? "LOWER(title)" : sortColumn(key);
		if (key == "closed" || key == "assignee")
			return 'ORDER BY ($column IS NULL) $flipped, $column $direction, id ASC';
		return 'ORDER BY $column $direction, id ASC';
	}

	/** Upstream sqlbuild.SortDefs: the column of each sort key. */
	static function sortColumn(sortBy:String):Null<String> {
		return switch sortBy {
			case "" | "priority": "priority";
			case "created": "created_at";
			case "updated": "updated_at";
			case "closed": "closed_at";
			case "status": "status";
			case "type": "issue_type";
			case "assignee": "assignee";
			case "title": "title";
			case _: null;
		};
	}

	/**
		Upstream sortMergedResults: a stable sort of the merged legs with the
		projection's order. The ID projection orders only the `id` key and keeps
		the concatenation for every other key; the issue projection orders as
		sqlbuild.Less does.
	**/
	static function sortMerged(rows:Array<SearchRow>, sortBy:String, descending:Bool, projection:SearchProjection):Void {
		if (rows.length <= 1)
			return;
		if (sortBy == "id") {
			rows.sort((left, right) -> descending ? compareUtf8(right.id, left.id) : compareUtf8(left.id, right.id));
			return;
		}
		if (projection.match(IdOnly))
			return;
		final key = sortColumn(sortBy) == null ? "" : sortBy;
		final reversed = (key == "created" || key == "updated" || key == "closed") != descending;
		rows.sort((left, right) -> {
			final leftFields = issueFields(left);
			final rightFields = issueFields(right);
			final primary = mergeKeyCompare(leftFields, rightFields, key);
			if (primary != 0)
				return reversed ? -primary : primary;
			if (key == "" || key == "priority") {
				final created = SqlIssueListReader.compareTimes(leftFields.createdAt, rightFields.createdAt);
				if (created != 0)
					return -created;
			}
			return compareUtf8(left.id, right.id);
		});
	}

	/** Upstream sortKeyCompare: the primary column ascending, a missing close time first. */
	static function mergeKeyCompare(left:SqlIssueFields, right:SqlIssueFields, key:String):Int {
		return switch key {
			case "created": SqlIssueListReader.compareTimes(left.createdAt, right.createdAt);
			case "updated": SqlIssueListReader.compareTimes(left.updatedAt, right.updatedAt);
			case "closed":
				if (left.closedAt == "" && right.closedAt == "") 0; else if (left.closedAt == "") -1; else if (right.closedAt == "") 1; else
					SqlIssueListReader.compareTimes(left.closedAt, right.closedAt);
			case "status": compareUtf8(left.status, right.status);
			case "type": compareUtf8(left.issueType, right.issueType);
			case "assignee": compareUtf8(left.assignee, right.assignee);
			case "title": compareUtf8(left.title.toLowerCase(), right.title.toLowerCase());
			case _: left.priority.compare(right.priority);
		};
	}

	static function failed(message:String, error:Null<go.NativeError>):SearchLeg {
		return LegStopped(SearchFailed(message, error));
	}
}

/** A failed step: upstream's words and the driver's error, when there is one. */
private typedef StepFailure = {
	final message:String;
	final error:Null<go.NativeError>;
}

/** One step of a leg: its value, or why it failed. */
private enum SearchStep<T> {
	StepDone(value:T);
	StepFailed(failure:StepFailure);
}
