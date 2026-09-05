package beadshx.nativeextern.database.sql;

/** Exact `database/sql.Rows` iteration and scan lifecycle used by Haxe storage. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("Rows")
@:go.struct
@:goNative
extern class Rows {
	public function new();

	@:go.name("Next")
	public function next():Bool;

	@:go.name("Scan")
	public function scan(destinations:haxe.Rest<Dynamic>):go.Error;

	@:go.name("Err")
	public function err():go.Error;

	@:go.name("Close")
	public function close():go.Error;
}
