package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.IssueHistory.IssueEvent;
import beadshx.store.IssueHistory.IssueHistoryEntry;

/** Own one read transaction for `bd history` or `bd history --events`; the reads are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedHistoryReader {
	public static function readHistory(beadsDir:String, databaseName:String, issueId:String):StoreResult<Array<IssueHistoryEntry>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlHistoryReader.readIssueHistory(context, transaction, issueId));
	}

	public static function readEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):StoreResult<Array<IssueEvent>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlHistoryReader.readIssueEvents(context, transaction, issueId, limit));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		return EmbeddedReadWording.forNoun("history", false).cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, reader));
	}
}
