package beadshx.nativeextern.database.sql;

import beadshx.nativeextern.context.Context;

/** Exact `database/sql.Tx` rollback surface controlled by authored Haxe. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("Tx")
@:go.struct
@:goNative
extern class Tx {
	public function new();

	@:go.name("Rollback")
	public function rollback():go.Error;

	/** One string bind preserves the exact QueryRowContext variadic call shape. */
	@:go.name("QueryRowContext")
	public function queryRowContext(context:Context, query:String, argument:String):Row;

	@:go.tupleReturn
	@:go.name("QueryContext")
	public function queryContext(context:Context, query:String, arguments:haxe.Rest<Dynamic>):TxQueryContextResult;

	/** Lossless query errors for Haxe-owned classification; same database/sql API. */
	@:go.tupleReturn
	@:go.name("QueryContext")
	public function queryNativeContext(context:Context, query:String, arguments:haxe.Rest<Dynamic>):NativeTxQueryResult;
}
