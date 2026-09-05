package beadshx.nativeextern.database.sql;

/** Typed nullable text scanner for SQL row boundaries. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("NullString")
@:go.struct
@:goNative
extern class NullString {
	public function new();

	@:go.name("String")
	public var string:String;

	@:go.name("Valid")
	public var valid:Bool;
}
