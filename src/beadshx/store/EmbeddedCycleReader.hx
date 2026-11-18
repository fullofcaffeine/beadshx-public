package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.relation.DependencyCycle;
import beadshx.relation.RelatedIssue;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.SqlCycleReader.readSqlCycles;

/** Own one read transaction for `bd dep cycles`; the cycle semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCycleReader {
	public static function read(beadsDir:String, databaseName:String):StoreResult<Array<DependencyCycle<RelatedIssue>>> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only cycle snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded cycle connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded cycle transaction: ${started.value2.toString()}');
		}
		final outcome = readSqlCycles(context, started.value1);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded cycle transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded cycle database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded cycle connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
