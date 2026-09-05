package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** Result of one Haxe-owned exact embedded issue-summary lookup. */
enum EmbeddedIssueSummaryResult {
	EmbeddedIssueSummaryFound(summary:IssueSummary);
	EmbeddedIssueSummaryMissing;
	EmbeddedIssueSummaryFailure(message:String);
}

/**
	Reads the compact issue identity needed during command resolution.

	What: probes the durable issue and ephemeral wisp planes in one read transaction.
	Why: exact issue lookup is first-party Beads behavior and must not remain behind
	`issueops.Reader` in the completed Haxe port.
	How: scan five concrete scalar fields through precise standard-library and Dolt
	driver externs, then roll back before closing every native resource.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueSummaryReader {
	static final READ_SUMMARY = "SELECT id, title, status, priority, issue_type FROM issues WHERE id = ? "
		+ "UNION ALL SELECT id, title, status, priority, issue_type FROM wisps WHERE id = ? LIMIT 1";

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(id:String):EmbeddedIssueSummaryResult {
		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.commitName = "BeadsHX read-only issue summary";
		config.commitEmail = "beadshx-readonly@invalid";
		config.database = databaseName;
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		if (openedConnector.value2 != null)
			return EmbeddedIssueSummaryFailure('open embedded issue connector: ${openedConnector.value2.toString()}');
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final pingError = database.pingContext(context);
		if (pingError != null) {
			database.close();
			connector.close();
			return EmbeddedIssueSummaryFailure('ping embedded issue database: ${pingError.toString()}');
		}

		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null) {
			database.close();
			connector.close();
			return EmbeddedIssueSummaryFailure('begin embedded issue transaction: ${openedTransaction.value2.toString()}');
		}
		final transaction = openedTransaction.value1;
		final queried = transaction.queryContext(context, READ_SUMMARY, id, id);
		if (queried.value2 != null) {
			transaction.rollback();
			database.close();
			connector.close();
			return EmbeddedIssueSummaryFailure('read issue summary "$id": ${queried.value2.toString()}');
		}

		final rows = queried.value1;
		var result:EmbeddedIssueSummaryResult = EmbeddedIssueSummaryMissing;
		if (rows.next()) {
			final storedId = new NullString();
			final title = new NullString();
			final status = new NullString();
			final priority = new NullString();
			final issueType = new NullString();
			final scanError = rows.scan(storedId, title, status, priority, issueType);
			if (scanError != null)
				result = EmbeddedIssueSummaryFailure('scan issue summary "$id": ${scanError.toString()}');
			else if (!storedId.valid || !title.valid || !status.valid || !priority.valid || !issueType.valid)
				result = EmbeddedIssueSummaryFailure('scan issue summary "$id": required field is null');
			else {
				final parsedPriority = Std.parseInt(priority.string);
				if (parsedPriority == null)
					result = EmbeddedIssueSummaryFailure('scan issue summary "$id": priority is not an integer');
				else
					result = EmbeddedIssueSummaryFound({
						id: storedId.string,
						title: title.string,
						status: GoReadonlyStore.parseIssueStatus(status.string),
						priority: parsedPriority,
						issueType: GoReadonlyStore.parseIssueType(issueType.string)
					});
			}
		}
		final rowError = rows.err();
		final closeRowsError = rows.close();
		final rollbackError = transaction.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rowError != null)
			return EmbeddedIssueSummaryFailure('finish issue summary "$id": ${rowError.toString()}');
		if (closeRowsError != null)
			return EmbeddedIssueSummaryFailure('close issue summary "$id": ${closeRowsError.toString()}');
		if (rollbackError != null)
			return EmbeddedIssueSummaryFailure('roll back issue summary "$id": ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return EmbeddedIssueSummaryFailure('close embedded issue database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return EmbeddedIssueSummaryFailure('close embedded issue connector: ${closeConnectorError.toString()}');
		return result;
	}
}
