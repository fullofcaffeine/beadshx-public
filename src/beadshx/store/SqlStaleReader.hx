package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.SqlIssueBatchReader.readIssuesByIds;

/**
	Lists stale issues as upstream issueops.GetStaleIssuesInTx does for `bd stale`
	(internal/storage/issueops/stale.go:17-95).

	The cutoff is `days` days before now, in UTC. The IDs come from `issues` only:
	not updated since the cutoff, with the requested status (open and in_progress
	when it is empty), not ephemeral, and without a lease heartbeat since the
	cutoff. They are ordered stalest first, and a positive `limit` caps them. The
	records, with their labels in label order, come from upstream's
	GetIssuesByIDsInTx (SqlIssueBatchReader) and keep the ID order. The caller owns
	the transaction.
**/
@:goNative
final class SqlStaleReader {
	public static function readSqlStale(context:Context, transaction:Tx, request:StaleRequest):StoreResult<Array<StaleIssue>> {
		final cutoff = TimePkg.now().utc().addDate(0, 0, -request.days);
		final statusClause = request.status == "" ? "status IN ('open', 'in_progress')" : "status = ?";
		var query = 'SELECT id FROM issues WHERE updated_at < ? AND $statusClause AND (ephemeral = 0 OR ephemeral IS NULL)'
			+ " AND NOT EXISTS (SELECT 1 FROM leases WHERE leases.issue_id = issues.id AND leases.heartbeat_at >= ?)"
			+ " ORDER BY updated_at ASC";
		if (request.limit > 0)
			query += ' LIMIT ${request.limit}';
		final queried = request.status == "" ? transaction.queryContext(context, query, cutoff,
			cutoff) : transaction.queryContext(context, query, cutoff, request.status, cutoff);
		if (queried.value2 != null)
			return Failure('failed to get stale issues: ${queried.value2.toString()}');
		final rows = queried.value1;
		final ids = new Array<String>();
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final scanError = rows.scan(id);
			if (scanError != null) {
				rows.close();
				return Failure('failed to scan stale issue id: ${scanError.toString()}');
			}
			ids.push(id.get());
		}
		final rowError = rows.err();
		rows.close();
		if (rowError != null)
			return Failure('stale issues rows: ${rowError.toString()}');
		if (ids.length == 0)
			return Success([]);

		final records = switch readIssuesByIds(context, transaction, ids) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final byId = new Map<String, StaleIssue>();
		for (record in records)
			byId.set(record.id, record);
		final ordered = new Array<StaleIssue>();
		for (id in ids) {
			final record = byId.get(id);
			if (record != null)
				ordered.push(record);
		}
		return Success(ordered);
	}
}
