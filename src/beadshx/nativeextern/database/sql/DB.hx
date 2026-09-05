package beadshx.nativeextern.database.sql;

import beadshx.nativeextern.context.Context;

/**
	What: the exact `database/sql.DB` lifecycle surface used by BeadsHX storage.
	Why: Haxe owns transaction policy while Go's standard library owns connection pooling.
	How: only ping, begin, and close cross this first tracer boundary.
**/
@:go.import("database/sql")
@:go.package("sql")
@:go.name("DB")
@:go.struct
@:goNative
extern class DB {
	public function new();

	@:go.name("PingContext")
	public function pingContext(context:Context):go.Error;

	@:go.tupleReturn
	@:go.name("BeginTx")
	public function beginTx(context:Context, options:TxOptions):DBBeginTxResult;

	@:go.name("Close")
	public function close():go.Error;
}
