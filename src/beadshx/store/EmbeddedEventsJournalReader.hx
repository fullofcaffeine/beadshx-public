package beadshx.store;

import haxe.Int64;
import beadshx.store.EmbeddedSession.EmbeddedRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.EventsJournal.EventsJournalRead;

/** Own one rolled-back read transaction for `bd events tail` or `bd events export`; the read is authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedEventsJournalReader {
	static final WORDING = EmbeddedReadWording.forNoun("events", false);

	public static function read(beadsDir:String, databaseName:String, since:Int64, limit:Int64):StoreResult<EventsJournalRead> {
		return finishJournalRead(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlEventsJournalReader.read(context, transaction, since, limit)));
	}

	/**
		Upstream finds a truncated window inside its store call
		(ReadEventsInTx), so `withConn` joins a failed release step to that
		error; `bd events` still finds the truncation through the join with
		`errors.As` (reportEventsTruncated) and reports the window alone. Every
		other result takes `withConn`'s join.
	**/
	static function finishJournalRead(read:EmbeddedRead<StoreResult<EventsJournalRead>>):StoreResult<EventsJournalRead> {
		return switch read {
			case EmbeddedReadFinished(Success(JournalTruncated(window)), _): Success(JournalTruncated(window));
			case _: WORDING.joinedResult(read);
		};
	}
}
