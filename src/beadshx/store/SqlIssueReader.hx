package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.RelatedIssue;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** The outcome of reading one issue from one table. */
private enum IssueTableRead {
	IssueTableFound(issue:RelatedIssue);

	/** No row with this ID, or no such table: the caller tries the next table. */
	IssueTableMissing;

	IssueTableFailed(message:String);
}

/**
	Reads one issue with its labels in the caller's SQL snapshot, like upstream issueops.GetIssueInTx.

	The issues table is read first and the wisps table second. A missing row or a missing
	table moves on to the next table; any other read error stops the read. An ID in
	neither table fails with upstream's `not found: issue <id>`. The caller owns the
	transaction and connection lifetime.
**/
@:goNative
final class SqlIssueReader {
	public static function readIssueInTx(context:Context, transaction:Tx, id:String):StoreResult<RelatedIssue> {
		for (plane in [{table: "issues", labels: "labels"}, {table: "wisps", labels: "wisp_labels"}])
			switch readIssueFromTable(context, transaction, plane.table, plane.labels, id) {
				case IssueTableFound(issue):
					return Success(issue);
				case IssueTableFailed(message):
					return Failure(message);
				case IssueTableMissing:
			}
		return Failure('not found: issue $id');
	}

	static function readIssueFromTable(context:Context, transaction:Tx, table:String, labelTable:String, id:String):IssueTableRead {
		final query = 'SELECT $SQL_ISSUE_COLUMNS FROM $table LEFT JOIN leases ON leases.issue_id = $table.id WHERE $table.id = ?';
		final queried = transaction.queryNativeContext(context, query, id);
		if (queried.error != null)
			return isTableNotExist(queried.error) ? IssueTableMissing : IssueTableFailed('get issue: ${queried.error.text()}');
		final rows = queried.rows;
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			if (rowError != null)
				return isTableNotExist(rowError) ? IssueTableMissing : IssueTableFailed('get issue: ${rowError.text()}');
			return IssueTableMissing;
		}
		final fields:SqlIssueFields = switch scanSqlIssueFieldsNative(rows, id) {
			case SqlIssueScanned(value): value;
			case SqlIssueScanFailure(error):
				rows.closeNative();
				return isTableNotExist(error) ? IssueTableMissing : IssueTableFailed('get issue: ${error.text()}');
			case SqlIssueDecodeFailure(message):
				rows.closeNative();
				return IssueTableFailed('get issue: $message');
		};
		final closeError = rows.closeNative();
		if (closeError != null)
			return IssueTableFailed('get issue: ${closeError.text()}');

		final queriedLabels = transaction.queryContext(context, 'SELECT label FROM $labelTable WHERE issue_id = ? ORDER BY label', id);
		if (queriedLabels.value2 != null)
			return IssueTableFailed('get issue labels: get labels: ${queriedLabels.value2.toString()}');
		final labelRows = queriedLabels.value1;
		final labels = new Array<String>();
		while (labelRows.next()) {
			final label = go.NativePointer.of("");
			final scanError = labelRows.scan(label);
			if (scanError != null) {
				labelRows.close();
				return IssueTableFailed('get issue labels: get labels: scan: ${scanError.toString()}');
			}
			labels.push(label.get());
		}
		labelRows.close();
		final labelError = labelRows.err();
		if (labelError != null)
			return IssueTableFailed('get issue labels: ${labelError.toString()}');
		return IssueTableFound(relatedIssueFromSql(fields, labels, ""));
	}
}
