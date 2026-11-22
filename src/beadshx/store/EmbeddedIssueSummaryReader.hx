package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Rows;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.EmbeddedSession.EmbeddedSessionCleanupFailure;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.SQL_READ_WISP;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;
import beadshx.store.SqlIssueRow.SqlIssueNativeScanResult;

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
	static final WORDING = EmbeddedReadWording.forNoun("issue", true);

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(id:String):EmbeddedIssueSummaryResult {
		return switch EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSummaryInTx(context, transaction, id)) {
			case EmbeddedReadNotStarted(stage, error, _): EmbeddedIssueSummaryFailure(WORDING.stageMessage(stage, error));
			case EmbeddedReadFinished(result, cleanup): finishSummaryRead(result, cleanup);
		};
	}

	/** A failed rollback joins the read's result; a failed close counts only after a successful read. */
	private static function finishSummaryRead(result:EmbeddedIssueSummaryResult, cleanup:Array<EmbeddedSessionCleanupFailure>):EmbeddedIssueSummaryResult {
		var rollbackError:Null<go.Error> = null;
		final closeFailures = new Array<EmbeddedSessionCleanupFailure>();
		for (failure in cleanup)
			switch failure {
				case SessionRollbackFailed(error):
					rollbackError = error;
				case SessionCloseDatabaseFailed(_) | SessionCloseConnectorFailed(_):
					closeFailures.push(failure);
			}
		final rolledBack = finishSummaryTransaction(result, rollbackError);
		return switch rolledBack {
			case EmbeddedIssueSummaryFailure(_): rolledBack;
			case _: closeFailures.length == 0 ? rolledBack : EmbeddedIssueSummaryFailure(WORDING.cleanupMessage(closeFailures[0]));
		};
	}

	/** Owns the read transaction's rollback result, independently of connection cleanup. */
	private static function finishSummaryTransaction(result:EmbeddedIssueSummaryResult, rollbackError:Null<go.Error>):EmbeddedIssueSummaryResult {
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
