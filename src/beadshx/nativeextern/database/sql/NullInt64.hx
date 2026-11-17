package beadshx.nativeextern.database.sql;

/** database/sql owns integer conversion and errors; validity preserves SQL NULL. */
@:go.import("database/sql") @:go.package("sql") @:go.name("NullInt64") @:go.struct @:goNative
extern class NullInt64 {
	public function new();
	@:go.name("Int64") public var value:go.NativeInt64;
	@:go.name("Valid") public var valid:Bool;
}
