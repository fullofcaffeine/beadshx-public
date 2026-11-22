package beadshx.store;

import haxe.Int64;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.EventsJournal.EventsJournalRead;

/** Own one rolled-back read transaction for `bd events tail` or `bd events export`; the read is authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedEventsJournalReader {
	public static function read(beadsDir:String, databaseName:String, since:Int64, limit:Int64):StoreResult<EventsJournalRead> {
		return EmbeddedReadWording.forNoun("events", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> SqlEventsJournalReader.read(context, transaction, since, limit)));
	}
}
