package beadshx.nativeextern.database.sql;

import beadshx.nativeextern.context.Context;

/**
	What: the exact `database/sql.DB` lifecycle surface used by BeadsHX storage.
	Why: Haxe owns transaction policy while Go's standard library owns connection pooling.
	How: only pool limits, ping, begin, close, and pool statistics cross this
	boundary. Nothing here runs a statement outside a transaction.
**/
@:go.import("database/sql")
@:go.package("sql")
@:go.name("DB")
@:go.struct
@:goNative
extern class DB {
	public function new();

	@:go.name("SetMaxOpenConns")
	public function setMaxOpenConns(count:Int):Void;

	@:go.name("SetMaxIdleConns")
	public function setMaxIdleConns(count:Int):Void;

	@:go.valueArgs("0")
	@:go.name("SetConnMaxIdleTime")
	public function setConnMaxIdleTime(duration:beadshx.nativeextern.time.Duration):Void;

	@:go.valueArgs("0")
	@:go.name("SetConnMaxLifetime")
	public function setConnMaxLifetime(duration:beadshx.nativeextern.time.Duration):Void;

	@:go.name("PingContext")
	public function pingContext(context:Context):go.Error;

	@:go.tupleReturn
	@:go.name("BeginTx")
	public function beginTx(context:Context, options:TxOptions):DBBeginTxResult;

	@:go.name("Close")
	public function close():go.Error;

	@:go.valueReturn
	@:go.name("Stats")
	public function stats():DBStats;
}
