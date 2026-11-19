package beadshx.store;

import haxe.Int64;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullInt64;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EventsJournal.EventsJournalRead;
import beadshx.store.EventsJournal.EventsJournalRow;
import beadshx.store.EventsJournal.eventsTruncation;
import go.NativePointer;

/**
	Port upstream ReadEventsInTx, which `bd events tail` and `bd events export` read in a rolled-back
	transaction. Nothing here writes: retention belongs to `bd events prune` and to mutating commands.
**/
@:goNative
final class SqlEventsJournalReader {
	static inline final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";

	/** The rows after `since`, oldest first; a positive limit becomes a SQL LIMIT. The window decides truncation. */
	public static function read(context:Context, transaction:Tx, since:Int64, limit:Int64):StoreResult<EventsJournalRead> {
		// Both integers are parsed int64 values, so their decimal text is a safe SQL literal.
		var query = 'SELECT seq, CAST(ts AS CHAR), op, issue_id, issue_json, dep_json, comment_json FROM bd_events_journal WHERE seq > ${Int64.toStr(since)} ORDER BY seq ASC';
		if (limit > 0)
			query += ' LIMIT ${Int64.toStr(limit)}';
		final queried = transaction.queryContext(context, query);
		if (queried.value2 != null)
			return Failure('journal: read since ${Int64.toStr(since)}: ${queried.value2.toString()}');
		final rows = queried.value1;
		final records = new Array<EventsJournalRow>();
		while (rows.next()) {
			final seq = new NullInt64();
			final ts = NativePointer.of("");
			final op = NativePointer.of("");
			final issueId = NativePointer.of("");
			final issueJson = new NullString();
			final depJson = new NullString();
			final commentJson = new NullString();
			final scanError = rows.scan(seq, ts, op, issueId, issueJson, depJson, commentJson);
			if (scanError != null) {
				rows.close();
				return Failure('journal: scan row: ${scanError.toString()}');
			}
			records.push({
				seq: Int64.parseString(StrconvPkg.formatInt(seq.value, 10)),
				ts: normalizeTimestamp(ts.get()),
				op: op.get(),
				issueId: issueId.get(),
				issueJson: SqlIssueRow.value(issueJson),
				depJson: SqlIssueRow.value(depJson),
				commentJson: SqlIssueRow.value(commentJson)
			});
		}
		final iterationError = rows.err();
		rows.close();
		if (iterationError != null)
			return Failure(iterationError.toString());
		return switch eventsTruncation(since, records, () -> readHead(context, transaction)) {
			case Failure(message): Failure(message);
			case Success(null): Success(JournalRecords(records));
			case Success(window): Success(JournalTruncated(window));
		};
	}

	/** The highest sequence number ever assigned; prune never lowers it, and no counter row is a head of 0. */
	static function readHead(context:Context, transaction:Tx):StoreResult<Int64> {
		final queried = transaction.queryContext(context, "SELECT next_seq FROM bd_events_seq WHERE id = 0");
		if (queried.value2 != null)
			return Failure('journal: read seq counter: ${queried.value2.toString()}');
		final rows = queried.value1;
		var head = Int64.ofInt(0);
		if (rows.next()) {
			final value = new NullInt64();
			final scanError = rows.scan(value);
			if (scanError != null) {
				rows.close();
				return Failure('journal: read seq counter: ${scanError.toString()}');
			}
			head = Int64.parseString(StrconvPkg.formatInt(value.value, 10));
		}
		final iterationError = rows.err();
		rows.close();
		return iterationError == null ? Success(head) : Failure('journal: read seq counter: ${iterationError.toString()}');
	}

	/** Upstream normalizeEventsTimestamp: the first layout that parses prints in UTC; otherwise the text stays. */
	static function normalizeTimestamp(raw:String):String {
		for (layout in [
			GO_RFC3339_NANO,
			"2006-01-02 15:04:05.999999999Z07:00",
			"2006-01-02 15:04:05.999999999",
			"2006-01-02 15:04:05"
		]) {
			final parsed = TimePkg.parse(layout, raw);
			if (parsed.value2 == null)
				return parsed.value1.utc().format(GO_RFC3339_NANO);
		}
		return raw;
	}
}
