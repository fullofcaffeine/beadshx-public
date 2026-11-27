package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/**
	Reads the `TaskSnapshot` artifact of an embedded workspace in one
	rolled-back read transaction of the shared `EmbeddedSession`, whose open
	also runs upstream's schema skew check.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedTaskSnapshotReader {
	public static function read(beadsDir:String, databaseName:String):StoreResult<String> {
		return EmbeddedReadWording.forNoun("snapshot", true).joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, TaskSnapshot.read));
	}
}
