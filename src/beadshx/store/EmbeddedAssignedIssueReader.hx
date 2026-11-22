package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

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

	static final WORDING = new EmbeddedReadWording("open embedded assigned-issue connector", "ping embedded assigned-issue database",
		"begin embedded assigned-issue transaction", "roll back assigned issue", "close embedded assigned-issue database",
		"close embedded assigned-issue connector");

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(actor:String, status:String):EmbeddedAssignedIssueResult {
		final read = EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readAssigned(context, transaction, actor, status));
		return switch WORDING.bodyFailureFirst(read) {
			case Failure(message): EmbeddedAssignedIssueFailure(message);
			case Success(result): result;
		};
	}

	/**
		A failed query or row iteration wins over the session's release steps.
		A failed scan is a result: a failed release step still replaces it.
	**/
	static function readAssigned(context:Context, transaction:Tx, actor:String, status:String):StoreResult<EmbeddedAssignedIssueResult> {
		final queried = transaction.queryContext(context, READ_ASSIGNED, actor, status, actor, status);
		if (queried.value2 != null)
			return Failure('read assigned issue: ${queried.value2.toString()}');

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
		if (rowError != null)
			return Failure('finish assigned issue: ${rowError.toString()}');
		if (closeRowsError != null)
			return Failure('close assigned issue: ${closeRowsError.toString()}');
		return Success(result);
	}
}
