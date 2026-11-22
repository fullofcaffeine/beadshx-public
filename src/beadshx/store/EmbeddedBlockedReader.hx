package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlBlockedReader.BlockedIssue;
import beadshx.store.SqlBlockedReader.readSqlBlocked;

/** Own one read transaction for `bd blocked`; the blocked-issue semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedBlockedReader {
	public static function read(beadsDir:String, databaseName:String, parentId:String):StoreResult<Array<BlockedIssue>> {
		return EmbeddedReadWording.forNoun("blocked", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlBlocked(context, transaction, parentId)));
	}
}
