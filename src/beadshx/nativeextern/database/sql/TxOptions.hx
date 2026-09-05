package beadshx.nativeextern.database.sql;

/** Exact zero-value transaction options from Go's `database/sql` package. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("TxOptions")
@:go.struct
@:goNative
extern class TxOptions {
	public function new();

	@:go.name("ReadOnly")
	public var readOnly:Bool;
}
