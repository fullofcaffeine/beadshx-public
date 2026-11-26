package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.Time;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EmbeddedSession.EmbeddedRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueSearch.SearchedIssues;

/**
	`bd ping` on an embedded workspace, with authored Haxe.

	Why: upstream's ping (cmd/bd/ping.go) takes the store that its pre-run
	opened and runs a trivial query. The native facade opened that store with
	upstream's strict read-only open, which refuses a database behind the
	binary, so at a remote-migrate gate stop ping refused where upstream warns
	and reads.
	What: upstream's pre-run store open, whose first open checks the schema
	and runs the gate; then, timed as upstream times its command body, its
	one store call: `SearchIssues` with an empty filter and a limit of one
	(SqlIssueSearch). Discovery ran before, in the application, and the store
	is open when the clock starts, so the resolve and store times are zero or
	close to it. A failed search, or a failed release of its session, is
	upstream's `query failed: ` reason (PingFailed). A session that does not
	open fails as the store open of upstream's pre-run would.
	How: Go's monotonic clock, through `time.Now` and `time.Until`, in whole
	milliseconds as Go's `Duration.Milliseconds` truncates them.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedPing {
	static final WORDING = EmbeddedReadWording.forNoun("ping", false);

	public static function check(beadsDir:String, databaseName:String):StoreResult<PingOutcome> {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		final start = TimePkg.now();
		final storeMs = elapsedMilliseconds(start);
		final read = EmbeddedSession.withRead(beadsDir, databaseName, searchOneIssue);
		final totalMs = elapsedMilliseconds(start);
		return switch read {
			case EmbeddedReadNotStarted(stage, error, _): Failure(WORDING.stageMessage(stage, error));
			case EmbeddedReadFinished(searched, cleanup):
				final failure = EmbeddedReadWording.joinReadErrors(switch searched {
					case Failure(message): message;
					case Success(_): null;
				}, cleanup);
				Success(failure != null ? PingFailed('query failed: $failure', totalMs) : PingAnswered({
					resolveMs: 0,
					storeMs: storeMs,
					queryMs: totalMs - storeMs,
					totalMs: totalMs
				}));
		};
	}

	/** Upstream `SearchIssues(ctx, "", IssueFilter{Limit: 1})`. */
	static function searchOneIssue(context:Context, transaction:Tx):StoreResult<Bool> {
		final filter = new IssueSearchFilter();
		filter.limit = 1;
		return switch SqlIssueSearch.searchIssues(context, transaction, filter) {
			case IssuesFound(_): Success(true);
			case IssuesNotSearched(SearchFailed(message, _)): Failure(message);
			// The filter sets no row cap, so this branch only completes the switch.
			case IssuesNotSearched(SearchRowCap(found, _, cap)): Failure('row cap: $found over $cap');
		};
	}

	/** Go's `time.Since(start).Milliseconds()`: the elapsed time, truncated to whole milliseconds. */
	static function elapsedMilliseconds(start:Time):Int {
		return Std.int(-TimePkg.until(start).seconds() * 1000);
	}
}
