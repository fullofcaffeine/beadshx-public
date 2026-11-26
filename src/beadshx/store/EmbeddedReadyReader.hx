package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueListReader.IssueSearchRows;
import beadshx.store.SqlReadyWorkReader.ReadyWorkFilter;

/** The ready page of the first read, or how the read ended. */
private enum ReadyPageRead {
	ReadyPage(filter:ReadyWorkFilter, items:Array<IssueListItem>);
	ReadyStopped(result:ReadyLoadResult);
}

/**
	Own the read transactions of `bd ready`; the ready semantics are authored Haxe.

	What: the ready page, with the read that the view asks for: the counted
	read of `--json` (SqlReadyWorkReader.readReadyWork) or the bare
	GetReadyWork of the human view (readReadyIssues). Then, as the native
	facade did after upstream, the total of a full page (CountReadyWork) and,
	for an empty page, whether any issue is open or in progress
	(GetStatistics). Upstream reads each in its own connection and ignores a
	failure of the last two: an unknown total leaves the page untruncated, and
	an unknown count reads as no open issues. After the bare read of a page
	that is not empty, the human view's buildParentEpicMap reads the issues'
	dependency rows and then each parent, each in its own connection; a failed
	read leaves its titles out.
	How: one embedded session for each read; the first one checks the schema.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedReadyReader {
	static final WORDING = EmbeddedReadWording.forNoun("ready", false);

	public static function read(beadsDir:String, databaseName:String, request:ReadyRequest, query:ReadyQuery):ReadyLoadResult {
		final page = switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> switch SqlReadyWorkReader.buildReadyFilter(request) {
			case Failure(message):
				ReadyStopped(ReadyFailure(message));
			case Success(filter):
				final rows = switch query {
					case ReadyWorkWithCounts: SqlReadyWorkReader.readReadyWork(context, transaction, filter);
					case ReadyWork: SqlReadyWorkReader.readReadyIssues(context, transaction, filter);
				};
				switch rows {
					case SearchRows(items): ReadyPage(filter, items);
					case SearchStopped(SearchFailed(message, _)): ReadyStopped(ReadyFailure(message));
					case SearchStopped(SearchRowCap(found, source, cap)): ReadyStopped(ReadyRowLimitExceeded(found, source, cap));
				}
		}) {
			case EmbeddedReadNotStarted(stage, error, _): ReadyStopped(ReadyFailure(WORDING.stageMessage(stage, error)));
			case EmbeddedReadFinished(value, cleanup): cleanup.length == 0 ? value : ReadyStopped(ReadyFailure(WORDING.cleanupMessage(cleanup[0])));
		};
		return switch page {
			case ReadyStopped(result): result;
			case ReadyPage(filter, items): finish(beadsDir, databaseName, filter, items, query);
		};
	}

	static function finish(beadsDir:String, databaseName:String, filter:ReadyWorkFilter, items:Array<IssueListItem>, query:ReadyQuery):ReadyLoadResult {
		var total = ReadyTotal.TotalUnknown;
		var truncated = false;
		if (filter.limit > 0 && items.length == filter.limit)
			switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> SqlReadyWorkReader.countReadyWork(context, transaction, filter)) {
				case EmbeddedReadFinished(Success(count), cleanup) if (cleanup.length == 0):
					total = TotalKnown(NativeIntegers.fromInt(count));
					truncated = count > items.length;
				case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _):
			}
		var hasOpenIssues = false;
		if (items.length == 0)
			switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> SqlReadyWorkReader.readHasOpenIssues(context, transaction)) {
				case EmbeddedReadFinished(Success(value), cleanup) if (cleanup.length == 0):
					hasOpenIssues = value;
				case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _):
			}
		final epicTitles = switch query {
			case ReadyWork if (items.length > 0): parentEpicTitles(beadsDir, databaseName, items);
			case ReadyWork | ReadyWorkWithCounts: null;
		};
		return ReadySuccess({
			page: {items: items, hasMore: truncated, formatted: ""},
			truncated: truncated,
			total: total,
			hasOpenIssues: hasOpenIssues,
			parentEpicTitles: epicTitles
		});
	}

	/**
		Upstream buildParentEpicMap (cmd/bd/ready.go:362-413): the parent of each
		issue from its dependency rows (GetDependencyRecordsForIssues), then each
		parent once (GetIssue), keeping the epics' titles. Upstream visits the
		parents in Go map order; each visit is a read of its own, so only the
		number of reads shows, and this visits them in the order of the page.
	**/
	static function parentEpicTitles(beadsDir:String, databaseName:String, items:Array<IssueListItem>):Map<String, String> {
		final titles = new Map<String, String>();
		final parents = switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlReadyWorkReader.readParentIds(context, transaction, [for (item in items) item.id])) {
			case EmbeddedReadFinished(Success(value), cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): return titles;
		};
		final epicTitles = new Map<String, String>();
		final visited = new Map<String, Bool>();
		for (item in items) {
			final parentId = parents.get(item.id);
			if (parentId == null || visited.exists(parentId))
				continue;
			visited.set(parentId, true);
			switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> SqlIssueReader.readIssueInTx(context, transaction, parentId)) {
				case EmbeddedReadFinished(Success(parent), cleanup) if (cleanup.length == 0 && parent.issueType == "epic"):
					epicTitles.set(parentId, parent.title);
				case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _):
			}
		}
		for (child in parents.keys()) {
			final parentId = parents.get(child);
			final title = parentId == null ? null : epicTitles.get(parentId);
			if (title != null)
				titles.set(child, title);
		}
		return titles;
	}
}
