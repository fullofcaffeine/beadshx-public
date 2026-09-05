package beadshx.nativeextern.database.sql;

/** Typed carrier for the `(*sql.DB).BeginTx` transaction and error results. */
@:goNative
class DBBeginTxResult {
	public var value1(default, null):Tx;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Tx, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
