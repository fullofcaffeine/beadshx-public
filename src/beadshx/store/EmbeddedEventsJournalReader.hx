package beadshx.store;

import haxe.Int64;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EventsJournal.EventsJournalRead;

/** Own one rolled-back read transaction for `bd events tail` or `bd events export`; the read is authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedEventsJournalReader {
	public static function read(beadsDir:String, databaseName:String, since:Int64, limit:Int64):StoreResult<EventsJournalRead> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only events snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded events connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded events transaction: ${started.value2.toString()}');
		}
		final outcome = SqlEventsJournalReader.read(context, started.value1, since, limit);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded events transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded events database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded events connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
