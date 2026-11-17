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

	/** Preserve the concrete driver cause for QueryRow-style missing-table routing. */
	@:go.name("Scan")
	public function scanNative(destinations:haxe.Rest<Dynamic>):go.NativeError;

	@:go.name("Err")
	public function err():go.Error;

	/** Preserve the driver's concrete error for optional-table classification. */
	@:go.name("Err")
	public function errNative():go.NativeError;

	@:go.name("Close")
	public function close():go.Error;

	/** Preserve the driver's concrete error when QueryRow.Scan would return Close. */
	@:go.name("Close")
	public function closeNative():go.NativeError;
}
