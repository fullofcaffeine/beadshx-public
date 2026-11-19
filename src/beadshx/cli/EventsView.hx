package beadshx.cli;

import haxe.Int64;
import haxe.Json;
import beadshx.nativeextern.bytes.Buffer;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.encoding.json.JsonPkg;
import beadshx.store.EventsJournal.EventsJournalRow;
import beadshx.store.EventsJournal.EventsJournalWindow;
import beadshx.store.EventsJournal.eventsTruncatedMessage;

/** JSON lines up to the first row whose payload Go cannot compact, and that failure. */
typedef EventsRecordLines = {
	final text:String;
	final error:Null<String>;
}

/** Upstream eventsCmd help, which `bd events` prints with no subcommand or an unknown one. */
function eventsHelp(globalFlags:String):String {
	return [
		"Read and manage the durable events journal (bd_events_journal).",
		"",
		"The journal records every committed issue mutation as an ordered, replayable",
		"row. Enable it with 'bd config set events-journal true' (or",
		"BD_EVENTS_JOURNAL=1). Records are emitted only while it is enabled.",
		"",
		"Retention is automatic: an enabled journal is bounded to the retention floors",
		"(events-journal-retain-days / -rows, 7 days / 100k rows by default) without",
		"anyone running a command. Disable both floors for an unbounded ledger, or",
		"events-journal-auto-prune for manual control; 'bd events prune' remains for an",
		"earlier, on-demand cut below the floors.",
		"",
		"Coverage and scope:",
		"  - Every mutation through bd's normal write paths (create, update, close,",
		"    reopen, delete, claim, dependency add/remove, label add/remove, comment) is",
		"    journaled in the same transaction as the change. Raw DML run through",
		"    'bd sql' bypasses those paths and is NOT journaled — a known non-coverage.",
		"  - The journal is per-branch working-set state (dolt_ignored): it records the",
		"    mutations committed on the writer's active branch. Rows arrive by direct",
		"    write, not by merge, so a consumer must read the journal on the same branch",
		"    the writer commits to; a branch checkout or merge does not carry journal",
		"    rows across branches.",
		"  - For the same reason the journal is per REPLICA. 'bd dolt pull' and the",
		"    changes a merge settles into this clone are not journaled: those rows",
		"    arrived as data, not as local mutations, and nothing on this clone wrote",
		"    them through the mutation seam. A consumer that mirrors a synced workspace",
		"    must re-baseline (a fresh export or a full re-read) after a sync, because",
		"    the journal describes only what THIS clone mutated.",
		"    Each replica also has its OWN seq space, counted from its own first",
		"    mutation. A checkpoint taken against one replica is meaningless against",
		"    another — the same seq names a different record, and a seq above the other",
		"    replica's head reads as \"caught up\" and stalls forever. Track a checkpoint",
		"    per replica, and re-baseline rather than carry one across.",
		"  - A few writes that happen while a store is being OPENED are unjournaled by",
		"    design: schema migrations and the version reconciliation that runs before",
		"    the workspace's configuration has been applied to the store. They touch",
		"    schema and clone-local metadata, never a bead, so a replaying consumer has",
		"    nothing to apply them to.",
		"  - Dependency records are not symmetric, in two ways.",
		"    Count: a dep_add is emitted for every accepted add, INCLUDING an idempotent",
		"    same-type re-add that only refreshes the edge's metadata. The audit 'events'",
		"    table deduplicates that case and writes nothing; the journal does not. Treat",
		"    dep_add as an upsert of the edge, not as proof the edge is new. A dep_remove",
		"    naming an edge that is already gone emits nothing at all.",
		"    Payload: dep.metadata differs in provenance between the two ops. On dep_add",
		"    it is the value being written, as the caller supplied it; on dep_remove it is",
		"    the raw stored column read back just before the delete. The two can differ",
		"    byte for byte while meaning the same thing, so compare parsed values.",
		"",
		"Structural dependency edits — the ones bd wires up itself rather than a 'bd dep'",
		"verb — write no audit event but DO journal, by design: a replaying consumer",
		"needs the edge either way.",
		"",
		"Usage:",
		"  bd events [command]",
		"",
		"Available Commands:",
		"  export      Print the entire journal from the beginning (JSON lines)",
		"  prune       Delete journal records below a sequence number (retention)",
		"  tail        Print journal records after a sequence number (JSON lines)",
		"",
		"Flags:",
		"  -h, --help   help for events",
		""
	].join("\n") + "\n" + globalFlags + "\nUse \"bd events [command] --help\" for more information about a command.\n";
}

function eventsTailHelp(globalFlags:String):String {
	return [
		"Print events journal records with seq greater than --since, in order.",
		"",
		"Each line is a JSON record:",
		"  {\"seq\":N,\"ts\":\"...\",\"op\":\"create|update|close|delete|dep_add|dep_remove|comment\",",
		"   \"issue_id\":\"...\",\"issue\":{...|null},\"dep\":{\"kind\":..,\"target\":..,\"metadata\":..},\"comment\":{...}}",
		"",
		"Record contract (stable for external consumers):",
		"  seq       int64   counter-assigned inside the mutation's transaction; gapless,",
		"                    strictly increasing in commit order, never reused or reset",
		"  ts        string  UTC insert time, stamped inside the committing transaction",
		"  op        string  one of the seven ops above",
		"  issue_id  string  the mutated issue's id",
		"  issue     object  full issue state AFTER the mutation; null on delete",
		"  dep       object  {\"kind\",\"target\",\"metadata\"} for dep_add / dep_remove; omitted otherwise",
		"  comment   object  {\"id\",\"author\",\"text\",\"created_at\",\"source\"} for comment; omitted otherwise",
		"",
		"Poll with the highest seq seen to consume new mutations incrementally, or pass",
		"--follow to keep printing new records as they are committed (Ctrl-C to stop).",
		"",
		"Retention boundary: if --since is below the oldest retained record — the prefix",
		"you asked for was pruned — the read FAILS instead of silently skipping ahead or",
		"returning an empty success. With --json the failure carries",
		"{\"code\":\"events_journal_truncated\",\"since\":N,\"floor\":F,\"head\":H}: floor is the",
		"oldest seq still retained, head the highest ever assigned. Resume from floor-1",
		"to continue with a known gap, or rebuild from a full export.",
		"",
		"Usage:",
		"  bd events tail [flags]",
		"",
		"Flags:",
		"      --follow      keep printing new records as they are committed (Ctrl-C to stop)",
		"  -h, --help        help for tail",
		"      --limit int   maximum number of records to return (0 = no limit)",
		"      --since int   return records with seq greater than this value",
		""
	].join("\n") + "\n" + globalFlags;
}

function eventsExportHelp(globalFlags:String):String {
	return [
		"Print every events journal record from seq 1, in order, as JSON lines.",
		"",
		"Equivalent to 'bd events tail --since 0'. Like tail, it FAILS rather than",
		"present a pruned journal's surviving suffix as a complete history.",
		"",
		"Usage:",
		"  bd events export [flags]",
		"",
		"Flags:",
		"  -h, --help        help for export",
		"      --limit int   maximum number of records to return (0 = no limit)",
		""
	].join("\n") + "\n" + globalFlags;
}

/**
	Upstream `json.NewEncoder(os.Stdout).Encode(record)` for each row. Payloads are json.RawMessage:
	Go compacts them and escapes HTML, and the first invalid one stops the stream after the lines before it.
	An empty issue payload prints `null`; an empty dep or comment payload is left out.
**/
@:goNative
function renderEventsRecords(rows:Array<EventsJournalRow>):EventsRecordLines {
	final text = new StringBuf();
	for (row in rows) {
		var line = '{"seq":${Int64.toStr(row.seq)},"ts":${Json.stringify(row.ts)},"op":${Json.stringify(row.op)},"issue_id":${Json.stringify(row.issueId)},"issue":';
		final payloads = [
			{name: "", raw: row.issueJson == "" ? "null" : row.issueJson},
			{name: "dep", raw: row.depJson},
			{name: "comment", raw: row.commentJson}
		];
		for (payload in payloads) {
			if (payload.raw == "")
				continue;
			final compacted = new Buffer();
			final error = JsonPkg.compact(compacted, BytesPkg.newBufferString(payload.raw).bytes());
			if (error != null)
				return {text: text.toString(), error: 'json: error calling MarshalJSON for type json.RawMessage: ${error.text()}'};
			line += (payload.name == "" ? "" : ',"${payload.name}":') + compacted.stringValue();
		}
		final escaped = new Buffer();
		JsonPkg.htmlEscape(escaped, BytesPkg.newBufferString(line + "}").bytes());
		text.add(escaped.stringValue() + "\n");
	}
	return {text: text.toString(), error: null};
}

/**
	Upstream `outputJSON` of the truncation payload. Without the envelope, wrapWithSchemaVersion
	round-trips it through float64, so a number above 2^53 prints rounded; the envelope keeps it exact.
**/
function renderEventsTruncatedJson(window:EventsJournalWindow, envelope:Bool):String {
	function number(value:Int64):String {
		return envelope ? Int64.toStr(value) : Json.stringify(Std.parseFloat(Int64.toStr(value)));
	}
	return [
		"{",
		'  "code": "events_journal_truncated",',
		'  "error": ${Json.stringify(eventsTruncatedMessage(window))},',
		'  "floor": ${number(window.floor)},',
		'  "head": ${number(window.head)},',
		'  "schema_version": 1,',
		'  "since": ${number(window.since)}',
		"}",
		""
	].join("\n");
}

/** The hint upstream reportEventsTruncated prints under the human error. */
function eventsTruncatedHint(window:EventsJournalWindow):String {
	return 'resume with --since ${Int64.toStr(window.floor - 1)} to continue from the oldest retained record (accepting the gap), or re-import from scratch';
}
