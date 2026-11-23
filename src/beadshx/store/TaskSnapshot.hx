package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyRead.compareUtf8;
import haxe.Json;

/** The database revision that one snapshot read sees, in its own transaction. */
typedef TaskSnapshotRevision = {
	/** `active_branch()`. */
	final branch:String;

	/** `DOLT_HASHOF('HEAD')`, upstream `GetCurrentCommit`. */
	final commit:String;

	/** `DOLT_HASHOF_DB()`, upstream `GetStateHash`, which also moves on uncommitted and ignored-table writes. */
	final state:String;

	/** The `_project_id` metadata value, or null when the database has none. */
	final projectId:Null<String>;
}

/**
	The read-only task snapshot artifact, schema `beadshx-task-snapshot/1`.

	Why: BHX-M08-09 asks for a deterministic, derived copy of every issue with
	the native revision it comes from, for parity, recovery and Caf consumers.
	Upstream has no such artifact; the owner approved spec v1 on 2026-11-22.

	What: JSON Lines with a line feed after every line. Line 1 is the header:
	`_dolt_branch`, `_dolt_commit`, `_dolt_state`, `_project_id` (left out
	when the database has none), `_records`, `_schema`, `_scope` and `_sort`,
	in byte order, encoded as Go's `encoding/json` encodes them. Every other
	line is upstream `bd export --all`'s line for one issue (`ExportIssueLine`),
	sorted by issue ID in byte order. There are no memory lines and no config
	rows, and nothing that depends on the time, the host, the directory, the
	locale, the environment or the reader.

	How: `read` takes every fact in the caller's one read transaction, so the
	header names exactly the revision that the lines come from. It returns the
	whole artifact, so the caller prints it at once or not at all. A change to
	the header keys, the record set, the record encoding or the order must
	increase the schema number.
**/
@:goNative
final class TaskSnapshot {
	public static inline final SCHEMA = "beadshx-task-snapshot/1";
	public static inline final SCOPE = "all-issues";
	public static inline final SORT = "id-bytewise";

	/** The refusal for every workspace but an embedded one, in the words of the other embedded-only commands. */
	public static inline final ROUTE_UNAVAILABLE = "snapshot is not available yet for server-mode or proxied workspaces in this build";

	/** Upstream's metadata key for the project identity (`workapi.MetadataKeyProjectID`). */
	static inline final PROJECT_ID_KEY = "_project_id";

	public static function read(context:Context, transaction:Tx):StoreResult<String> {
		final revision = switch readRevision(context, transaction) {
			case Failure(message): return Failure('failed to read the database revision: $message');
			case Success(value): value;
		};
		final issues = switch SqlExportReader.readAllIssues(context, transaction) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		issues.sort((left, right) -> compareUtf8(left.fields.id, right.fields.id));
		final lines = new Array<String>();
		for (issue in issues)
			switch ExportIssueLine.render(issue) {
				case Failure(message):
					return Failure(message);
				case Success(line):
					lines.push(line);
			}
		final artifact = new StringBuf();
		artifact.add(renderHeader(revision, lines.length) + "\n");
		for (line in lines)
			artifact.add(line + "\n");
		return Success(artifact.toString());
	}

	/** The header line: one compact JSON object with its keys in byte order. */
	public static function renderHeader(revision:TaskSnapshotRevision, records:Int):String {
		final fields = [
			'"_dolt_branch":${Json.stringify(revision.branch)}',
			'"_dolt_commit":${Json.stringify(revision.commit)}',
			'"_dolt_state":${Json.stringify(revision.state)}'
		];
		if (revision.projectId != null)
			fields.push('"_project_id":${Json.stringify(revision.projectId)}');
		fields.push('"_records":$records');
		fields.push('"_schema":${Json.stringify(SCHEMA)}');
		fields.push('"_scope":${Json.stringify(SCOPE)}');
		fields.push('"_sort":${Json.stringify(SORT)}');
		return ExportIssueLine.escapeHtml('{${fields.join(",")}}');
	}

	/**
		The revision, read as upstream's `GetCurrentCommit`, `GetStateHash`,
		`CurrentBranch` and `GetMetadata("_project_id")` read it. An empty
		`_project_id` counts as none, as upstream's `GetMetadata` returns ""
		for a missing key.
	**/
	static function readRevision(context:Context, transaction:Tx):StoreResult<TaskSnapshotRevision> {
		final branch = switch readText(context, transaction, "SELECT active_branch()", null) {
			case Failure(message): return Failure('active branch: $message');
			case Success(null): return Failure("active branch: no row");
			case Success(value): value;
		};
		final commit = switch readText(context, transaction, "SELECT DOLT_HASHOF('HEAD')", null) {
			case Failure(message): return Failure('current commit: $message');
			case Success(null): return Failure("current commit: no row");
			case Success(value): value;
		};
		final state = switch readText(context, transaction, "SELECT DOLT_HASHOF_DB()", null) {
			case Failure(message): return Failure('state hash: $message');
			case Success(null): return Failure("state hash: no row");
			case Success(value): value;
		};
		final projectId = switch readText(context, transaction, "SELECT value FROM metadata WHERE `key` = ?", PROJECT_ID_KEY) {
			case Failure(message): return Failure('get metadata $PROJECT_ID_KEY: $message');
			case Success(value): value == "" ? null : value;
		};
		return Success({
			branch: branch,
			commit: commit,
			state: state,
			projectId: projectId
		});
	}

	/** The first column of the first row as `(*sql.Row).Scan` reads it into a string, or null without a row. */
	static function readText(context:Context, transaction:Tx, query:String, argument:Null<String>):StoreResult<Null<String>> {
		final queried = argument == null ? transaction.queryContext(context, query) : transaction.queryContext(context, query, argument);
		if (queried.value2 != null)
			return Failure(queried.value2.toString());
		final rows = queried.value1;
		if (!rows.next()) {
			final rowError = rows.err();
			rows.close();
			return rowError == null ? Success(null) : Failure(rowError.toString());
		}
		final value = go.NativePointer.of("");
		final scanError = rows.scan(value);
		final closeError = rows.close();
		if (scanError != null)
			return Failure(scanError.toString());
		if (closeError != null)
			return Failure(closeError.toString());
		return Success(value.get());
	}
}
