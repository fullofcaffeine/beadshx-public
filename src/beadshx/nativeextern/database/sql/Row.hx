package beadshx.nativeextern.database.sql;

/** Fixed typed destinations over database/sql.Row.Scan; sql owns conversion and closing. */
@:go.import("database/sql") @:go.package("sql") @:go.name("Row") @:goNative
extern class Row {
	@:go.name("Scan") public function scanInt64(value:NullInt64):go.NativeError;
	@:go.name("Scan") public function scanInt(value:go.NativePointer<Int>):go.NativeError;
	@:go.name("Scan") public function scanBool(value:go.NativePointer<Bool>):go.NativeError;
}
