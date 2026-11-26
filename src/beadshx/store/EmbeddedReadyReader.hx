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

	What: the ready page (SqlReadyWorkReader.readReadyWork), then, as the native
	facade did after upstream, the total of a full page (CountReadyWork) and,
	for an empty page, whether any issue is open or in progress (GetStatistics).
	Upstream reads each in its own connection and ignores a failure of the last
	two: an unknown total leaves the page untruncated, and an unknown count
	reads as no open issues.
	How: one embedded session for each read; the first one checks the schema.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedReadyReader {
	static final WORDING = EmbeddedReadWording.forNoun("ready", false);

	public static function read(beadsDir:String, databaseName:String, request:ReadyRequest):ReadyLoadResult {
		final page = switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> switch SqlReadyWorkReader.buildReadyFilter(request) {
			case Failure(message):
				ReadyStopped(ReadyFailure(message));
			case Success(filter):
				switch SqlReadyWorkReader.readReadyWork(context, transaction, filter) {
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
			case ReadyPage(filter, items): finish(beadsDir, databaseName, filter, items);
		};
	}

	static function finish(beadsDir:String, databaseName:String, filter:ReadyWorkFilter, items:Array<IssueListItem>):ReadyLoadResult {
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
		return ReadySuccess({
			page: {items: items, hasMore: truncated, formatted: ""},
			truncated: truncated,
			total: total,
			hasOpenIssues: hasOpenIssues
		});
	}
}
