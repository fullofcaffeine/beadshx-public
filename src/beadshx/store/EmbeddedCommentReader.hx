package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.SqlCommentReader.readSqlDirectIssueComments;

/** Own one read transaction for `bd comments`; the comment read is authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCommentReader {
	public static function read(beadsDir:String, databaseName:String, issueId:String):StoreResult<Array<IssueComment>> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only comments snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded comments connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded comments transaction: ${started.value2.toString()}');
		}
		final outcome = readSqlDirectIssueComments(context, started.value1, issueId);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded comments transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded comments database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded comments connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
