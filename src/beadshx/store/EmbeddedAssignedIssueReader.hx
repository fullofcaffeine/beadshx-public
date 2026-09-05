package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** Result of one Haxe-owned assigned-issue lookup. */
enum EmbeddedAssignedIssueResult {
	EmbeddedAssignedIssueFound(id:String);
	EmbeddedAssignedIssueMissing;
	EmbeddedAssignedIssueFailure(message:String);
}

/** Reads the first store-ordered issue assigned to one actor in one status. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedAssignedIssueReader {
	static final READ_ASSIGNED = "SELECT id FROM ("
		+ "SELECT id, priority, created_at FROM issues WHERE assignee = ? AND status = ? "
		+ "UNION ALL SELECT id, priority, created_at FROM wisps WHERE assignee = ? AND status = ?"
		+ ") assigned ORDER BY priority ASC, created_at DESC, id ASC LIMIT 1";

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(actor:String, status:String):EmbeddedAssignedIssueResult {
		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.commitName = "BeadsHX read-only assigned issue";
		config.commitEmail = "beadshx-readonly@invalid";
		config.database = databaseName;
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		if (openedConnector.value2 != null)
			return EmbeddedAssignedIssueFailure('open embedded assigned-issue connector: ${openedConnector.value2.toString()}');
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final pingError = database.pingContext(context);
		if (pingError != null) {
			database.close();
			connector.close();
			return EmbeddedAssignedIssueFailure('ping embedded assigned-issue database: ${pingError.toString()}');
		}

		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null) {
			database.close();
			connector.close();
			return EmbeddedAssignedIssueFailure('begin embedded assigned-issue transaction: ${openedTransaction.value2.toString()}');
		}
		final transaction = openedTransaction.value1;
		final queried = transaction.queryContext(context, READ_ASSIGNED, actor, status, actor, status);
		if (queried.value2 != null) {
			transaction.rollback();
			database.close();
			connector.close();
			return EmbeddedAssignedIssueFailure('read assigned issue: ${queried.value2.toString()}');
		}

		final rows = queried.value1;
		var result:EmbeddedAssignedIssueResult = EmbeddedAssignedIssueMissing;
		if (rows.next()) {
			final id = new NullString();
			final scanError = rows.scan(id);
			if (scanError != null)
				result = EmbeddedAssignedIssueFailure('scan assigned issue: ${scanError.toString()}');
			else if (!id.valid)
				result = EmbeddedAssignedIssueFailure("scan assigned issue: id is null");
			else
				result = EmbeddedAssignedIssueFound(id.string);
		}
		final rowError = rows.err();
		final closeRowsError = rows.close();
		final rollbackError = transaction.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rowError != null)
			return EmbeddedAssignedIssueFailure('finish assigned issue: ${rowError.toString()}');
		if (closeRowsError != null)
			return EmbeddedAssignedIssueFailure('close assigned issue: ${closeRowsError.toString()}');
		if (rollbackError != null)
			return EmbeddedAssignedIssueFailure('roll back assigned issue: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return EmbeddedAssignedIssueFailure('close embedded assigned-issue database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return EmbeddedAssignedIssueFailure('close embedded assigned-issue connector: ${closeConnectorError.toString()}');
		return result;
	}
}
