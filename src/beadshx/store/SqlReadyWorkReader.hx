package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.TimePkg;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.relation.RelatedIssue;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueFilter.IssueFilterFlag;
import beadshx.store.SqlIssueFilter.IssueFilterTables;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueListReader.IssueSearchRows;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** Upstream types.WorkFilter, as far as `bd ready` and `bd list --ready` fill it; its status is always open. */
@:goNative
final class ReadyWorkFilter {
	public var issueType = "";
	public var priority = OptionalInt.IntAbsent;
	public var assignee:Null<String> = null;
	public var unassigned = false;
	public var labels = new Array<String>();
	public var labelsAny = new Array<String>();
	public var excludeLabels = new Array<String>();
	public var labelPattern = "";
	public var labelRegex = "";
	public var includeDeferred = false;
	public var includeEphemeral = false;
	public var excludeTypes = new Array<String>();
	public var parentId:Null<String> = null;

	/** `--mol-type`. The ready predicate leaves it out; only the wisp search of GetReadyWork applies it. */
	public var molType:Null<String> = null;

	public var metadataFields = new Array<IssueListMetadataFilter>();
	public var hasMetadataKey = "";

	/** `hybrid`, `priority` or `oldest`; empty sorts as `hybrid`. */
	public var sortPolicy = "";

	public var limit = 0;
	public var maxRows = 0;
	public var maxRowsSource = "";
	public var lite = false;

	public function new() {}
}

/** The WHERE, ORDER BY and LIMIT of one ready query over one table family (upstream readyWorkPredicates). */
private typedef ReadyPredicates = {
	/** Starts with `WHERE `. */
	final whereSql:String;

	/** The arguments of `whereSql` alone, for a COUNT over the predicate. */
	final whereArguments:Array<Dynamic>;

	final orderSql:String;
	final limitSql:String;

	/** The arguments of `whereSql`, then those of `orderSql`. */
	final arguments:Array<Dynamic>;

	/** The children of a parent deferred into the future; empty with --include-deferred. */
	final deferredChildren:Array<String>;
}

/** Upstream sqlbuild.LabelSearchPlan: the label filters as joins, and the filter without them. */
private typedef LabelSearchPlan = {
	final fromSql:String;
	final clauses:Array<String>;
	final arguments:Array<Dynamic>;
	final distinct:Bool;
	final filter:IssueSearchFilter;
}

/**
	Reads ready work as upstream's embedded store does for `bd ready`, `bd ready
	--gated`, `--mol` and `--explain`, and `bd list --ready`
	(internal/storage/issueops/ready_work.go and ready_work_counts.go).

	What: the work filter of a ready request (workapi.BuildReadyFilter) or of a
	list filter (workapi.ReadyFilterFromIssueFilter); the ready predicate
	(sqlbuild.BuildReadyWorkWhere), with the children of a future-deferred parent
	and the descendants of `--parent` read first; GetReadyWorkWithCountsInTx,
	which reads a bounded page by ID and then the counts query for those IDs,
	over issues and then wisps, a wisp winning over an issue with the same ID, in
	the order of the sort policy; GetReadyWorkInTx, the bare read of the human
	`bd ready` view (readReadyIssues); CountReadyWorkInTx for the total of a
	full page; and the open and in-progress counts of GetStatistics. Upstream's
	read-only store does not wake expired defers, and neither does this port.
	How: each function runs in a read transaction that the caller owns.
**/
@:goNative
final class SqlReadyWorkReader {
	/** Upstream workapi.DefaultReadyLimit. */
	static inline final DEFAULT_READY_LIMIT = 100;

	/** Upstream sqlbuild.QueryBatchSize. */
	static inline final BATCH_SIZE = 200;

	/** Upstream readyWorkPageSize's minPageSize. */
	static inline final MIN_WISP_PAGE_SIZE = 100;

	/** The types that ready work never lists without --type (sqlbuild.ReadyWorkExcludeTypes), with the default infra types. */
	static final READY_EXCLUDED_TYPES = ["merge-request", "gate", "molecule", "rig", "agent", "role", "message"];

	static final SORTABLE_TIME = "2006-01-02T15:04:05.000000000";

	/** Go's `sql.ErrNoRows` text. */
	static final NO_ROWS = "sql: no rows in result set";

	/**
		Upstream BuildReadyFilter for a ready request, with the request's
		defensive row cap, as the native facade set it.
	**/
	public static function buildReadyFilter(request:ReadyRequest):StoreResult<ReadyWorkFilter> {
		final filter = new ReadyWorkFilter();
		filter.issueType = SqlIssueFilter.normalizeIssueType(request.issueType);
		filter.limit = switch request.limit {
			case IntPresent(value): value;
			case IntAbsent: DEFAULT_READY_LIMIT;
		};
		filter.unassigned = request.unassigned;
		filter.sortPolicy = switch request.sort {
			case Priority: "priority";
			case Hybrid: "hybrid";
			case Oldest: "oldest";
		};
		filter.labels = SqlIssueFilter.normalizedEntries(request.labels);
		filter.labelsAny = SqlIssueFilter.normalizedEntries(request.labelsAny);
		filter.excludeLabels = SqlIssueFilter.normalizedEntries(request.excludeLabels);
		filter.labelPattern = request.labelPattern;
		filter.labelRegex = request.labelRegex;
		filter.includeDeferred = request.includeDeferred;
		filter.includeEphemeral = request.includeEphemeral;
		for (raw in request.excludeTypes)
			for (part in raw.split(",")) {
				final excluded = goTrimSpace(part);
				if (excluded != "")
					filter.excludeTypes.push(SqlIssueFilter.normalizeIssueType(excluded));
			}
		filter.hasMetadataKey = request.hasMetadataKey;
		filter.lite = request.brief;
		filter.priority = request.priority;
		if (request.assignee != "" && !request.unassigned)
			filter.assignee = request.assignee;
		if (request.parentId != "")
			filter.parentId = request.parentId;
		if (request.moleculeType != "")
			filter.molType = request.moleculeType;
		filter.metadataFields = request.metadataFields;
		final metadataError = SqlIssueFilter.metadataFilterError(request.metadataFields, request.hasMetadataKey);
		if (metadataError != null)
			return Failure(metadataError);
		switch request.maxRows {
			case IntPresent(value):
				filter.maxRows = value;
				filter.maxRowsSource = request.maxRowsSource;
			case IntAbsent:
		}
		return Success(filter);
	}

	/** Upstream BuildReadyCountFilter for the same request: no limit and no row cap. */
	public static function countFilter(filter:ReadyWorkFilter):ReadyWorkFilter {
		final counted = new ReadyWorkFilter();
		counted.issueType = filter.issueType;
		counted.priority = filter.priority;
		counted.assignee = filter.assignee;
		counted.unassigned = filter.unassigned;
		counted.labels = filter.labels;
		counted.labelsAny = filter.labelsAny;
		counted.excludeLabels = filter.excludeLabels;
		counted.labelPattern = filter.labelPattern;
		counted.labelRegex = filter.labelRegex;
		counted.includeDeferred = filter.includeDeferred;
		counted.includeEphemeral = filter.includeEphemeral;
		counted.excludeTypes = filter.excludeTypes;
		counted.parentId = filter.parentId;
		counted.molType = filter.molType;
		counted.metadataFields = filter.metadataFields;
		counted.hasMetadataKey = filter.hasMetadataKey;
		counted.sortPolicy = filter.sortPolicy;
		counted.lite = filter.lite;
		return counted;
	}

	/**
		Upstream ReadyFilterFromIssueFilter: the part of a `list --ready` filter
		that the ready query carries. It admits wisps when the list filter does.
	**/
	public static function fromListFilter(filter:IssueSearchFilter):ReadyWorkFilter {
		final ready = new ReadyWorkFilter();
		ready.limit = filter.limit;
		ready.labels = filter.labels;
		ready.labelsAny = filter.labelsAny;
		ready.excludeLabels = filter.excludeLabels;
		ready.labelPattern = filter.labelPattern;
		ready.labelRegex = filter.labelRegex;
		ready.parentId = filter.parentId;
		ready.excludeTypes = filter.excludeTypes;
		ready.metadataFields = filter.metadataFields;
		ready.hasMetadataKey = filter.hasMetadataKey;
		ready.maxRows = filter.maxRows;
		ready.maxRowsSource = filter.maxRowsSource;
		ready.lite = filter.lite;
		if (filter.issueType != null)
			ready.issueType = filter.issueType;
		ready.molType = filter.molType;
		ready.priority = filter.priority;
		ready.assignee = filter.assignee;
		ready.unassigned = filter.noAssignee;
		ready.includeEphemeral = filter.ephemeral.match(FlagTrue) || !filter.skipWisps;
		return ready;
	}

	/** Upstream GetReadyWorkWithCountsInTx. */
	public static function readReadyWork(context:Context, transaction:Tx, filter:ReadyWorkFilter):IssueSearchRows {
		final wispDependencies = switch SqlIssueListReader.probeTable(context, transaction, "wisp_dependencies") {
			case TableHasRows | TableEmpty: true;
			case TableMissing: false;
			case TableProbeFailed(error): return failed('get ready work with counts: wisp dependency probe: ${error.text()}', error);
		};
		final issuePredicates = switch predicates(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		final issues = switch readyCounts(context, transaction, SqlIssueFilter.ISSUE_TABLES, filter, issuePredicates, wispDependencies) {
			case SearchRows(value): value;
			case stopped: return stopped;
		};
		switch SqlIssueListReader.probeTable(context, transaction, "wisps") {
			case TableHasRows:
			case TableEmpty | TableMissing:
				return finish(issues, filter);
			case TableProbeFailed(error):
				return failed('get ready work with counts: wisp probe: ${error.text()}', error);
		}
		if (!wispDependencies)
			return finish(issues, filter);
		final wispPredicates = switch predicates(context, transaction, filter, SqlIssueFilter.WISP_TABLES) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		final wisps = switch readyCounts(context, transaction, SqlIssueFilter.WISP_TABLES, filter, wispPredicates, true) {
			case SearchRows(value): value;
			case SearchStopped(SearchFailed(_, error)) if (isTableNotExist(error)): return finish(issues, filter);
			case stopped: return stopped;
		};
		if (wisps.length == 0)
			return finish(issues, filter);
		// Prefer the wisp record when an ID is in both tables.
		final wispIds = new Map<String, Bool>();
		for (wisp in wisps)
			wispIds.set(wisp.id, true);
		final kept = [for (issue in issues) if (!wispIds.exists(issue.id)) issue];
		for (wisp in wisps)
			kept.push(wisp);
		sortByPolicy(kept, filter.sortPolicy);
		return finish(kept, filter);
	}

	/**
		Upstream GetReadyWorkInTx, the bare read that the human `bd ready` view
		makes (cmd/bd/ready.go:220).

		What: the IDs of the ready issues under the ready predicate, sort policy
		and bound, then their records (GetIssuesByIDsInTx: labels, no counts, no
		parent and no dependencies). Wisps come from a search of their own
		(readyWisps), which applies only some of the filter, and are merged in by
		the sort policy and cut to the limit. The row cap counts what is left.
	**/
	public static function readReadyIssues(context:Context, transaction:Tx, filter:ReadyWorkFilter):IssueSearchRows {
		final issuePredicates = switch predicates(context, transaction, filter, SqlIssueFilter.ISSUE_TABLES) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		final ids = switch readIdPage(context, transaction,
			'SELECT id FROM issues ${issuePredicates.whereSql} ${issuePredicates.orderSql} ${issuePredicates.limitSql}', issuePredicates.arguments) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		final records = switch SqlIssueBatchReader.readIssuesByIds(context, transaction, ids) {
			case Failure(message): return failed('get ready work: fetch issues: $message', null);
			case Success(value): [for (record in value) record.id => record];
		};
		var ordered = new Array<IssueListItem>();
		for (id in ids) {
			final record = records.get(id);
			if (record != null)
				ordered.push(recordItem(record));
		}
		final wisps = switch readyWisps(context, transaction, filter, issuePredicates.deferredChildren) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		if (wisps.length > 0)
			ordered = mergeReadyWisps(ordered, wisps, filter);
		if (filter.maxRows > 0 && ordered.length > filter.maxRows)
			return SearchStopped(SearchRowCap(ordered.length, filter.maxRowsSource, filter.maxRows));
		return SearchRows(ordered);
	}

	/**
		Upstream mergeReadyWisps: the issues whose ID is not a wisp's, then the
		wisps, in the order of the sort policy, cut to the limit.
	**/
	static function mergeReadyWisps(issues:Array<IssueListItem>, wisps:Array<IssueListItem>, filter:ReadyWorkFilter):Array<IssueListItem> {
		final wispIds = [for (wisp in wisps) wisp.id => true];
		final kept = [for (issue in issues) if (!wispIds.exists(issue.id)) issue];
		for (wisp in wisps)
			kept.push(wisp);
		sortByPolicy(kept, filter.sortPolicy);
		return filter.limit > 0 && kept.length > filter.limit ? kept.slice(0, filter.limit) : kept;
	}

	/**
		Upstream getReadyWispsInTx: the ready wisps of GetReadyWork.

		Why: upstream searches the wisps table with the narrower issue filter of
		readyWorkWispIssueFilter, not with the ready predicate, so the wisps of
		the human view differ from those of `--json`.
		What: nothing when the wisps table is empty or missing. Without a limit,
		one search under the default list order, bounded only by the row cap.
		With one, pages of IDs (readyWorkPageSize) in the order of the sort
		policy, each page's records read in that order and filtered, until the
		limit is reached or the IDs run out. A missing table on a search reads as
		no wisps.
	**/
	static function readyWisps(context:Context, transaction:Tx, filter:ReadyWorkFilter, deferredChildren:Array<String>):StoreResult<Array<IssueListItem>> {
		switch SqlIssueListReader.probeTable(context, transaction, "wisps") {
			case TableHasRows:
			case TableEmpty | TableMissing:
				return Success([]);
			case TableProbeFailed(error):
				return Failure('search wisps (ready work): probe: ${error.text()}');
		}
		final wispFilter = wispIssueFilter(filter);
		if (filter.limit <= 0) {
			wispFilter.limit = 0;
			final wisps = switch searchWisps(context, transaction, wispFilter) {
				case WispsMissing: return Success([]);
				case WispsFailed(message): return Failure('search wisps (ready work): $message');
				case WispsFound(value): value;
			};
			return filterReadyWisps(context, transaction, filter, wisps, deferredChildren);
		}
		final pageSize = readyWorkPageSize(filter.limit);
		final order = readyOrder(filter.sortPolicy);
		final ready = new Array<IssueListItem>();
		var offset = 0;
		while (ready.length < filter.limit) {
			final pageIds = switch wispIdPage(context, transaction, wispFilter, !filter.includeDeferred, order, pageSize, offset) {
				case WispIdsMissing: return Success([]);
				case WispIdsFailed(message): return Failure('search wisps (ready work): $message');
				case WispIds(value): value;
			};
			if (pageIds.length == 0)
				break;
			final pageWisps = switch wispsInOrder(context, transaction, pageIds) {
				case Failure(message): return Failure('search wisps (ready work): $message');
				case Success(value): value;
			};
			final pageReady = switch filterReadyWisps(context, transaction, filter, pageWisps, deferredChildren) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			for (wisp in pageReady) {
				ready.push(wisp);
				if (ready.length >= filter.limit)
					break;
			}
			if (pageIds.length < pageSize)
				break;
			// In Go's int, like the limit that sizes the page.
			offset = GoInt.add(offset, pageSize);
		}
		return Success(ready);
	}

	/** Upstream readyWorkPageSize: at least 100 IDs a page. */
	static function readyWorkPageSize(limit:Int):Int {
		if (limit <= 0)
			return 0;
		return limit < MIN_WISP_PAGE_SIZE ? MIN_WISP_PAGE_SIZE : limit;
	}

	/**
		Upstream readyWorkWispIssueFilter: the issue filter of the wisp search.
		It carries the priority, the label sets, the limit, --mol-type, the
		metadata filters and the row cap; leaves pinned wisps out; reads open
		wisps; takes --type, or else the excluded types; the assignee rules; and
		leaves ephemeral wisps out unless the request includes them. It drops
		--label-pattern, --label-regex, --parent and the defer rules, which
		filterReadyWisps applies to some extent.
	**/
	static function wispIssueFilter(filter:ReadyWorkFilter):IssueSearchFilter {
		final wispFilter = new IssueSearchFilter();
		wispFilter.priority = filter.priority;
		wispFilter.labels = filter.labels;
		wispFilter.labelsAny = filter.labelsAny;
		wispFilter.excludeLabels = filter.excludeLabels;
		wispFilter.limit = filter.limit;
		wispFilter.molType = filter.molType;
		wispFilter.pinned = FlagFalse;
		wispFilter.metadataFields = filter.metadataFields;
		wispFilter.hasMetadataKey = filter.hasMetadataKey;
		wispFilter.maxRows = filter.maxRows;
		wispFilter.maxRowsSource = filter.maxRowsSource;
		// The ready filter's status is always open (BuildReadyFilter).
		wispFilter.status = "open";
		if (filter.issueType != "")
			wispFilter.issueType = filter.issueType;
		else
			wispFilter.excludeTypes = excludedTypes(filter.excludeTypes);
		if (filter.unassigned)
			wispFilter.noAssignee = true;
		else if (filter.assignee != null)
			wispFilter.assignee = filter.assignee;
		if (!filter.includeEphemeral)
			wispFilter.ephemeral = FlagFalse;
		return wispFilter;
	}

	/**
		Upstream sqlbuild.BuildLabelDrivenSearch: each --label as a join of its
		own and the --label-any set as one join, with their clauses first; the
		filter that is left builds the other clauses.
	**/
	static function labelDrivenSearch(filter:IssueSearchFilter, tables:IssueFilterTables):LabelSearchPlan {
		final labels = [for (label in filter.labels) if (label != "") label];
		final labelsAny = [for (label in filter.labelsAny) if (label != "") label];
		if (labels.length == 0 && labelsAny.length == 0)
			return {
				fromSql: tables.main,
				clauses: [],
				arguments: [],
				distinct: false,
				filter: filter
			};
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
		final rest = copyFilter(filter);
		rest.labels = [];
		rest.labelsAny = [];
		return {
			fromSql: tables.main + " " + joins.join(" "),
			clauses: clauses,
			arguments: arguments,
			distinct: true,
			filter: rest
		};
	}

	/** The fields of a wisp filter that wispIssueFilter sets, in a new filter. */
	static function copyFilter(filter:IssueSearchFilter):IssueSearchFilter {
		final copy = new IssueSearchFilter();
		copy.priority = filter.priority;
		copy.labels = filter.labels;
		copy.labelsAny = filter.labelsAny;
		copy.excludeLabels = filter.excludeLabels;
		copy.limit = filter.limit;
		copy.molType = filter.molType;
		copy.pinned = filter.pinned;
		copy.metadataFields = filter.metadataFields;
		copy.hasMetadataKey = filter.hasMetadataKey;
		copy.maxRows = filter.maxRows;
		copy.maxRowsSource = filter.maxRowsSource;
		copy.status = filter.status;
		copy.issueType = filter.issueType;
		copy.excludeTypes = filter.excludeTypes;
		copy.noAssignee = filter.noAssignee;
		copy.assignee = filter.assignee;
		copy.ephemeral = filter.ephemeral;
		return copy;
	}

	/** The WHERE of a wisp search: the label joins' clauses, then the filter's (BuildIssueFilterClauses, then MergeInto). */
	static function wispWhere(plan:LabelSearchPlan, extra:Array<String>):{sql:String, arguments:Array<Dynamic>} {
		final built = SqlIssueFilter.buildFilterClauses(plan.filter, SqlIssueFilter.WISP_TABLES);
		final clauses = plan.clauses.concat(built.clauses).concat(extra);
		return {sql: clauses.length == 0 ? "" : "WHERE " + clauses.join(" AND "), arguments: plan.arguments.concat(built.arguments)};
	}

	/**
		Upstream queryReadyWispIssueIDPage: one page of wisp IDs in the order of
		the sort policy, without the deferred wisps unless the request includes
		them.
	**/
	static function wispIdPage(context:Context, transaction:Tx, filter:IssueSearchFilter, excludeDeferred:Bool, order:{sql:String, arguments:Array<Dynamic>},
			limit:Int, offset:Int):WispIdRead {
		final plan = labelDrivenSearch(filter, SqlIssueFilter.WISP_TABLES);
		final where = wispWhere(plan, excludeDeferred ? ["(defer_until IS NULL OR defer_until <= UTC_TIMESTAMP())"] : []);
		final select = plan.distinct ? "SELECT DISTINCT " : "SELECT ";
		final queried = transaction.queryNativeContext(context, '${select}id FROM ${plan.fromSql} ${where.sql} ${order.sql} LIMIT $limit OFFSET $offset',
			...where.arguments.concat(order.arguments));
		if (queried.error != null)
			return isTableNotExist(queried.error) ? WispIdsMissing : WispIdsFailed('search wisps: ${queried.error.text()}');
		final rows = queried.rows;
		final ids = new Array<String>();
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final scanError = rows.scanNative(id);
			if (scanError != null) {
				rows.closeNative();
				return isTableNotExist(scanError) ? WispIdsMissing : WispIdsFailed('search wisps: scan id: ${scanError.text()}');
			}
			ids.push(id.get());
		}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return isTableNotExist(rowError) ? WispIdsMissing : WispIdsFailed('search wisps: rows: ${rowError.text()}');
		return WispIds(ids);
	}

	/** Upstream getWispIssuesByIDsInOrderInTx: the wisps' records, read from the wisps table, in the order of `ids`. */
	static function wispsInOrder(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Array<IssueListItem>> {
		final records = switch SqlIssueBatchReader.readIssuesFromWisps(context, transaction, ids) {
			case Failure(message): return Failure(message);
			case Success(value): [for (record in value) record.id => record];
		};
		final ordered = new Array<IssueListItem>();
		for (id in ids) {
			final record = records.get(id);
			if (record != null)
				ordered.push(recordItem(record));
		}
		return Success(ordered);
	}

	/**
		Upstream searchTableInTxT over the wisps table with issueProjection and no
		limit: the records in the default list order, bounded only by the row
		cap, with their labels (hydrateIssueLabelsAndDeps without dependencies).
	**/
	static function searchWisps(context:Context, transaction:Tx, filter:IssueSearchFilter):WispSearch {
		final plan = labelDrivenSearch(filter, SqlIssueFilter.WISP_TABLES);
		final where = wispWhere(plan, []);
		final bound = SqlIssueListReader.effectiveSearchLimit(filter.limit, filter.maxRows);
		final select = plan.distinct ? "SELECT DISTINCT " : "SELECT ";
		final queried = transaction.queryNativeContext(context,
			'$select$SQL_ISSUE_COLUMNS FROM ${plan.fromSql} LEFT JOIN leases ON leases.issue_id = wisps.id ${where.sql} ORDER BY priority ASC, created_at DESC, id ASC${bound > 0 ? ' LIMIT $bound' : ""}',
			...where.arguments);
		if (queried.error != null)
			return isTableNotExist(queried.error) ? WispsMissing : WispsFailed('search wisps: ${queried.error.text()}');
		final rows = queried.rows;
		final found = new Array<SqlIssueFields>();
		final seen = new Map<String, Bool>();
		while (rows.next()) {
			final fields = switch scanSqlIssueFieldsNative(rows, "") {
				case SqlIssueScanned(value): value;
				case SqlIssueScanFailure(error):
					rows.closeNative();
					return isTableNotExist(error) ? WispsMissing : WispsFailed('search wisps: scan: ${error.text()}');
				case SqlIssueDecodeFailure(message):
					rows.closeNative();
					return WispsFailed('search wisps: scan: $message');
			};
			// GH#3567: a join can repeat a row.
			if (seen.exists(fields.id))
				continue;
			seen.set(fields.id, true);
			found.push(fields);
		}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return isTableNotExist(rowError) ? WispsMissing : WispsFailed('search wisps: rows: ${rowError.text()}');
		final labels = new Map<String, Array<String>>();
		final ids = [for (fields in found) fields.id];
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final labelQuery = transaction.queryNativeContext(context,
				'SELECT issue_id, label FROM wisp_labels WHERE issue_id IN (${[for (_ in batch) "?"].join(",")}) ORDER BY issue_id, label', ...arguments);
			if (labelQuery.error != null)
				return
					isTableNotExist(labelQuery.error) ? WispsMissing : WispsFailed('search wisps: hydrate labels: get labels for issues from wisp_labels: ${labelQuery.error.text()}');
			final labelRows = labelQuery.rows;
			while (labelRows.next()) {
				final issueId = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = labelRows.scanNative(issueId, label);
				if (scanError != null) {
					labelRows.closeNative();
					return
						isTableNotExist(scanError) ? WispsMissing : WispsFailed('search wisps: hydrate labels: get labels for issues: scan: ${scanError.text()}');
				}
				final values = labels.get(issueId.get());
				if (values == null)
					labels.set(issueId.get(), [label.get()]);
				else
					values.push(label.get());
			}
			labelRows.closeNative();
			final labelError = labelRows.errNative();
			if (labelError != null)
				return
					isTableNotExist(labelError) ? WispsMissing : WispsFailed('search wisps: hydrate labels: get labels for issues: rows: ${labelError.text()}');
		}
		return WispsFound([
			for (fields in found) {
				final issueLabels = labels.get(fields.id);
				recordItem(relatedIssueFromSql(fields, issueLabels == null ? [] : issueLabels, ""));
			}
		]);
	}

	/**
		Upstream filterReadyWispsInTx: drops the wisps outside --parent, the
		wisps deferred into the future (checked in Go against the clock) and the
		children of a deferred parent unless the request includes deferred work,
		the wisps marked blocked, and the pinned ones.
	**/
	static function filterReadyWisps(context:Context, transaction:Tx, filter:ReadyWorkFilter, wisps:Array<IssueListItem>,
			deferredChildren:Array<String>):StoreResult<Array<IssueListItem>> {
		if (wisps.length == 0)
			return Success(wisps);
		final wispIds = [for (wisp in wisps) wisp.id];
		final excluded = new Map<String, Bool>();
		final parentId = filter.parentId;
		if (parentId != null) {
			final descendants = switch descendantIds(context, transaction, parentId) {
				case Failure(message): return Failure('get wisp parent descendants: $message');
				case Success(value): [for (id in value) id => true];
			};
			final parented = switch parentedIds(context, transaction, wispIds) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			for (wisp in wisps) {
				if (descendants.exists(wisp.id))
					continue;
				if (StringTools.startsWith(wisp.id, parentId + ".") && !parented.exists(wisp.id))
					continue;
				excluded.set(wisp.id, true);
			}
		}
		if (!filter.includeDeferred) {
			final now = TimePkg.now().utc().format(SORTABLE_TIME);
			for (wisp in wisps)
				if (wisp.deferUntil != "" && SqlIssueListReader.sortableTime(wisp.deferUntil) > now)
					excluded.set(wisp.id, true);
			for (id in deferredChildren)
				excluded.set(id, true);
		}
		var start = 0;
		while (start < wispIds.length) {
			final batch = wispIds.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final queried = transaction.queryNativeContext(context,
				'SELECT id FROM wisps WHERE id IN (${[for (_ in batch) "?"].join(",")}) AND is_blocked = 1', ...arguments);
			if (queried.error != null)
				return Failure('get ready work: filter blocked wisps: ${queried.error.text()}');
			final rows = queried.rows;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final scanError = rows.scanNative(id);
				if (scanError != null) {
					rows.closeNative();
					return Failure('scan blocked wisp: ${scanError.text()}');
				}
				excluded.set(id.get(), true);
			}
			rows.closeNative();
			final rowError = rows.errNative();
			if (rowError != null)
				return Failure('blocked wisp rows: ${rowError.text()}');
		}
		return Success([
			for (wisp in wisps)
				if (!wisp.longFields.pinned && !excluded.exists(wisp.id)) wisp
		]);
	}

	/** Upstream getParentedIDSetInTx: the IDs with a parent-child row in either dependency table. */
	static function parentedIds(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, Bool>> {
		final parented = new Map<String, Bool>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			var start = 0;
			var missing = false;
			while (start < ids.length && !missing) {
				final batch = ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				final arguments:Array<Dynamic> = [for (id in batch) id];
				final queried = transaction.queryNativeContext(context,
					'SELECT issue_id FROM $table WHERE type = \'parent-child\' AND issue_id IN (${[for (_ in batch) "?"].join(",")})', ...arguments);
				if (queried.error != null) {
					if (table == "wisp_dependencies" && isTableNotExist(queried.error)) {
						missing = true;
						continue;
					}
					return Failure('get parented IDs from $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final id = go.NativePointer.of("");
					final scanError = rows.scanNative(id);
					if (scanError != null) {
						rows.closeNative();
						return Failure('get parented IDs: scan: ${scanError.text()}');
					}
					parented.set(id.get(), true);
				}
				rows.closeNative();
				final rowError = rows.errNative();
				if (rowError != null)
					return Failure('get parented IDs: rows from $table: ${rowError.text()}');
			}
		}
		return Success(parented);
	}

	/** A GetIssuesByIDsInTx record as a list item: no counts, no parent, no dependencies. */
	static function recordItem(record:RelatedIssue):IssueListItem {
		return {
			id: record.id,
			title: record.title,
			description: record.description,
			design: record.design,
			acceptanceCriteria: record.acceptanceCriteria,
			notes: record.notes,
			specId: record.specId,
			status: record.status,
			priority: record.priority,
			issueType: record.issueType,
			assignee: record.assignee,
			owner: record.owner,
			estimatedMinutes: record.estimatedMinutes,
			createdAt: record.createdAt,
			createdBy: record.createdBy,
			updatedAt: record.updatedAt,
			startedAt: record.startedAt,
			closedAt: record.closedAt,
			closeReason: record.closeReason,
			closedBySession: record.closedBySession,
			dueAt: record.dueAt,
			deferUntil: record.deferUntil,
			externalRef: record.externalRef,
			sourceSystem: record.sourceSystem,
			metadata: record.metadata,
			wispType: record.wispType,
			moleculeType: record.moleculeType,
			longFields: record.longFields,
			labels: record.labels,
			dependencies: [],
			dependencyCount: 0,
			dependentCount: 0,
			commentCount: 0,
			parent: "",
			blockedBy: [],
			blocks: [],
			blockingParent: ""
		};
	}

	/**
		The parent of each issue, from upstream GetDependencyRecordsForIssuesInTx
		as buildParentEpicMap (cmd/bd/ready.go) reads it: each issue's rows of
		the dependency table that its wisp status selects, in the order
		`issue_id, depends_on_id, type, id`, the last `parent-child` row winning.
		buildParentEpicMap ignores a failed read, so the messages are the scan's.
	**/
	public static function readParentIds(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, String>> {
		final parents = new Map<String, String>();
		if (ids.length == 0)
			return Success(parents);
		final wisps = switch SqlIssueBatchReader.readWispIdSet(context, transaction, ids) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		for (plane in [
			{table: "wisp_dependencies", ids: [for (id in ids) if (wisps.exists(id)) id]},
			{table: "dependencies", ids: [for (id in ids) if (!wisps.exists(id)) id]}
		]) {
			var start = 0;
			while (start < plane.ids.length) {
				final batch = plane.ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				switch SqlGraphReader.readDependencyBatch(context, transaction, plane.table, batch) {
					case Failure(message):
						return Failure(message);
					case Success(records):
						for (record in records)
							if (record.type == "parent-child")
								parents.set(record.issueId, record.dependsOnId);
				}
			}
		}
		return Success(parents);
	}

	/** Upstream CountReadyWorkInTx: the size of the ready set, without the counts query. */
	public static function countReadyWork(context:Context, transaction:Tx, filter:ReadyWorkFilter):StoreResult<Int> {
		final counted = countFilter(filter);
		final wispDependencies = switch SqlIssueListReader.probeTable(context, transaction, "wisp_dependencies") {
			case TableHasRows | TableEmpty: true;
			case TableMissing: false;
			case TableProbeFailed(error): return Failure('count ready work: wisp dependency probe: ${error.text()}');
		};
		final issuePredicates = switch predicates(context, transaction, counted, SqlIssueFilter.ISSUE_TABLES) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final issueCount = switch countRows(context, transaction, 'SELECT COUNT(*) FROM issues ${issuePredicates.whereSql}', issuePredicates.whereArguments) {
			case CountFailed(error): return Failure('count ready work: issues: ${error.text()}');
			case CountMissing: return Failure('count ready work: issues: $NO_ROWS');
			case Counted(value): value;
		};
		final wispsEmpty = switch SqlIssueListReader.probeTable(context, transaction, "wisps") {
			case TableHasRows: false;
			case TableEmpty | TableMissing: true;
			case TableProbeFailed(error): return Failure('count ready work: wisp probe: ${error.text()}');
		};
		if (wispsEmpty || !wispDependencies)
			return Success(issueCount);
		final wispPredicates = switch predicates(context, transaction, counted, SqlIssueFilter.WISP_TABLES) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final wispCount = switch countRows(context, transaction, 'SELECT COUNT(*) FROM wisps ${wispPredicates.whereSql}', wispPredicates.whereArguments) {
			case CountFailed(error) if (isTableNotExist(error)): return Success(issueCount);
			case CountFailed(error): return Failure('count ready work: wisps: ${error.text()}');
			case CountMissing: return Failure('count ready work: wisps: $NO_ROWS');
			case Counted(value): value;
		};
		if (wispCount == 0)
			return Success(issueCount);
		final overlap = switch countRows(context, transaction,
			'SELECT COUNT(*) FROM issues ${issuePredicates.whereSql} AND id IN (SELECT id FROM wisps ${wispPredicates.whereSql})',
			issuePredicates.whereArguments.concat(wispPredicates.whereArguments)) {
			case CountFailed(error): return Failure('count ready work: overlap: ${error.text()}');
			case CountMissing: return Failure('count ready work: overlap: $NO_ROWS');
			case Counted(value): value;
		};
		return Success(issueCount + wispCount - overlap);
	}

	/**
		Whether any issue is open or in progress, from upstream GetStatistics on an
		embedded store (the counts query, then the blocked count), which `bd ready`
		reads when it finds no ready work.
	**/
	public static function readHasOpenIssues(context:Context, transaction:Tx):StoreResult<Bool> {
		final queried = transaction.queryNativeContext(context,
			"SELECT COUNT(*) AS total, COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),"
			+ " COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),"
			+ " COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0),"
			+ " COALESCE(SUM(CASE WHEN status = 'deferred' THEN 1 ELSE 0 END), 0),"
			+ " COALESCE(SUM(CASE WHEN pinned = 1 THEN 1 ELSE 0 END), 0) FROM issues");
		if (queried.error != null)
			return Failure('scan issue counts: ${queried.error.text()}');
		final rows = queried.rows;
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			return Failure(rowError != null ? 'scan issue counts: ${rowError.text()}' : 'scan issue counts: $NO_ROWS');
		}
		final total = go.NativePointer.of(0);
		final open = go.NativePointer.of(0);
		final inProgress = go.NativePointer.of(0);
		final closed = go.NativePointer.of(0);
		final deferred = go.NativePointer.of(0);
		final pinned = go.NativePointer.of(0);
		final scanError = rows.scanNative(total, open, inProgress, closed, deferred, pinned);
		rows.closeNative();
		if (scanError != null)
			return Failure('scan issue counts: ${scanError.text()}');
		return switch countRows(context, transaction, "SELECT COUNT(*) FROM issues WHERE is_blocked = 1 AND status <> 'closed' AND status <> 'pinned'", []) {
			case CountFailed(error): Failure(error.text());
			case CountMissing: Failure(NO_ROWS);
			case Counted(_): Success(open.get() > 0 || inProgress.get() > 0);
		};
	}

	/** Upstream buildReadyWorkPredicates for one table family. */
	static function predicates(context:Context, transaction:Tx, filter:ReadyWorkFilter, tables:IssueFilterTables):StoreResult<ReadyPredicates> {
		var deferredChildren = new Array<String>();
		if (!filter.includeDeferred)
			switch deferredParentChildren(context, transaction) {
				case Failure(message):
					return Failure('get ready work: compute deferred parent children: $message');
				case Success(value):
					deferredChildren = value;
			}
		var descendants = new Array<String>();
		final parentId = filter.parentId;
		if (parentId != null)
			switch descendantIds(context, transaction, parentId) {
				case Failure(message):
					return Failure('get parent descendants: $message');
				case Success(value):
					descendants = value;
			}
		final where = readyWhere(filter, tables, deferredChildren, descendants);
		final order = readyOrder(filter.sortPolicy);
		final bound = SqlIssueListReader.effectiveSearchLimit(filter.limit, filter.maxRows);
		return Success({
			whereSql: where.sql,
			whereArguments: where.arguments,
			orderSql: order.sql,
			limitSql: bound > 0 ? 'LIMIT $bound' : "",
			arguments: where.arguments.concat(order.arguments),
			deferredChildren: deferredChildren
		});
	}

	/** Upstream sqlbuild.BuildReadyWorkWhere; every clause names main-table columns only. */
	static function readyWhere(filter:ReadyWorkFilter, tables:IssueFilterTables, deferredChildren:Array<String>,
			descendants:Array<String>):{sql:String, arguments:Array<Dynamic>} {
		final clauses = ["status = ?", "(pinned = 0 OR pinned IS NULL)", "is_blocked = 0"];
		final arguments:Array<Dynamic> = ["open"];
		if (!filter.includeEphemeral)
			clauses.push("(ephemeral = 0 OR ephemeral IS NULL)");
		switch filter.priority {
			case IntPresent(value):
				clauses.push("priority = ?");
				arguments.push(value);
			case IntAbsent:
		}
		if (filter.issueType != "") {
			clauses.push("issue_type = ?");
			arguments.push(filter.issueType);
		} else {
			final excluded = excludedTypes(filter.excludeTypes);
			clauses.push('issue_type NOT IN (${batchPlaceholders(excluded, arguments)})');
		}
		if (filter.unassigned)
			clauses.push("(assignee IS NULL OR assignee = '')");
		else if (filter.assignee != null) {
			clauses.push("assignee = ?");
			arguments.push(filter.assignee);
		}
		if (!filter.includeDeferred) {
			clauses.push("(defer_until IS NULL OR defer_until <= UTC_TIMESTAMP())");
			var start = 0;
			while (start < deferredChildren.length) {
				final batch = deferredChildren.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				clauses.push('id NOT IN (${batchPlaceholders(batch, arguments)})');
			}
		}
		for (label in filter.labels) {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label = ?)');
			arguments.push(label);
		}
		if (filter.labelsAny.length > 0) {
			for (label in filter.labelsAny)
				arguments.push(label);
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label IN (${[for (_ in filter.labelsAny) "?"].join(", ")}))');
		}
		if (filter.excludeLabels.length > 0) {
			for (label in filter.excludeLabels)
				arguments.push(label);
			clauses.push('id NOT IN (SELECT issue_id FROM ${tables.labels} WHERE label IN (${[for (_ in filter.excludeLabels) "?"].join(", ")}))');
		}
		if (filter.labelPattern != "") {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label LIKE ? ESCAPE \'|\')');
			arguments.push(SqlIssueFilter.globToLikePattern(filter.labelPattern));
		}
		if (filter.labelRegex != "") {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label REGEXP ?)');
			arguments.push(filter.labelRegex);
		}
		final parentId = filter.parentId;
		if (parentId != null) {
			final parentClauses = [
				'(id LIKE CONCAT(?, \'.%\') AND id NOT IN (SELECT issue_id FROM ${tables.dependencies} WHERE type = \'parent-child\'))'
			];
			arguments.push(parentId);
			var start = 0;
			while (start < descendants.length) {
				final batch = descendants.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				parentClauses.push('id IN (${batchPlaceholders(batch, arguments)})');
			}
			clauses.push("(" + parentClauses.join(" OR ") + ")");
		}
		if (filter.hasMetadataKey != "") {
			clauses.push("JSON_EXTRACT(metadata, ?) IS NOT NULL");
			arguments.push(SqlIssueFilter.metadataPath(filter.hasMetadataKey));
		}
		for (field in SqlIssueFilter.sortedMetadataFields(filter.metadataFields)) {
			clauses.push("JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?");
			arguments.push(SqlIssueFilter.metadataPath(field.key));
			arguments.push(field.value);
		}
		return {sql: "WHERE " + clauses.join(" AND "), arguments: arguments};
	}

	/** Upstream ReadyWorkExcludeTypes: the default types, then each extra type once. */
	static function excludedTypes(extra:Array<String>):Array<String> {
		final excluded = READY_EXCLUDED_TYPES.copy();
		final seen = [for (issueType in excluded) issueType => true];
		for (issueType in extra) {
			if (issueType == "" || seen.exists(issueType))
				continue;
			seen.set(issueType, true);
			excluded.push(issueType);
		}
		return excluded;
	}

	/** Upstream sqlbuild.BuildReadyWorkOrder on `created_at` and `priority`; the hybrid order binds its recency cutoff twice. */
	static function readyOrder(policy:String):{sql:String, arguments:Array<Dynamic>} {
		return switch policy {
			case "oldest":
				{sql: "ORDER BY created_at ASC, id ASC", arguments: []};
			case "hybrid" | "":
				final cutoff = recentCutoff();
				final arguments:Array<Dynamic> = [cutoff, cutoff];
				{
					sql: "ORDER BY CASE WHEN created_at >= ? THEN 0 ELSE 1 END ASC, CASE WHEN created_at >= ? THEN priority ELSE 999 END ASC, created_at ASC, id ASC",
					arguments: arguments
				};
			case _:
				{sql: "ORDER BY priority ASC, created_at ASC, id ASC", arguments: []};
		};
	}

	/** Upstream runReadyCountsInTx: a bounded page reads its IDs first, then the counts query for those IDs, in the ID order. */
	static function readyCounts(context:Context, transaction:Tx, tables:IssueFilterTables, filter:ReadyWorkFilter, predicates:ReadyPredicates,
			wispReverseDependencies:Bool):IssueSearchRows {
		if (filter.limit <= 0) {
			final query = SqlIssueListReader.countsQuery(tables, [], predicates.whereSql, predicates.orderSql, predicates.limitSql, wispReverseDependencies,
				false, false);
			return SqlIssueListReader.scanCountsRows(context, transaction, tables.main, query, predicates.arguments, filter.lite);
		}
		final pageIds = switch readIdPage(context, transaction,
			'SELECT id FROM ${tables.main} ${predicates.whereSql} ${predicates.orderSql} ${predicates.limitSql}', predicates.arguments) {
			case Failure(message): return failed(message, null);
			case Success(value): value;
		};
		final byId = new Map<String, IssueListItem>();
		var start = 0;
		while (start < pageIds.length) {
			final batch = pageIds.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final query = SqlIssueListReader.countsQuery(tables, batch, "", "", "", wispReverseDependencies, false, false);
			final arguments = SqlIssueListReader.countsArguments(batch, wispReverseDependencies, false, false);
			switch SqlIssueListReader.scanCountsRows(context, transaction, tables.main, query, arguments, filter.lite) {
				case SearchRows(items):
					for (item in items)
						byId.set(item.id, item);
				case stopped:
					return stopped;
			}
		}
		final ordered = new Array<IssueListItem>();
		for (id in pageIds) {
			final item = byId.get(id);
			if (item != null)
				ordered.push(item);
		}
		return SearchRows(ordered);
	}

	/** Upstream queryReadyIssueIDPage. */
	static function readIdPage(context:Context, transaction:Tx, query:String, arguments:Array<Dynamic>):StoreResult<Array<String>> {
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return Failure('failed to get ready work: ${queried.error.text()}');
		final rows = queried.rows;
		final ids = new Array<String>();
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final scanError = rows.scanNative(id);
			if (scanError != null) {
				rows.closeNative();
				return Failure('get ready work: scan id: ${scanError.text()}');
			}
			ids.push(id.get());
		}
		rows.closeNative();
		final rowError = rows.errNative();
		if (rowError != null)
			return Failure('get ready work: rows: ${rowError.text()}');
		return Success(ids);
	}

	/** Upstream getChildrenOfDeferredParentsInTx: the children of a parent deferred into the future. */
	static function deferredParentChildren(context:Context, transaction:Tx):StoreResult<Array<String>> {
		var deferredParent = false;
		for (table in ["issues", "wisps"]) {
			final queried = transaction.queryNativeContext(context,
				'SELECT 1 FROM $table WHERE defer_until IS NOT NULL AND defer_until > UTC_TIMESTAMP() LIMIT 1');
			if (queried.error != null) {
				if (table == "wisps" && isTableNotExist(queried.error))
					continue;
				return Failure('deferred parents: check future-deferred parents from $table: ${queried.error.text()}');
			}
			final present = queried.rows.next();
			final rowError = queried.rows.errNative();
			queried.rows.closeNative();
			if (rowError != null) {
				if (table == "wisps" && isTableNotExist(rowError))
					continue;
				return Failure('deferred parents: check future-deferred parents from $table: ${rowError.text()}');
			}
			if (present) {
				deferredParent = true;
				break;
			}
		}
		if (!deferredParent)
			return Success([]);
		final children = new Array<String>();
		for (dependencyTable in ["dependencies", "wisp_dependencies"]) {
			for (issueTable in ["issues", "wisps"]) {
				final target = issueTable == "wisps" ? "depends_on_wisp_id" : "depends_on_issue_id";
				final queried = transaction.queryNativeContext(context,
					'SELECT dep.issue_id FROM $dependencyTable dep JOIN $issueTable parent ON parent.id = dep.$target' +
					" WHERE dep.type = 'parent-child' AND parent.defer_until IS NOT NULL AND parent.defer_until > UTC_TIMESTAMP()");
				if (queried.error != null) {
					if (dependencyTable == "wisp_dependencies" && isTableNotExist(queried.error))
						break;
					if (issueTable == "wisps" && isTableNotExist(queried.error))
						continue;
					return Failure('deferred parents: get deferred children from $dependencyTable/$issueTable: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final id = go.NativePointer.of("");
					final scanError = rows.scanNative(id);
					if (scanError != null) {
						rows.closeNative();
						return Failure('deferred parents: scan deferred child from $dependencyTable/$issueTable: ${scanError.text()}');
					}
					children.push(id.get());
				}
				rows.closeNative();
				final rowError = rows.errNative();
				if (rowError != null)
					return Failure('deferred parents: child rows from $dependencyTable/$issueTable: ${rowError.text()}');
			}
		}
		return Success(children);
	}

	/** Upstream GetDescendantIDsInTx without a depth limit: every issue below `rootId`, over both dependency tables when they exist. */
	static function descendantIds(context:Context, transaction:Tx, rootId:String):StoreResult<Array<String>> {
		if (rootId == "")
			return Success([]);
		return switch queryDescendants(context, transaction, rootId, true) {
			case DescendantsFailed(error) if (isTableNotExist(error)):
				switch queryDescendants(context, transaction, rootId, false) {
					case DescendantsFailed(retryError): Failure(retryError.text());
					case DescendantsFailedWith(message): Failure(message);
					case Descendants(ids): Success(ids);
				}
			case DescendantsFailed(error): Failure(error.text());
			case DescendantsFailedWith(message): Failure(message);
			case Descendants(ids): Success(ids);
		};
	}

	static function queryDescendants(context:Context, transaction:Tx, rootId:String, includeWisps:Bool):DescendantRead {
		final target = SqlIssueFilter.DEPENDENCY_TARGET;
		var edges = 'SELECT issue_id, $target FROM dependencies WHERE type = \'parent-child\'';
		if (includeWisps)
			edges += ' UNION ALL SELECT issue_id, $target FROM wisp_dependencies WHERE type = \'parent-child\'';
		final query = 'WITH RECURSIVE parent_edges(issue_id, depends_on_id) AS ($edges),'
			+ " descendants(id, depth, path) AS ("
			+ " SELECT issue_id, 1, CONCAT(',', ?, ',', issue_id, ',') FROM parent_edges WHERE depends_on_id = ?"
			+ " UNION ALL"
			+ " SELECT e.issue_id, d.depth + 1, CONCAT(d.path, e.issue_id, ',') FROM parent_edges e JOIN descendants d ON e.depends_on_id = d.id"
			+ " WHERE (? <= 0 OR d.depth < ?) AND LOCATE(CONCAT(',', e.issue_id, ','), d.path) = 0"
			+ ") SELECT id, depth FROM descendants WHERE id <> ?";
		final queried = transaction.queryNativeContext(context, query, rootId, rootId, 0, 0, rootId);
		if (queried.error != null)
			return DescendantsFailed(queried.error);
		final rows = queried.rows;
		final ids = new Array<String>();
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final depth = go.NativePointer.of(0);
			final scanError = rows.scanNative(id, depth);
			if (scanError != null) {
				rows.closeNative();
				return DescendantsFailedWith('scan descendant: ${scanError.text()}');
			}
			ids.push(id.get());
		}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return DescendantsFailedWith('descendant rows: ${rowError.text()}');
		return Descendants(ids);
	}

	/** One COUNT(*) row, as `(*sql.Row).Scan` reads it. */
	static function countRows(context:Context, transaction:Tx, query:String, arguments:Array<Dynamic>):CountRead {
		final queried = transaction.queryNativeContext(context, query, ...arguments);
		if (queried.error != null)
			return CountFailed(queried.error);
		final rows = queried.rows;
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			return rowError != null ? CountFailed(rowError) : CountMissing;
		}
		final count = go.NativePointer.of(0);
		final scanError = rows.scanNative(count);
		final closeError = rows.closeNative();
		if (scanError != null)
			return CountFailed(scanError);
		if (closeError != null)
			return CountFailed(closeError);
		return Counted(count.get());
	}

	/** Upstream finishReadyWorkWithCounts: the limit cut, then the row cap on what is left. */
	static function finish(items:Array<IssueListItem>, filter:ReadyWorkFilter):IssueSearchRows {
		final kept = filter.limit > 0 && items.length > filter.limit ? items.slice(0, filter.limit) : items;
		if (filter.maxRows > 0 && kept.length > filter.maxRows)
			return SearchStopped(SearchRowCap(kept.length, filter.maxRowsSource, filter.maxRows));
		return SearchRows(kept);
	}

	/**
		Upstream sortReadyIssues, as sortIssuesWithCountsByPolicy applies it to a
		merged page: `oldest` by creation time, `priority` by priority, then
		creation time; `hybrid` puts the issues of the last 48 hours first, by
		priority, and the older ones by creation time. The ID breaks every tie.
	**/
	static function sortByPolicy(items:Array<IssueListItem>, policy:String):Void {
		if (items.length <= 1)
			return;
		final cutoff = recentCutoff().format(SORTABLE_TIME);
		items.sort((left, right) -> comparePolicy(left, right, policy, cutoff));
	}

	static function comparePolicy(left:IssueListItem, right:IssueListItem, policy:String, cutoff:String):Int {
		final created = SqlIssueListReader.compareTimes(left.createdAt, right.createdAt);
		final byCreation = created != 0 ? created : compareUtf8(left.id, right.id);
		final priority = left.priority.compare(right.priority);
		switch policy {
			case "oldest":
				return byCreation;
			case "hybrid" | "":
				final leftRecent = SqlIssueListReader.sortableTime(left.createdAt) >= cutoff;
				final rightRecent = SqlIssueListReader.sortableTime(right.createdAt) >= cutoff;
				if (leftRecent != rightRecent)
					return leftRecent ? -1 : 1;
				if (leftRecent && priority != 0)
					return priority;
				return byCreation;
			case _:
				return priority != 0 ? priority : byCreation;
		}
	}

	/** Upstream's recency cutoff: 48 hours before now, in UTC. */
	static function recentCutoff():beadshx.nativeextern.time.Time {
		return TimePkg.now().utc().add(TimePkg.parseDuration("-48h").value1);
	}

	/** `?` for each value, joined with `,` as sqlbuild.InPlaceholders joins them, after the values join the arguments. */
	static function batchPlaceholders(values:Array<String>, arguments:Array<Dynamic>):String {
		for (value in values)
			arguments.push(value);
		return [for (_ in values) "?"].join(",");
	}

	static function failed(message:String, error:Null<go.NativeError>):IssueSearchRows {
		return SearchStopped(SearchFailed(message, error));
	}
}

/** One COUNT(*) read. */
private enum CountRead {
	Counted(value:Int);
	CountFailed(error:go.NativeError);

	/** No row, `sql.ErrNoRows`, which a COUNT(*) never gives. */
	CountMissing;
}

/** One page of wisp IDs, no wisps table (upstream reads that as no wisps), or upstream's error. */
private enum WispIdRead {
	WispIds(ids:Array<String>);
	WispIdsMissing;
	WispIdsFailed(message:String);
}

/** The wisps of an unbounded wisp search, no wisps table, or upstream's error. */
private enum WispSearch {
	WispsFound(wisps:Array<IssueListItem>);
	WispsMissing;
	WispsFailed(message:String);
}

/** The descendant query's rows, its native error, or upstream's wrapped scan error. */
private enum DescendantRead {
	Descendants(ids:Array<String>);
	DescendantsFailed(error:go.NativeError);
	DescendantsFailedWith(message:String);
}
