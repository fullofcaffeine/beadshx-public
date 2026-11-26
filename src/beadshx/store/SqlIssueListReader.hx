package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.TimePkg;
import beadshx.query.QueryPage;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.JsonValue.GoJsonFieldKind;
import beadshx.store.JsonValue.GoJsonStruct;
import beadshx.store.JsonValue.decodeGoStructArray;
import beadshx.store.SqlIssueFilter.IssueFilterFlag;
import beadshx.store.SqlIssueFilter.IssueFilterTables;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** A failed search step: upstream's error text, or its defensive row cap. */
enum IssueSearchFailure {
	SearchFailed(message:String, error:Null<go.NativeError>);
	SearchRowCap(found:Int, source:String, cap:Int);
}

/** One table's rows, or why the table could not be searched. */
enum IssueSearchRows {
	SearchRows(items:Array<IssueListItem>);
	SearchStopped(failure:IssueSearchFailure);
}

/** An optional table probe: present, missing, or failed with upstream's error. */
enum TableProbe {
	TableHasRows;
	TableEmpty;
	TableMissing;
	TableProbeFailed(error:go.NativeError);
}

/**
	Reads one list page as upstream's store-backed issueops.Reader.List does
	(internal/workapi/storereader/reader.go).

	What: the list configuration and filter (SqlIssueFilter), then
	issueops.SearchIssuesWithCountsInTx (internal/storage/issueops/search_counts.go):
	the counts query over issues and, unless the filter skips them, wisps, with a
	wisp winning over an issue with the same ID; its sort, limit and row cap; and
	the page epilogue workapi.FinishPageAt. A --ready page reads the ready query
	of the same filter instead (SqlReadyWorkReader). It adds no blocking
	annotations: EmbeddedIssueListReader reads them after the page.
	How: one read transaction that the caller owns.
**/
@:goNative
final class SqlIssueListReader {
	static final GO_RFC3339 = "2006-01-02T15:04:05Z07:00";
	static final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";
	static final SORTABLE_TIME = "2006-01-02T15:04:05.000000000";

	/** sqlbuild.IssueBaseColumns qualified with `i.`, then the lease columns (ReadyWorkIssueColumns). */
	static final ISSUE_COLUMNS = [
		for (column in SqlIssueRow.SQL_ISSUE_COLUMNS.split(", "))
			StringTools.startsWith(column, "leases.") ? column : 'i.$column'
	].join(", ");

	/** types.Dependency's JSON fields, which the counts query's deps_json carries. */
	static final DEPENDENCY_JSON:GoJsonStruct = {
		packageName: "types",
		name: "Dependency",
		fields: [
			{tag: "id", kind: GoStringField},
			{tag: "issue_id", kind: GoStringField},
			{tag: "depends_on_id", kind: GoStringField},
			{tag: "type", kind: GoStringField},
			{tag: "created_at", kind: GoStringField},
			{tag: "created_by", kind: GoStringField},
			{tag: "metadata", kind: GoStringField},
			{tag: "thread_id", kind: GoStringField}
		]
	};

	public static function readSqlIssueList(context:Context, transaction:Tx, request:IssueListRequest, limit:Int,
			layers:IssueListConfigLayers):IssueListResult {
		final config = SqlIssueFilter.loadListConfig(context, transaction, layers);
		final filter = switch SqlIssueFilter.buildListFilter(request, limit, config) {
			case Failure(message): return ListFailure(message);
			case Success(value): value;
		};
		final offset = switch request.offset {
			case IntPresent(value) if (value > 0): value;
			case IntPresent(_) | IntAbsent: 0;
		};
		// WithRowsBeforeThePage, then WithFetchOneExtra: reach past the skipped rows and one more.
		// In Go's int: a bound that this build parsed natively can pass 32 bits (see GoInt).
		if (offset > 0 && filter.limit > 0)
			filter.limit = GoInt.add(filter.limit, offset);
		if (filter.limit > 0) {
			if (filter.maxRows > 0 && filter.limit == filter.maxRows)
				filter.maxRows = GoInt.add(filter.maxRows, 1);
			filter.limit = GoInt.add(filter.limit, 1);
		}
		final searched = request.ready ? SqlReadyWorkReader.readReadyWork(context, transaction,
			SqlReadyWorkReader.fromListFilter(filter)) : searchWithCounts(context, transaction, filter);
		final items = switch searched {
			case SearchRows(value): value;
			case SearchStopped(SearchFailed(message, _)): return ListFailure(message);
			case SearchStopped(SearchRowCap(found, source, cap)): return ListRowLimitExceeded(found, source, cap);
		};
		// FinishPageAt: the display order, the skip, the cut and the has-more verdict.
		sortForDisplay(items, request.sortBy, request.reverse);
		var page = offset >= items.length ? [] : items.slice(offset);
		var hasMore = false;
		if (limit > 0 && page.length > limit) {
			page = page.slice(0, limit);
			hasMore = true;
		}
		return ListSuccess({items: page, hasMore: hasMore, formatted: ""});
	}

	/**
		The read of `bd search` and of `label list-all`, as the native facade
		ran it on upstream's store: SearchIssuesWithCountsInTx with the query
		text and the filter that the facade built from the request, then the
		display order (workapi.SortIssuesWithCounts).

		What the filter takes: the limit, 50 when the request has none; the
		status selector, checked against `customStatusNames` (upstream
		ApplyStatusFilter), unless it is empty or `all`; the assignee and the
		type as written; the labels; the description, notes and external
		reference substrings; the empty-description, no-assignee and no-labels
		checks; the created, updated and closed bounds; the priority range;
		and the metadata filters. The issues and the wisps are both searched.
	**/
	public static function readSqlIssueSearch(context:Context, transaction:Tx, query:String, request:IssueListRequest,
			customStatusNames:Array<String>):IssueListResult {
		final filter = new IssueSearchFilter();
		filter.queryText = query;
		filter.limit = switch request.limit {
			case IntPresent(value): value;
			case IntAbsent: 50;
		};
		if (request.status != "" && request.status != "all") {
			final refused = SqlIssueFilter.applyStatusSelector(filter, request.status, customStatusNames);
			if (refused != null)
				return ListFailure(refused);
		}
		if (request.assignee != "")
			filter.assignee = request.assignee;
		if (request.issueType != "")
			filter.issueType = request.issueType;
		filter.labels = request.labels;
		filter.labelsAny = request.labelsAny;
		filter.descriptionContains = request.descriptionContains;
		filter.notesContains = request.notesContains;
		filter.externalRefContains = request.externalContains;
		filter.emptyDescription = request.emptyDescription;
		filter.noAssignee = request.noAssignee;
		filter.noLabels = request.noLabels;
		final searchTimes = [
			for (bound in request.timeFilters)
				if (bound.match(CreatedAfter(_) | CreatedBefore(_) | UpdatedAfter(_) | UpdatedBefore(_) | ClosedAfter(_) | ClosedBefore(_))) bound
		];
		switch SqlIssueFilter.filterTimes(searchTimes) {
			case Failure(message):
				return ListFailure(message);
			case Success(times):
				filter.times = times;
		}
		filter.priorityMin = request.priorityMin;
		filter.priorityMax = request.priorityMax;
		filter.metadataFields = request.metadataFields;
		filter.hasMetadataKey = request.hasMetadataKey;
		// BuildIssueFilterClauses refuses an invalid metadata key before it builds the query.
		final metadataError = SqlIssueFilter.metadataClauseError(filter.metadataFields, filter.hasMetadataKey);
		if (metadataError != null)
			return ListFailure(metadataError);
		final items = switch searchWithCounts(context, transaction, filter) {
			case SearchRows(value): value;
			case SearchStopped(SearchFailed(message, _)): return ListFailure(message);
			case SearchStopped(SearchRowCap(found, source, cap)): return ListRowLimitExceeded(found, source, cap);
		};
		sortForDisplay(items, request.sortBy, request.reverse);
		return ListSuccess({items: items, hasMore: false, formatted: ""});
	}

	/**
		Every issue and wisp as query candidates, in the order that the native
		facade read them for `bd query`: issueops.Reader.List with AllFlag and
		IncludeAllTypes, which lifts every default status, pinned, template,
		gate and infra-type suppression and reads the wisps too, under the
		default order (priority, newest first, then the ID). The facade paged
		that list 50 rows at a time; one read without a limit gives the same
		rows in the same order.
	**/
	public static function readQueryCandidates(context:Context, transaction:Tx):StoreResult<Array<IssueListItem>> {
		return switch searchWithCounts(context, transaction, new IssueSearchFilter()) {
			case SearchRows(items): Success(items);
			case SearchStopped(SearchFailed(message, _)): Failure(message);
			// The filter sets no row cap, so this branch only completes the switch.
			case SearchStopped(SearchRowCap(found, _, cap)): Failure('row cap: $found over $cap');
		};
	}

	/** Upstream SearchIssuesWithCountsInTx, with the filter's query text. */
	static function searchWithCounts(context:Context, transaction:Tx, filter:IssueSearchFilter):IssueSearchRows {
		final wispDependencies = switch probeTable(context, transaction, "wisp_dependencies") {
			case TableHasRows | TableEmpty: true;
			case TableMissing: false;
			case TableProbeFailed(error): return failed('search issues with counts: wisp dependency probe: ${error.text()}', error);
		};
		final ephemeralOnly = switch filter.ephemeral {
			case FlagTrue: true;
			case FlagFalse | FlagUnset: false;
		};
		if (ephemeralOnly) {
			final wispsEmpty = switch probeTable(context, transaction, "wisps") {
				case TableHasRows: false;
				case TableEmpty | TableMissing: true;
				case TableProbeFailed(error): return failed('search issues with counts: ephemeral wisp probe: ${error.text()}', error);
			};
			if (!wispsEmpty && wispDependencies)
				switch searchTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES, true) {
					case SearchRows(wisps) if (wisps.length > 0):
						return finishSearch(wisps, filter);
					case SearchRows(_):
					case SearchStopped(SearchFailed(_, error)) if (isTableNotExist(error)):
					case SearchStopped(failure):
						return SearchStopped(failure);
				}
			return switch searchTable(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES, wispDependencies) {
				case SearchRows(issues): finishSearch(issues, filter);
				case stopped: stopped;
			};
		}

		final issues = switch searchTable(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES, wispDependencies) {
			case SearchRows(value): value;
			case stopped: return stopped;
		};
		if (filter.skipWisps)
			return finishSearch(issues, filter);
		switch probeTable(context, transaction, "wisps") {
			case TableHasRows:
			case TableEmpty | TableMissing:
				return finishSearch(issues, filter);
			case TableProbeFailed(error):
				return failed('search issues with counts: wisp probe: ${error.text()}', error);
		}
		if (!wispDependencies)
			return finishSearch(issues, filter);
		final wisps = switch searchTable(context, transaction, filter, SqlIssueFilter.WISP_TABLES, true) {
			case SearchRows(value): value;
			case SearchStopped(SearchFailed(_, error)) if (isTableNotExist(error)): return finishSearch(issues, filter);
			case stopped: return stopped;
		};
		if (wisps.length == 0)
			return finishSearch(issues, filter);
		// Prefer the wisp record when an ID is in both tables.
		final wispIds = new Map<String, Bool>();
		for (wisp in wisps)
			wispIds.set(wisp.id, true);
		final merged = [for (issue in issues) if (!wispIds.exists(issue.id)) issue];
		for (wisp in wisps)
			merged.push(wisp);
		return finishSearch(merged, filter);
	}

	/** Upstream runFilterSearchQueryInTx for one table family. */
	static function searchTable(context:Context, transaction:Tx, filter:IssueSearchFilter, tables:IssueFilterTables,
			wispReverseDependencies:Bool):IssueSearchRows {
		final where = SqlIssueFilter.buildFilterClauses(filter, tables);
		final whereSql = where.clauses.length == 0 ? "" : "WHERE " + where.clauses.join(" AND ");
		final idSort = filter.sortBy == "id";
		final bound = effectiveSearchLimit(filter.limit, filter.maxRows);
		final limitSql = bound > 0 && !idSort ? 'LIMIT $bound' : "";
		final query = countsQuery(tables, [], whereSql, orderBy(filter.sortBy, filter.sortDesc), limitSql, wispReverseDependencies, filter.skipLabels,
			filter.skipCounts);
		final items = switch scanCountsRows(context, transaction, tables.main, query, where.arguments, filter.lite) {
			case SearchRows(value): value;
			case stopped: return stopped;
		};
		if (idSort) {
			// goSideSortAndTrim: byte order by ID, then the bound the query could not apply.
			items.sort((left, right) -> filter.sortDesc ? compareUtf8(right.id, left.id) : compareUtf8(left.id, right.id));
			if (bound > 0 && items.length > bound)
				return SearchRows(items.slice(0, bound));
		}
		return SearchRows(items);
	}

	/** Upstream scanCountsRowsInTx: run a counts query and keep the first row of each ID. */
	public static function scanCountsRows(context:Context, transaction:Tx, mainTable:String, query:String, arguments:Array<Dynamic>,
			lite:Bool):IssueSearchRows {
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return failed('search count $mainTable: ${queried.error.text()}', queried.error);
		final rows = queried.rows;
		final items = new Array<IssueListItem>();
		final seen = new Map<String, Bool>();
		while (rows.next()) {
			final labelsJson = new NullString();
			final dependencyCount = go.NativePointer.of(0);
			final dependentCount = go.NativePointer.of(0);
			final commentCount = go.NativePointer.of(0);
			final parentId = new NullString();
			final dependenciesJson = new NullString();
			final scanned = SqlIssueRow.scanSqlIssueFieldsWithExtra(rows, "", [
				labelsJson,
				dependencyCount,
				dependentCount,
				commentCount,
				parentId,
				dependenciesJson
			]);
			final fields = switch scanned {
				case SqlIssueScanned(value): value;
				case SqlIssueScanFailure(error):
					rows.closeNative();
					return failed('scan issue with counts: ${error.text()}', error);
				case SqlIssueDecodeFailure(message):
					rows.closeNative();
					return failed('scan issue with counts: $message', null);
			};
			final item = switch listItem(fields, lite, labelsJson, dependencyCount.get(), dependentCount.get(), commentCount.get(), parentId,
				dependenciesJson) {
				case Failure(message):
					rows.closeNative();
					return failed(message, null);
				case Success(value): value;
			};
			if (seen.exists(item.id))
				continue;
			seen.set(item.id, true);
			items.push(item);
		}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return failed('search count $mainTable: rows: ${rowError.text()}', rowError);
		return SearchRows(items);
	}

	/**
		Upstream sqlbuild.SearchCountsSQL. Without `ids` it is the predicate form:
		`whereSql` narrows the driver before the joins, and `orderSql` and
		`limitSql` follow them. With `ids` it is the by-IDs form: the driver and
		each aggregate read only those IDs, whose arguments countsArguments gives.
	**/
	public static function countsQuery(tables:IssueFilterTables, ids:Array<String>, whereSql:String, orderSql:String, limitSql:String,
			wispReverseDependencies:Bool, skipLabels:Bool, skipCounts:Bool):String {
		final target = SqlIssueFilter.DEPENDENCY_TARGET;
		final byIds = ids.length > 0;
		final inSql = [for (_ in ids) "?"].join(",");
		final idWhere = byIds ? 'WHERE issue_id IN ($inSql)' : "";
		final idAnd = byIds ? ' AND issue_id IN ($inSql)' : "";
		final targetAnd = byIds ? ' AND $target IN ($inSql)' : "";
		var reverseBlockers = 'SELECT $target AS dep_id FROM dependencies WHERE type = \'blocks\'$targetAnd';
		if (wispReverseDependencies)
			reverseBlockers += ' UNION ALL SELECT $target AS dep_id FROM wisp_dependencies WHERE type = \'blocks\'$targetAnd';
		final labelsSelect = skipLabels ? "NULL AS labels_json" : "l.labels_json AS labels_json";
		final labelsJoin = skipLabels ? "" : ' LEFT JOIN (SELECT issue_id, JSON_ARRAYAGG(label) AS labels_json FROM ${tables.labels} $idWhere GROUP BY issue_id) l ON l.issue_id = i.id';
		final countsSelect = skipCounts ? "0 AS dep_count, 0 AS rdep_count, 0 AS comment_count" : "COALESCE(dc.cnt, 0) AS dep_count, COALESCE(rc.cnt, 0) AS rdep_count, COALESCE(cc.cnt, 0) AS comment_count";
		final countsJoins = skipCounts ? "" : ' LEFT JOIN (SELECT issue_id, COUNT(*) AS cnt FROM ${tables.dependencies} WHERE type = \'blocks\'$idAnd GROUP BY issue_id) dc ON dc.issue_id = i.id'
			+ ' LEFT JOIN (SELECT dep_id, COUNT(*) AS cnt FROM ($reverseBlockers) all_blockers GROUP BY dep_id) rc ON rc.dep_id = i.id'
			+ ' LEFT JOIN (SELECT issue_id, COUNT(*) AS cnt FROM ${tables.comments} $idWhere GROUP BY issue_id) cc ON cc.issue_id = i.id';
		final driver = byIds || whereSql == "" ? '${tables.main} i' : '(SELECT i.* FROM ${tables.main} i $whereSql) i';
		final outer = byIds ? 'WHERE i.id IN ($inSql)' : '$orderSql $limitSql';
		final dependencyJson = "JSON_OBJECT('issue_id', issue_id, 'depends_on_id', "
			+ target
			+ ", 'type', type,"
			+ " 'created_at', DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ'), 'created_by', created_by,"
			+ " 'metadata', CAST(metadata AS CHAR), 'thread_id', thread_id)";
		return 'SELECT $ISSUE_COLUMNS, $labelsSelect, $countsSelect, pc.parent_id AS parent_id, d.deps_json AS deps_json'
			+ ' FROM $driver LEFT JOIN leases ON leases.issue_id = i.id$labelsJoin$countsJoins'
			+
			' LEFT JOIN (SELECT issue_id, MIN($target) AS parent_id FROM ${tables.dependencies} WHERE type = \'parent-child\'$idAnd GROUP BY issue_id) pc ON pc.issue_id = i.id'
			+
			' LEFT JOIN (SELECT issue_id, JSON_ARRAYAGG($dependencyJson) AS deps_json FROM ${tables.dependencies} $idWhere GROUP BY issue_id) d ON d.issue_id = i.id'
			+ ' $outer';
	}

	/** The arguments of a by-IDs counts query: the IDs once for each place that reads them, in placeholder order. */
	public static function countsArguments(ids:Array<String>, wispReverseDependencies:Bool, skipLabels:Bool, skipCounts:Bool):Array<Dynamic> {
		var places = 3; // the parent, the dependency JSON and the driver
		if (!skipLabels)
			places++;
		if (!skipCounts)
			places += wispReverseDependencies ? 4 : 3;
		final arguments = new Array<Dynamic>();
		for (_ in 0...places)
			for (id in ids)
				arguments.push(id);
		return arguments;
	}

	/** Upstream ScanReadyWorkRowWithCounts after the issue columns, and the facade's list-item projection. */
	static function listItem(fields:SqlIssueFields, lite:Bool, labelsJson:NullString, dependencyCount:Int, dependentCount:Int, commentCount:Int,
			parentId:NullString, dependenciesJson:NullString):StoreResult<IssueListItem> {
		var labels = new Array<String>();
		if (labelsJson.valid && labelsJson.string != "")
			switch JsonValue.parseStringArrayNullAsEmpty(labelsJson.string, "labels_json") {
				case Failure(message):
					return Failure('scan issue with counts: parse labels_json: $message');
				case Success(values):
					values.sort(compareUtf8);
					labels = values;
			}
		final dependencies = new Array<IssueListDependency>();
		if (dependenciesJson.valid && dependenciesJson.string != "")
			switch decodeGoStructArray(dependenciesJson.string, DEPENDENCY_JSON) {
				case Failure(message):
					return Failure('scan issue with counts: parse deps_json: $message');
				case Success(rows):
					for (row in rows) {
						if (row == null)
							return Failure("issue list contains an empty dependency edge");
						final createdAt = switch dependencyTime(row.get("created_at")) {
							case Failure(message): return Failure('scan issue with counts: parse deps_json: $message');
							case Success(value): value;
						};
						dependencies.push({
							id: text(row.get("id")),
							issueId: text(row.get("issue_id")),
							dependsOnId: text(row.get("depends_on_id")),
							dependencyType: text(row.get("type")),
							createdAt: createdAt,
							createdBy: text(row.get("created_by")),
							metadata: text(row.get("metadata")),
							threadId: text(row.get("thread_id"))
						});
					}
			}
		final related = relatedIssueFromSql(fields, labels, "");
		return Success({
			id: related.id,
			title: related.title,
			// ScanIssueLiteFrom leaves the heavy text columns empty.
			description: lite ? "" : related.description,
			design: lite ? "" : related.design,
			acceptanceCriteria: lite ? "" : related.acceptanceCriteria,
			notes: lite ? "" : related.notes,
			specId: related.specId,
			status: related.status,
			priority: related.priority,
			issueType: related.issueType,
			assignee: related.assignee,
			owner: related.owner,
			estimatedMinutes: related.estimatedMinutes,
			createdAt: related.createdAt,
			createdBy: related.createdBy,
			updatedAt: related.updatedAt,
			startedAt: related.startedAt,
			closedAt: related.closedAt,
			closeReason: related.closeReason,
			closedBySession: related.closedBySession,
			dueAt: related.dueAt,
			deferUntil: related.deferUntil,
			externalRef: related.externalRef,
			sourceSystem: related.sourceSystem,
			metadata: related.metadata,
			wispType: related.wispType,
			moleculeType: related.moleculeType,
			longFields: lite ? liteLongFields(related.longFields) : related.longFields,
			labels: related.labels,
			dependencies: dependencies,
			dependencyCount: dependencyCount,
			dependentCount: dependentCount,
			commentCount: commentCount,
			parent: parentId.valid ? parentId.string : "",
			blockedBy: [],
			blocks: [],
			blockingParent: ""
		});
	}

	static function liteLongFields(fields:IssueLongFields):IssueLongFields {
		return {
			isBlocked: fields.isBlocked,
			leaseExpiresAt: fields.leaseExpiresAt,
			heartbeatAt: fields.heartbeatAt,
			leaseGrantedNode: fields.leaseGrantedNode,
			compactionLevel: fields.compactionLevel,
			compactedAt: fields.compactedAt,
			compactedAtCommit: fields.compactedAtCommit,
			originalSize: fields.originalSize,
			sender: fields.sender,
			ephemeral: fields.ephemeral,
			noHistory: fields.noHistory,
			storageClass: fields.storageClass,
			pinned: fields.pinned,
			template: fields.template,
			bondedFrom: fields.bondedFrom,
			awaitType: fields.awaitType,
			awaitId: fields.awaitId,
			timeout: fields.timeout,
			timeoutNanos: fields.timeoutNanos,
			waiters: [],
			sourceFormula: fields.sourceFormula,
			sourceLocation: fields.sourceLocation,
			workType: fields.workType,
			eventKind: fields.eventKind,
			actor: fields.actor,
			target: fields.target,
			payload: ""
		};
	}

	/** A types.Dependency created_at as the facade prints it: absent or null is Go's zero time. */
	static function dependencyTime(value:Null<String>):StoreResult<String> {
		if (value == null)
			return Success("0001-01-01T00:00:00Z");
		final parsed = TimePkg.parse(GO_RFC3339, value);
		if (parsed.value2 != null)
			return Failure(parsed.value2.text());
		return Success(parsed.value1.format(GO_RFC3339_NANO));
	}

	static inline function text(value:Null<String>):String {
		return value == null ? "" : value;
	}

	/** Upstream finishSearchIssuesWithCounts: the merge order, the limit cut, then the row cap. */
	static function finishSearch(items:Array<IssueListItem>, filter:IssueSearchFilter):IssueSearchRows {
		sortForMerge(items, filter.sortBy, filter.sortDesc);
		final kept = filter.limit > 0 && items.length > filter.limit ? items.slice(0, filter.limit) : items;
		if (filter.maxRows > 0 && kept.length > filter.maxRows)
			return SearchStopped(SearchRowCap(kept.length, filter.maxRowsSource, filter.maxRows));
		return SearchRows(kept);
	}

	/** Upstream EffectiveSearchLimit: a row cap asks for one row past it. */
	public static function effectiveSearchLimit(limit:Int, maxRows:Int):Int {
		if (maxRows > 0 && (limit == 0 || limit > maxRows))
			return GoInt.add(maxRows, 1);
		return limit;
	}

	/** Upstream sqlbuild.OrderBy on the `i` alias; `id` sorts after the query. */
	static function orderBy(sortBy:String, descending:Bool):String {
		if (sortBy == "id")
			return "";
		final key = sortColumn(sortBy) == null ? "" : sortBy;
		final defaultDescending = key == "created" || key == "updated" || key == "closed";
		final direction = defaultDescending != descending ? "DESC" : "ASC";
		final flipped = direction == "ASC" ? "DESC" : "ASC";
		if (key == "" || key == "priority")
			return 'ORDER BY i.priority $direction, i.created_at DESC, i.id ASC';
		final column = key == "title" ? "LOWER(i.title)" : 'i.${sortColumn(key)}';
		if (key == "closed" || key == "assignee")
			return 'ORDER BY ($column IS NULL) $flipped, $column $direction, i.id ASC';
		return 'ORDER BY $column $direction, i.id ASC';
	}

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

	/** Upstream sqlbuild.Less, the merge order of the issues and wisps legs; a stable sort. */
	static function sortForMerge(items:Array<IssueListItem>, sortBy:String, descending:Bool):Void {
		if (items.length <= 1)
			return;
		if (sortBy == "id") {
			items.sort((left, right) -> descending ? compareUtf8(right.id, left.id) : compareUtf8(left.id, right.id));
			return;
		}
		final key = sortColumn(sortBy) == null ? "" : sortBy;
		final reversed = (key == "created" || key == "updated" || key == "closed") != descending;
		items.sort((left, right) -> {
			final primary = mergeKeyCompare(left, right, key);
			if (primary != 0)
				return reversed ? -primary : primary;
			if (key == "" || key == "priority") {
				final created = compareTimes(left.createdAt, right.createdAt);
				if (created != 0)
					return -created;
			}
			return compareUtf8(left.id, right.id);
		});
	}

	/** Upstream sortKeyCompare: the primary column ascending, NULL first. */
	static function mergeKeyCompare(left:IssueListItem, right:IssueListItem, key:String):Int {
		return switch key {
			case "created": compareTimes(left.createdAt, right.createdAt);
			case "updated": compareTimes(left.updatedAt, right.updatedAt);
			case "closed": compareOptionalTimes(left.closedAt, right.closedAt, true);
			case "status": compareUtf8(left.status, right.status);
			case "type": compareUtf8(left.issueType, right.issueType);
			case "assignee": compareUtf8(left.assignee, right.assignee);
			case "title": compareUtf8(left.title.toLowerCase(), right.title.toLowerCase());
			case _: left.priority.compare(right.priority);
		};
	}

	/** Upstream workapi.SortRows with CompareIssuesBy: a stable display sort, flipped by --reverse. */
	static function sortForDisplay(items:Array<IssueListItem>, sortBy:String, reverse:Bool):Void {
		if (sortBy == "")
			return;
		items.sort((left, right) -> {
			final order = switch sortBy {
				case "priority": left.priority.compare(right.priority);
				case "created": compareTimes(right.createdAt, left.createdAt);
				case "updated": compareTimes(right.updatedAt, left.updatedAt);
				case "closed": -compareOptionalTimes(left.closedAt, right.closedAt, true);
				case "status": compareUtf8(left.status, right.status);
				case "id": QueryPage.naturalCompareIds(left.id, right.id);
				case "title": compareUtf8(left.title.toLowerCase(), right.title.toLowerCase());
				case "type": compareUtf8(left.issueType, right.issueType);
				case "assignee": compareUtf8(left.assignee, right.assignee);
				case _: 0;
			};
			return reverse ? -order : order;
		});
	}

	/**
		Two RFC3339Nano times in time order: each in UTC with all nine fraction
		digits, which orders as text for the years 1 to 9999 that Go formats.
	**/
	public static function compareTimes(left:String, right:String):Int {
		return compareUtf8(sortableTime(left), sortableTime(right));
	}

	public static function sortableTime(value:String):String {
		final parsed = TimePkg.parse(GO_RFC3339_NANO, value);
		return parsed.value2 != null ? value : parsed.value1.utc().format(SORTABLE_TIME);
	}

	/** Two optional times, an empty one first when `emptyFirst`. */
	static function compareOptionalTimes(left:String, right:String, emptyFirst:Bool):Int {
		if (left == "" && right == "")
			return 0;
		if (left == "")
			return emptyFirst ? -1 : 1;
		if (right == "")
			return emptyFirst ? 1 : -1;
		return compareTimes(left, right);
	}

	/** Upstream wispsTableEmptyOrMissingInTx and optionalTableExistsInTx, which share one probe. */
	public static function probeTable(context:Context, transaction:Tx, table:String):TableProbe {
		final probe = transaction.queryNativeContext(context, 'SELECT 1 FROM $table LIMIT 1');
		if (probe.error != null)
			return isTableNotExist(probe.error) ? TableMissing : TableProbeFailed(probe.error);
		final present = probe.rows.next();
		final rowError = probe.rows.errNative();
		final closeError = probe.rows.closeNative();
		if (rowError != null)
			return isTableNotExist(rowError) ? TableMissing : TableProbeFailed(rowError);
		if (closeError != null && present)
			return isTableNotExist(closeError) ? TableMissing : TableProbeFailed(closeError);
		return present ? TableHasRows : TableEmpty;
	}

	static function failed(message:String, error:Null<go.NativeError>):IssueSearchRows {
		return SearchStopped(SearchFailed(message, error));
	}
}
