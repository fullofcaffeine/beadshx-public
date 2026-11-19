package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;

/** Own one read transaction for `bd types` or `bd statuses`; the custom-entry semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCustomConfigReader {
	public static function readTypes(beadsDir:String, databaseName:String):StoreResult<Array<String>> {
		return read(beadsDir, databaseName, (context, transaction) -> Success(SqlCustomConfigReader.readCustomTypes(context, transaction)));
	}

	public static function readStatuses(beadsDir:String, databaseName:String):StoreResult<Array<CustomConfig.CustomStatus>> {
		return read(beadsDir, databaseName, (context, transaction) -> Success(SqlCustomConfigReader.readCustomStatuses(context, transaction)));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only config snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded config connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded config transaction: ${started.value2.toString()}');
		}
		final outcome = reader(context, started.value1);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded config transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded config database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded config connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
