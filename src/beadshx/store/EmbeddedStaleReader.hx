package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlStaleReader.readSqlStale;

/** Own one read transaction for `bd stale`; the stale-issue semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedStaleReader {
	public static function read(beadsDir:String, databaseName:String, request:StaleRequest):StoreResult<Array<StaleIssue>> {
		return EmbeddedReadWording.forNoun("stale", false)
			.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlStale(context, transaction, request)));
	}
}
