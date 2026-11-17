package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Rows;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.SQL_READ_WISP;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;
import beadshx.store.SqlIssueRow.SqlIssueNativeScanResult;
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
	How: scan the pinned 52-column issue row, then its labels, through precise
	standard-library and Dolt driver externs within one read transaction.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueSummaryReader {
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
		final result = finishSummaryTransaction(readSummaryInTx(context, transaction, id), transaction);
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		final readFailure = switch result {
			case EmbeddedIssueSummaryFailure(_): true;
			case _: false;
		};
		if (readFailure)
			return result;
		if (closeDatabaseError != null)
			return EmbeddedIssueSummaryFailure('close embedded issue database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return EmbeddedIssueSummaryFailure('close embedded issue connector: ${closeConnectorError.toString()}');
		return result;
	}

	/** Owns the read transaction's rollback result, independently of connection cleanup. */
	private static function finishSummaryTransaction(result:EmbeddedIssueSummaryResult, transaction:Tx):EmbeddedIssueSummaryResult {
		final rollbackError = transaction.rollback();
		if (rollbackError == null)
			return result;
		final rollbackMessage = rollbackError.toString();
		return switch result {
			case EmbeddedIssueSummaryFailure(message): EmbeddedIssueSummaryFailure('$message\n$rollbackMessage');
			case _: EmbeddedIssueSummaryFailure(rollbackMessage);
		};
	}

	/** Issues win over wisps; a hard issue error never falls through. */
	private static function readSummaryInTx(context:Context, transaction:Tx, id:String):EmbeddedIssueSummaryResult {
		final issue = readTable(context, transaction, id, false);
		return switch issue {
			case EmbeddedIssueSummaryMissing: readTable(context, transaction, id, true);
			case _: issue;
		};
	}

	private static function readTable(context:Context, transaction:Tx, id:String, isWisp:Bool):EmbeddedIssueSummaryResult {
		final query = isWisp ? SQL_READ_WISP : SQL_READ_ISSUE;
		final queried = transaction.queryNativeContext(context, query, id);
		if (queried.error != null)
			return isTableNotExist(queried.error) ? EmbeddedIssueSummaryMissing : EmbeddedIssueSummaryFailure('get issue: ${queried.error.text()}');
		final result = scanSummaryRows(queried.rows, id);
		return switch result {
			case EmbeddedIssueSummaryFound(summary):
				final labels = readLabels(context, transaction, id, isWisp);
				switch labels {
					case Failure(message): EmbeddedIssueSummaryFailure('get issue labels: $message');
					case Success(_): EmbeddedIssueSummaryFound(summary);
				};
			case _: result;
		};
	}

	/** QueryRow.Scan returns Scan errors first, then successful Scan's Close error. */
	private static function scanSummaryRows(rows:Rows, id:String):EmbeddedIssueSummaryResult {
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			if (rowError == null || isTableNotExist(rowError))
				return EmbeddedIssueSummaryMissing;
			return EmbeddedIssueSummaryFailure('get issue: ${rowError.text()}');
		}
		final scanned = scanSqlIssueFieldsNative(rows, id);
		return switch scanned {
			case SqlIssueScanFailure(error):
				rows.closeNative();
				isTableNotExist(error) ? EmbeddedIssueSummaryMissing : EmbeddedIssueSummaryFailure('get issue: ${error.text()}');
			case SqlIssueDecodeFailure(message):
				rows.closeNative();
				EmbeddedIssueSummaryFailure('get issue: $message');
			case SqlIssueScanned(fields):
				final closeError = rows.closeNative();
				if (closeError != null)
					isTableNotExist(closeError) ? EmbeddedIssueSummaryMissing : EmbeddedIssueSummaryFailure('get issue: ${closeError.text()}'); else
					EmbeddedIssueSummaryFound({
					id: fields.id,
					title: fields.title,
					status: GoReadonlyStore.parseIssueStatus(fields.status),
					priority: fields.priority,
					issueType: GoReadonlyStore.parseIssueType(fields.issueType)
				});
		};
	}

	/** Labels are read for their pinned failure behavior even though summary hides them. */
	private static function readLabels(context:Context, transaction:Tx, id:String, isWisp:Bool):StoreResult<Bool> {
		final table = isWisp ? "wisp_labels" : "labels";
		final queried = transaction.queryNativeContext(context, 'SELECT label FROM $table WHERE issue_id = ? ORDER BY label', id);
		if (queried.error != null)
			return Failure('get labels: ${queried.error.text()}');
		final rows = queried.rows;
		while (rows.next()) {
			final label = go.NativePointer.of("");
			final scanError = rows.scanNative(label);
			if (scanError != null) {
				rows.closeNative();
				return Failure('get labels: scan: ${scanError.text()}');
			}
		}
		final rowError = rows.errNative();
		rows.closeNative();
		return rowError == null ? Success(true) : Failure(rowError.text());
	}
}
