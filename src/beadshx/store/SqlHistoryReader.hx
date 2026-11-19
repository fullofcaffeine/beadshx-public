package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullInt64;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.NullTime;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.Time;
import beadshx.store.IssueHistory.IssueEvent;
import beadshx.store.IssueHistory.IssueHistoryEntry;
import go.NativePointer;

/**
	Port upstream HistoryInTx and GetEventsInTx, which `bd history` reads through the embedded store.

	The driver scans every time, so each one is formatted in the zone it arrives in: commit dates in
	the local zone and event times in UTC. A deferred Rows.Close error is ignored, as upstream does.
**/
@:goNative
final class SqlHistoryReader {
	static inline final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";
	static inline final GO_DATE_TIME = "2006-01-02 15:04:05";

	/**
		The subquery keeps Dolt from planning `WHERE id = ?` on the history table as a one-row
		primary-key lookup; the history table has one row for each commit that holds the issue.
	**/
	static final HISTORY_QUERY = "SELECT id, title, COALESCE(description, '') AS description, COALESCE(design, '') AS design, "
		+ "COALESCE(acceptance_criteria, '') AS acceptance_criteria, COALESCE(notes, '') AS notes, "
		+ "status, priority, issue_type, assignee, owner, created_by, estimated_minutes, created_at, updated_at, closed_at, close_reason, "
		+ "pinned, mol_type, commit_hash, committer, commit_date FROM (SELECT * FROM dolt_history_issues) h WHERE h.id = ? ORDER BY h.commit_date DESC";

	public static function readIssueHistory(context:Context, transaction:Tx, issueId:String):StoreResult<Array<IssueHistoryEntry>> {
		final queried = transaction.queryContext(context, HISTORY_QUERY, issueId);
		if (queried.value2 != null)
			return Failure("failed to get issue history: " + queried.value2.toString());
		final rows = queried.value1;
		final entries = new Array<IssueHistoryEntry>();
		while (rows.next()) {
			final id = NativePointer.of("");
			final title = NativePointer.of("");
			final description = NativePointer.of("");
			final design = NativePointer.of("");
			final acceptanceCriteria = NativePointer.of("");
			final notes = NativePointer.of("");
			final status = NativePointer.of("");
			final priority = NativePointer.of(0);
			final issueType = NativePointer.of("");
			final assignee = new NullString();
			final owner = new NullString();
			final createdBy = new NullString();
			final estimatedMinutes = new NullInt64();
			final createdAt = new NullString();
			final updatedAt = new NullString();
			final closedAt = new NullTime();
			final closeReason = new NullString();
			final pinned = new NullInt64();
			final moleculeType = new NullString();
			final commitHash = NativePointer.of("");
			final committer = NativePointer.of("");
			final commitDate = new Time();
			final scanError = rows.scan(id, title, description, design, acceptanceCriteria, notes, status, priority, issueType, assignee, owner, createdBy,
				estimatedMinutes, createdAt, updatedAt, closedAt, closeReason, pinned, moleculeType, commitHash, committer, commitDate);
			if (scanError != null) {
				rows.close();
				return Failure("failed to scan history: " + scanError.toString());
			}
			entries.push({
				commitHash: commitHash.get(),
				committer: committer.get(),
				commitDate: commitDate.format(GO_RFC3339_NANO),
				commitDateText: commitDate.format(GO_DATE_TIME),
				issue: {
					id: id.get(),
					title: title.get(),
					description: description.get(),
					design: design.get(),
					acceptanceCriteria: acceptanceCriteria.get(),
					notes: notes.get(),
					status: status.get(),
					priority: priority.get(),
					issueType: issueType.get(),
					assignee: SqlIssueRow.value(assignee),
					owner: SqlIssueRow.value(owner),
					estimatedMinutes: estimatedMinutes.valid ? IntegerPresent(NativeIntegers.fromInt64(estimatedMinutes.value)) : IntegerAbsent,
					createdAt: SqlIssueRow.parseIssueTime(createdAt),
					createdBy: SqlIssueRow.value(createdBy),
					updatedAt: SqlIssueRow.parseIssueTime(updatedAt),
					closedAt: SqlIssueRow.timeValue(closedAt),
					closeReason: SqlIssueRow.value(closeReason),
					pinned: SqlIssueRow.nativeFlag(pinned),
					moleculeType: SqlIssueRow.value(moleculeType)
				}
			});
		}
		final iterationError = rows.err();
		rows.close();
		return iterationError == null ? Success(entries) : Failure(iterationError.toString());
	}

	/** The events table follows the issue's active-wisp probe; a positive limit becomes a SQL LIMIT. */
	public static function readIssueEvents(context:Context, transaction:Tx, issueId:String, limit:Int):StoreResult<Array<IssueEvent>> {
		final table = SqlWispRouting.isActiveWispInTx(context, transaction, issueId) ? "wisp_events" : "events";
		var query = 'SELECT id, issue_id, event_type, actor, old_value, new_value, comment, created_at FROM $table WHERE issue_id = ? ORDER BY created_at DESC';
		if (limit > 0)
			query += ' LIMIT $limit';
		final queried = transaction.queryContext(context, query, issueId);
		if (queried.value2 != null)
			return Failure("get events: " + queried.value2.toString());
		final rows = queried.value1;
		final events = new Array<IssueEvent>();
		while (rows.next()) {
			final id = NativePointer.of("");
			final eventIssueId = NativePointer.of("");
			final eventType = NativePointer.of("");
			final actor = NativePointer.of("");
			final oldValue = new NullString();
			final newValue = new NullString();
			final comment = new NullString();
			final createdAt = new Time();
			final scanError = rows.scan(id, eventIssueId, eventType, actor, oldValue, newValue, comment, createdAt);
			if (scanError != null) {
				rows.close();
				return Failure("scan event: " + scanError.toString());
			}
			events.push({
				id: id.get(),
				issueId: eventIssueId.get(),
				eventType: eventType.get(),
				actor: actor.get(),
				oldValue: oldValue.valid ? oldValue.string : null,
				newValue: newValue.valid ? newValue.string : null,
				comment: comment.valid ? comment.string : null,
				createdAt: createdAt.format(GO_RFC3339_NANO),
				createdAtText: createdAt.format(GO_DATE_TIME)
			});
		}
		final iterationError = rows.err();
		rows.close();
		return iterationError == null ? Success(events) : Failure(iterationError.toString());
	}
}
