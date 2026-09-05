package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** Result of one Haxe-owned partial-ID candidate scan. */
enum EmbeddedIssueIdSearchResult {
	EmbeddedIssueIds(ids:Array<String>);
	EmbeddedIssueIdSearchFailure(message:String);
}

/** Supplies deduplicated issue and wisp IDs to Haxe abbreviation policy. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueIdSearch {
	static final READ_IDS = "SELECT id FROM (" + "SELECT id FROM issues WHERE LOWER(id) LIKE ? " + "UNION SELECT id FROM wisps WHERE LOWER(id) LIKE ?"
		+ ") candidates ORDER BY id ASC";

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(query:String):EmbeddedIssueIdSearchResult {
		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.commitName = "BeadsHX read-only issue ID search";
		config.commitEmail = "beadshx-readonly@invalid";
		config.database = databaseName;
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		if (openedConnector.value2 != null)
			return EmbeddedIssueIdSearchFailure('open embedded issue-ID connector: ${openedConnector.value2.toString()}');
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final pingError = database.pingContext(context);
		if (pingError != null) {
			database.close();
			connector.close();
			return EmbeddedIssueIdSearchFailure('ping embedded issue-ID database: ${pingError.toString()}');
		}

		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null) {
			database.close();
			connector.close();
			return EmbeddedIssueIdSearchFailure('begin embedded issue-ID transaction: ${openedTransaction.value2.toString()}');
		}
		final transaction = openedTransaction.value1;
		final pattern = "%" + query.toLowerCase() + "%";
		final queried = transaction.queryContext(context, READ_IDS, pattern, pattern);
		if (queried.value2 != null) {
			transaction.rollback();
			database.close();
			connector.close();
			return EmbeddedIssueIdSearchFailure('search embedded issue IDs: ${queried.value2.toString()}');
		}

		final rows = queried.value1;
		final ids = new Array<String>();
		var failure = "";
		while (failure == "" && rows.next()) {
			final id = new NullString();
			final scanError = rows.scan(id);
			if (scanError != null)
				failure = 'scan embedded issue ID: ${scanError.toString()}';
			else if (!id.valid)
				failure = "scan embedded issue ID: id is null";
			else
				ids.push(id.string);
		}
		final rowError = rows.err();
		final closeRowsError = rows.close();
		final rollbackError = transaction.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (failure != "")
			return EmbeddedIssueIdSearchFailure(failure);
		if (rowError != null)
			return EmbeddedIssueIdSearchFailure('finish embedded issue-ID search: ${rowError.toString()}');
		if (closeRowsError != null)
			return EmbeddedIssueIdSearchFailure('close embedded issue-ID search: ${closeRowsError.toString()}');
		if (rollbackError != null)
			return EmbeddedIssueIdSearchFailure('roll back embedded issue-ID search: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return EmbeddedIssueIdSearchFailure('close embedded issue-ID database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return EmbeddedIssueIdSearchFailure('close embedded issue-ID connector: ${closeConnectorError.toString()}');
		return EmbeddedIssueIds(ids);
	}
}
