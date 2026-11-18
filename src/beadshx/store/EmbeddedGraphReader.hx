package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.SqlGraphReader.GraphSubgraph;

/** Own one read transaction for `bd graph`, `bd graph --all` and `bd graph check`; the graph semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedGraphReader {
	public static function readCycles(beadsDir:String, databaseName:String):StoreResult<Array<Array<String>>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readGraphCycles(context, transaction));
	}

	public static function readSubgraph(beadsDir:String, databaseName:String, rootId:String):StoreResult<GraphSubgraph> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readGraphSubgraph(context, transaction, rootId));
	}

	public static function readAll(beadsDir:String, databaseName:String, maxRows:Int):StoreResult<SqlGraphReader.AllGraphLoad> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readAllGraphs(context, transaction, maxRows));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only graph snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded graph connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded graph transaction: ${started.value2.toString()}');
		}
		final outcome = reader(context, started.value1);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded graph transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded graph database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded graph connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
