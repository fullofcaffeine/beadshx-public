package beadshx.nativeextern.database.sql;

import beadshx.nativeextern.time.Time;

/** Typed nullable timestamp scanner for SQL row boundaries. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("NullTime")
@:go.struct
@:goNative
extern class NullTime {
	public function new();

	@:go.name("Time")
	public var time:Time;

	@:go.name("Valid")
	public var valid:Bool;
}
