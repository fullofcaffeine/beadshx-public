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

	@:go.tupleReturn
	@:go.name("QueryContext")
	public function queryContext(context:Context, query:String, arguments:haxe.Rest<Dynamic>):TxQueryContextResult;
}
