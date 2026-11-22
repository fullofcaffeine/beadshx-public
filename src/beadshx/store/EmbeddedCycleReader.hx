package beadshx.store;

import beadshx.relation.DependencyCycle;
import beadshx.relation.RelatedIssue;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlCycleReader.readSqlCycles;

/** Own one read transaction for `bd dep cycles`; the cycle semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCycleReader {
	public static function read(beadsDir:String, databaseName:String):StoreResult<Array<DependencyCycle<RelatedIssue>>> {
		return EmbeddedReadWording.forNoun("cycle", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlCycles(context, transaction)));
	}
}
