package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyCycle;
import beadshx.relation.DependencyCycle.buildCycles;
import beadshx.relation.DependencyCycle.canonicalCyclePaths;
import beadshx.relation.RelatedIssue;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SqlIssueNativeScanResult;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.scanSqlIssueFieldsNative;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** The outcome of looking up one cycle member in one table. */
private enum MemberLookup {
	MemberFound(issue:RelatedIssue);

	/** No row with this ID, or no such table: upstream then tries the next table. */
	MemberNotInTable;

	/** Any other read error: upstream stops and reports the member without a record. */
	MemberLookupFailed;
}

/**
	Read every dependency cycle in the caller's SQL snapshot, as upstream DetectCycleReportInTx does.

	Only `blocks` and `conditional-blocks` edges from both dependency tables form the
	graph. Each member is looked up in issues first and then in wisps, with its labels.
	Like upstream, any member lookup that fails counts as a member without a record,
	so the report still lists the cycle and marks it partial. The caller owns the
	transaction and connection lifetime.
**/
@:goNative
final class SqlCycleReader {
	public static function readSqlCycles(context:Context, transaction:Tx):StoreResult<Array<DependencyCycle<RelatedIssue>>> {
		final graph = new Map<String, Array<String>>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final queried = transaction.queryContext(context,
				'SELECT issue_id, COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) AS depends_on_id, type FROM $table');
			if (queried.value2 != null)
				return Failure('dependency graph: query $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final dependsOnId = go.NativePointer.of("");
				final kind = go.NativePointer.of("");
				final scanError = rows.scan(issueId, dependsOnId, kind);
				if (scanError != null) {
					rows.close();
					return Failure('dependency graph: scan $table: ${scanError.toString()}');
				}
				if (kind.get() != "blocks" && kind.get() != "conditional-blocks")
					continue;
				var targets = graph.get(issueId.get());
				if (targets == null) {
					targets = [];
					graph.set(issueId.get(), targets);
				}
				targets.push(dependsOnId.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('dependency graph: rows $table: ${rowError.toString()}');
		}
		return Success(buildCycles(canonicalCyclePaths(graph), id -> readMember(context, transaction, id)));
	}

	static function readMember(context:Context, transaction:Tx, id:String):Null<RelatedIssue> {
		switch lookupMember(context, transaction, id, "issues", "labels") {
			case MemberFound(issue):
				return issue;
			case MemberLookupFailed:
				return null;
			case MemberNotInTable:
		}
		return switch lookupMember(context, transaction, id, "wisps", "wisp_labels") {
			case MemberFound(issue): issue;
			case MemberLookupFailed | MemberNotInTable: null;
		};
	}

	/** Reads one member from one table; a missing row or a missing table lets the caller try wisps. */
	static function lookupMember(context:Context, transaction:Tx, id:String, table:String, labelTable:String):MemberLookup {
		final query = 'SELECT $SQL_ISSUE_COLUMNS FROM $table LEFT JOIN leases ON leases.issue_id = $table.id WHERE $table.id = ?';
		final queried = transaction.queryNativeContext(context, query, id);
		if (queried.error != null)
			return isTableNotExist(queried.error) ? MemberNotInTable : MemberLookupFailed;
		final rows = queried.rows;
		if (!rows.next()) {
			final rowError = rows.errNative();
			rows.closeNative();
			if (rowError != null)
				return isTableNotExist(rowError) ? MemberNotInTable : MemberLookupFailed;
			return MemberNotInTable;
		}
		final fields:SqlIssueFields = switch scanSqlIssueFieldsNative(rows, id) {
			case SqlIssueScanned(value): value;
			case SqlIssueScanFailure(_) | SqlIssueDecodeFailure(_):
				rows.closeNative();
				return MemberLookupFailed;
		};
		final closeError = rows.closeNative();
		if (closeError != null)
			return MemberLookupFailed;

		final queriedLabels = transaction.queryContext(context, 'SELECT label FROM $labelTable WHERE issue_id = ? ORDER BY label', id);
		if (queriedLabels.value2 != null)
			return MemberLookupFailed;
		final labelRows = queriedLabels.value1;
		final labels = new Array<String>();
		while (labelRows.next()) {
			final label = go.NativePointer.of("");
			if (labelRows.scan(label) != null) {
				labelRows.close();
				return MemberLookupFailed;
			}
			labels.push(label.get());
		}
		labelRows.close();
		if (labelRows.err() != null)
			return MemberLookupFailed;
		return MemberFound(relatedIssueFromSql(fields, labels, ""));
	}
}
