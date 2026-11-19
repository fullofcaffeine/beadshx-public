package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.IssueHistory.IssueEvent;
import beadshx.store.IssueHistory.IssueHistoryEntry;

/** Own one read transaction for `bd history` or `bd history --events`; the reads are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedHistoryReader {
	public static function readHistory(beadsDir:String, databaseName:String, issueId:String):StoreResult<Array<IssueHistoryEntry>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlHistoryReader.readIssueHistory(context, transaction, issueId));
	}

	public static function readEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):StoreResult<Array<IssueEvent>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlHistoryReader.readIssueEvents(context, transaction, issueId, limit));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only history snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded history connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded history transaction: ${started.value2.toString()}');
		}
		final outcome = reader(context, started.value1);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded history transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded history database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded history connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
