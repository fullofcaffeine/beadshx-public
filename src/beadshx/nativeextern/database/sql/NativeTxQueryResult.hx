package beadshx.nativeextern.database.sql;

/** QueryContext keeps its error identity until the Haxe caller classifies it. */
@:goNative
class NativeTxQueryResult {
	public final rows:Rows;
	public final error:go.NativeError;

	public function new(rows:Rows, error:go.NativeError) {
		this.rows = rows;
		this.error = error;
	}
}
