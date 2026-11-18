package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.RelatedIssue;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.scanSqlIssueFields;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/**
	Reads full issue records, with labels, for an explicit list of IDs.

	This ports upstream issueops.GetIssuesByIDsInTx: IDs that exist in wisps are read
	from wisps, the others from issues, in batches of 200, and each batch's labels
	come from the matching label table. Missing IDs are skipped. Records keep the
	read order, issues first; callers sort when order matters. The caller owns the
	transaction.
**/
@:goNative
final class SqlIssueBatchReader {
	static inline final BATCH_SIZE = 200;

	public static function readIssuesByIds(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Array<RelatedIssue>> {
		if (ids.length == 0)
			return Success([]);
		final wisps = switch readWispIdSet(context, transaction, ids) {
			case Failure(message): return Failure('get issues by IDs: build wisp set: $message');
			case Success(value): value;
		};
		final durableIds = [for (id in ids) if (!wisps.exists(id)) id];
		final wispIds = [for (id in ids) if (wisps.exists(id)) id];
		final issues = new Array<RelatedIssue>();
		for (plane in [
			{table: "issues", labels: "labels", ids: durableIds},
			{table: "wisps", labels: "wisp_labels", ids: wispIds}
		]) {
			var start = 0;
			while (start < plane.ids.length) {
				final batch = plane.ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				switch readBatch(context, transaction, plane.table, plane.labels, batch) {
					case Failure(message):
						return Failure(message);
					case Success(rows):
						for (row in rows)
							issues.push(row);
				}
			}
		}
		return Success(issues);
	}

	static function readBatch(context:Context, transaction:Tx, table:String, labelTable:String, batch:Array<String>):StoreResult<Array<RelatedIssue>> {
		final placeholders = [for (_ in batch) "?"].join(",");
		final arguments:Array<Dynamic> = [for (id in batch) id];
		final queried = transaction.queryContext(context,
			'SELECT $SQL_ISSUE_COLUMNS FROM $table LEFT JOIN leases ON leases.issue_id = $table.id WHERE id IN ($placeholders)', ...arguments);
		if (queried.value2 != null)
			return Failure('get issues by IDs from $table: ${queried.value2.toString()}');
		final rows = queried.value1;
		final order = new Array<String>();
		final fields = new Map<String, SqlIssueRow.SqlIssueFields>();
		while (rows.next())
			switch scanSqlIssueFields(rows, "", RelationHydration) {
				case Failure(message):
					rows.close();
					return Failure('get issues by IDs: scan: $message');
				case Success(value):
					order.push(value.id);
					fields.set(value.id, value);
			}
		rows.close();
		final rowError = rows.err();
		if (rowError != null)
			return Failure('get issues by IDs: rows: ${rowError.toString()}');

		final labels = new Map<String, Array<String>>();
		for (id in order)
			labels.set(id, []);
		if (order.length > 0) {
			final queriedLabels = transaction.queryContext(context,
				'SELECT issue_id, label FROM $labelTable WHERE issue_id IN ($placeholders) ORDER BY issue_id, label', ...arguments);
			if (queriedLabels.value2 != null)
				return Failure('get issues by IDs: labels from $labelTable: ${queriedLabels.value2.toString()}');
			final labelRows = queriedLabels.value1;
			while (labelRows.next()) {
				final issueId = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = labelRows.scan(issueId, label);
				if (scanError != null) {
					labelRows.close();
					return Failure('get issues by IDs: scan label: ${scanError.toString()}');
				}
				final values = labels.get(issueId.get());
				if (values != null)
					values.push(label.get());
			}
			labelRows.close();
			final labelError = labelRows.err();
			if (labelError != null)
				return Failure('get issues by IDs: label rows: ${labelError.toString()}');
		}

		final records = new Array<RelatedIssue>();
		for (id in order) {
			final issue = fields.get(id);
			final issueLabels = labels.get(id);
			if (issue != null && issueLabels != null)
				records.push(relatedIssueFromSql(issue, issueLabels, ""));
		}
		return Success(records);
	}

	/** Ports upstream WispIDSetInTx: an empty or missing wisps table means no wisps. */
	static function readWispIdSet(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, Bool>> {
		final result = new Map<String, Bool>();
		final probe = transaction.queryNativeContext(context, "SELECT 1 FROM wisps LIMIT 1");
		if (probe.error != null)
			return isTableNotExist(probe.error) ? Success(result) : Failure('wisp id set: probe: ${probe.error.text()}');
		final present = probe.rows.next();
		final probeError = probe.rows.errNative();
		final closeError = probe.rows.closeNative();
		if (probeError != null)
			return isTableNotExist(probeError) ? Success(result) : Failure('wisp id set: probe: ${probeError.text()}');
		if (closeError != null)
			return isTableNotExist(closeError) ? Success(result) : Failure('wisp id set: probe: ${closeError.text()}');
		if (!present)
			return Success(result);
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + BATCH_SIZE);
			start += BATCH_SIZE;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final queried = transaction.queryContext(context, 'SELECT id FROM wisps WHERE id IN (${[for (_ in batch) "?"].join(",")})', ...arguments);
			if (queried.value2 != null)
				return Failure('wisp id set: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final scanError = rows.scan(id);
				if (scanError != null) {
					rows.close();
					return Failure('wisp id set: scan: ${scanError.toString()}');
				}
				result.set(id.get(), true);
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('wisp id set: rows: ${rowError.toString()}');
		}
		return Success(result);
	}
}
