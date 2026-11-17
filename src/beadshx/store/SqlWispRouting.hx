package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;

/**
	Pinned IsActiveWispInTx treats every failed probe as durable-table routing.
	Each caller executes its own probe; no result is cached across detail reads.
	Class metadata declares this narrowly owned native SQL boundary.
**/
@:goNative
final class SqlWispRouting {
	public static function isActiveWispInTx(context:Context, transaction:Tx, id:String):Bool {
		final active = go.NativePointer.of(0);
		return transaction.queryRowContext(context, "SELECT 1 FROM wisps WHERE id = ? LIMIT 1", id).scanInt(active) == null;
	}
}
