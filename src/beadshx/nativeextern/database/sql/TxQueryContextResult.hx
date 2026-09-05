package beadshx.nativeextern.database.sql;

/** Typed carrier for `(*sql.Tx).QueryContext` rows and error results. */
@:goNative
class TxQueryContextResult {
	public var value1(default, null):Rows;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Rows, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
