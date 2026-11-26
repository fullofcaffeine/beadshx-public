package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.Time;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/**
	`bd ping` on an embedded workspace, with authored Haxe.

	Why: upstream's ping (cmd/bd/ping.go) takes the store that its pre-run
	opened and runs a trivial query. The native facade opened that store with
	upstream's strict read-only open, which refuses a database behind the
	binary, so at a remote-migrate gate stop ping refused where upstream warns
	and reads.
	What: upstream's pre-run store open, whose first open checks the schema
	and runs the gate; then, timed as upstream times its command body, one
	store call that runs the query: the scalar count of an empty count
	request (`SELECT COUNT(*) FROM issues`), "the issue count" of upstream's
	help text, as the facade ran it. Discovery ran before, in the
	application, and the store is open when the clock starts, so the resolve
	and store times are zero or close to it. A failed query, or a failed
	release of its session, fails the ping.
	How: Go's monotonic clock, through `time.Now` and `time.Until`, in whole
	milliseconds as Go's `Duration.Milliseconds` truncates them.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedPing {
	static final WORDING = EmbeddedReadWording.forNoun("ping", false);

	public static function check(beadsDir:String, databaseName:String):StoreResult<PingSnapshot> {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		final start = TimePkg.now();
		final storeMs = elapsedMilliseconds(start);
		final counted = WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, countIssues));
		final totalMs = elapsedMilliseconds(start);
		return switch counted {
			case Failure(message): Failure(message);
			case Success(_): Success({
					resolveMs: 0,
					storeMs: storeMs,
					queryMs: totalMs - storeMs,
					totalMs: totalMs
				});
		};
	}

	/** The issue count of an empty count request. */
	static function countIssues(context:Context, transaction:Tx):StoreResult<Int> {
		return switch SqlIssueCountReader.buildCountFilter(emptyCountRequest(), []) {
			case Failure(message): Failure(message);
			case Success(filter): SqlIssueCountReader.countIssues(context, transaction, filter);
		};
	}

	/** Go's `time.Since(start).Milliseconds()`: the elapsed time, truncated to whole milliseconds. */
	static function elapsedMilliseconds(start:Time):Int {
		return Std.int(-TimePkg.until(start).seconds() * 1000);
	}

	/** Upstream's `issueops.CountRequest{}`: no filter, the issues table only. */
	static function emptyCountRequest():CountRequest {
		return {
			status: "",
			issueType: "",
			assignee: "",
			priority: IntAbsent,
			priorityMin: IntAbsent,
			priorityMax: IntAbsent,
			labels: [],
			labelsAny: [],
			titleSearch: "",
			idFilter: "",
			titleContains: "",
			descriptionContains: "",
			notesContains: "",
			timeFilters: [],
			emptyDescription: false,
			noAssignee: false,
			noLabels: false,
			includeInfra: false
		};
	}
}
