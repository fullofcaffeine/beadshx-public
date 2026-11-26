package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlBlockingAnnotation.IssueBlocking;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueListReader.readQueryCandidates;
import beadshx.store.SqlIssueListReader.readSqlIssueList;
import beadshx.store.SqlIssueListReader.readSqlIssueSearch;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueSearch.SearchedIssues;
import beadshx.store.StoreResult;

/**
	Own the store opens and read transactions of one list page; the list semantics are authored Haxe.

	The page is one read, which loads the list configuration too. A --ready
	page first opens the store as upstream's defer-wake sweep does
	(EmbeddedSession.openForDeferWake). The main page of `bd list` opens the
	store for upstream's LoadStoreListConfig itself (see Application.runList).
	A request for blocking annotations, which the human list prints, adds a
	read, as upstream's list asks its BlockingAnnotator after the page.
	Upstream renders the page undecorated when that read fails, so a failure
	of that read, of its open or of its release leaves the page as it is.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueListReader {
	static final WORDING = EmbeddedReadWording.forNoun("list", false);
	static final SEARCH_WORDING = EmbeddedReadWording.forNoun("search", false);
	static final QUERY_WORDING = EmbeddedReadWording.forNoun("query", false);

	public static function read(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int, layers:IssueListConfigLayers):IssueListResult {
		if (request.ready)
			EmbeddedSession.openForDeferWake(beadsDir, databaseName);
		final result = finishListRead(WORDING,
			EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlIssueList(context, transaction, request, limit, layers)));
		if (!request.blockingAnnotations)
			return result;
		return switch result {
			case ListSuccess(page): ListSuccess(annotated(beadsDir, databaseName, page));
			case ListFailure(_) | ListRowLimitExceeded(_, _, _): result;
		};
	}

	/**
		`bd search` and `label list-all`: the store open of upstream's pre-run,
		then for a status selector other than `all` upstream's
		LoadStoreListConfig (EmbeddedListConfig, three sessions), whose custom
		statuses check the selector before the search opens the store again,
		then the search in one read (readSqlIssueSearch), which carries the
		counted rows that the native facade read on upstream's store. The
		command opens the store for search's follow-up store calls itself.
	**/
	public static function search(beadsDir:String, databaseName:String, query:String, request:IssueListRequest, layers:IssueListConfigLayers):IssueListResult {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		var customStatusNames = new Array<String>();
		if (request.status != "" && request.status != "all") {
			customStatusNames = searchStatusNames(beadsDir, databaseName, layers);
			// Upstream's ApplyStatusFilter refuses a bad selector before SearchIssues opens the store.
			final refused = SqlIssueFilter.applyStatusSelector(new IssueSearchFilter(), request.status, customStatusNames);
			if (refused != null)
				return ListFailure(refused);
		}
		return finishListRead(SEARCH_WORDING,
			EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> readSqlIssueSearch(context, transaction, query, request, customStatusNames)));
	}

	/**
		Upstream search's check of a `--status` selector, which comes before its
		other flag checks (cmd/bd/search.go:114-122): the store open of
		upstream's pre-run, then LoadStoreListConfig (three sessions) and
		ApplyStatusFilter. Null when the selector applies; `all` and an empty
		selector read nothing.
	**/
	public static function searchStatusRefusal(beadsDir:String, databaseName:String, status:String, layers:IssueListConfigLayers):Null<String> {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		if (status == "" || status == "all")
			return null;
		return SqlIssueFilter.applyStatusSelector(new IssueSearchFilter(), status, searchStatusNames(beadsDir, databaseName, layers));
	}

	/** The custom status names of upstream's LoadStoreListConfig (EmbeddedListConfig). */
	static function searchStatusNames(beadsDir:String, databaseName:String, layers:IssueListConfigLayers):Array<String> {
		return [
			for (status in EmbeddedListConfig.load(beadsDir, databaseName, layers).customStatuses)
				status.name
		];
	}

	/**
		Upstream `SearchIssues` with an issue type and a status and no other
		filter, such as the closed gates of `ready --gated`
		(cmd/bd/mol_ready_gated.go:131-141): the IDs of the issues it finds, in
		one read with upstream's query and words (SqlIssueSearch).
	**/
	public static function typedIssueIds(beadsDir:String, databaseName:String, issueType:String, status:String):StoreResult<Array<String>> {
		final filter = new IssueSearchFilter();
		filter.issueType = issueType;
		filter.status = status;
		return SEARCH_WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> switch SqlIssueSearch.searchIssues(context, transaction, filter) {
				case IssuesFound(issues): Success([for (issue in issues) issue.fields.id]);
				case IssuesNotSearched(SearchFailed(message, _)): Failure(message);
				// The filter sets no row cap, so this branch only completes the switch.
				case IssuesNotSearched(SearchRowCap(found, _, cap)): Failure('row cap: $found over $cap');
			}));
	}

	/**
		Upstream `withConn`'s join for a page (`EmbeddedReadWording.joinReadErrors`).
		A row cap comes from inside upstream's store call, and
		`handleMaxRowsError` finds it through the join with `errors.As`, so the
		cap stays and the release errors go.
	**/
	static function finishListRead(wording:EmbeddedReadWording, read:EmbeddedRead<IssueListResult>):IssueListResult {
		return switch read {
			case EmbeddedReadNotStarted(stage, error, _): ListFailure(wording.stageMessage(stage, error));
			case EmbeddedReadFinished(ListRowLimitExceeded(found, source, cap), _): ListRowLimitExceeded(found, source, cap);
			case EmbeddedReadFinished(ListFailure(message), cleanup): ListFailure(EmbeddedReadWording.joinReadErrors(message, cleanup));
			case EmbeddedReadFinished(ListSuccess(page), cleanup):
				final released = EmbeddedReadWording.joinReadErrors(null, cleanup);
				released == null ? ListSuccess(page) : ListFailure(released);
		};
	}

	/** After the store open of upstream's pre-run, every issue and wisp as `bd query` candidates (readQueryCandidates), in one read. */
	public static function queryCandidates(beadsDir:String, databaseName:String):StoreResult<Array<IssueListItem>> {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		return QUERY_WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, readQueryCandidates));
	}

	static function annotated(beadsDir:String, databaseName:String, page:IssueListPage):IssueListPage {
		final ids = [for (item in page.items) item.id];
		final blocking = switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlBlockingAnnotation.annotate(context, transaction, ids)) {
			case EmbeddedReadFinished(Success(value), cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): return page;
		};
		return {items: [for (item in page.items) withBlocking(item, blocking.get(item.id))], hasMore: page.hasMore, formatted: page.formatted};
	}

	static function withBlocking(item:IssueListItem, blocking:Null<IssueBlocking>):IssueListItem {
		if (blocking == null)
			return item;
		return {
			id: item.id,
			title: item.title,
			description: item.description,
			design: item.design,
			acceptanceCriteria: item.acceptanceCriteria,
			notes: item.notes,
			specId: item.specId,
			status: item.status,
			priority: item.priority,
			issueType: item.issueType,
			assignee: item.assignee,
			owner: item.owner,
			estimatedMinutes: item.estimatedMinutes,
			createdAt: item.createdAt,
			createdBy: item.createdBy,
			updatedAt: item.updatedAt,
			startedAt: item.startedAt,
			closedAt: item.closedAt,
			closeReason: item.closeReason,
			closedBySession: item.closedBySession,
			dueAt: item.dueAt,
			deferUntil: item.deferUntil,
			externalRef: item.externalRef,
			sourceSystem: item.sourceSystem,
			metadata: item.metadata,
			wispType: item.wispType,
			moleculeType: item.moleculeType,
			longFields: item.longFields,
			labels: item.labels,
			dependencies: item.dependencies,
			dependencyCount: item.dependencyCount,
			dependentCount: item.dependentCount,
			commentCount: item.commentCount,
			parent: item.parent,
			blockedBy: blocking.blockedBy,
			blocks: blocking.blocks,
			blockingParent: blocking.parent
		};
	}
}
