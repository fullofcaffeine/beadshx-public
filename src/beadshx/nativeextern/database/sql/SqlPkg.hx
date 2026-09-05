package beadshx.nativeextern.database.sql;

import beadshx.nativeextern.doltdriver.Connector;

/** Package functions used to attach the independent Dolt connector to `database/sql`. */
@:go.import("database/sql")
@:go.package("sql")
@:goNative
extern class SqlPkg {
	/**
		What: calls `sql.OpenDB` with the concrete Dolt connector.
		Why: haxe.go does not yet prove arbitrary concrete-to-Go-interface method sets.
		How: the narrowed extern emits the real standard-library call; the Go compiler
		still verifies that `*embedded.Connector` implements `driver.Connector`.
	**/
	@:go.name("OpenDB")
	public static function openDoltDB(connector:Connector):DB;
}
