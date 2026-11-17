import beadshx.cli.Application;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.store.IssueLongFields;
import beadshx.store.IssueRecord;
import beadshx.store.SqlIssueRow;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import SqlTestValues.DriverValue;

private typedef SqlPresenceCase = {
	final name:String;
	final externalRef:Null<String>;
	final commit:Null<String>;
	final externalJson:Null<String>;
	final commitJson:Null<String>;
}

/** Lossless native rows exercise only the two pointer-string slots in the pinned52-column projection. */
@:access(beadshx.cli.Application)
@:access(Main)
@:goNative
class SqlPresence {
	public static function check(failures:Array<String>):Void {
		// Pinned 52-column scan positions must select the nullable values directly.
		final columns = SqlIssueRow.SQL_ISSUE_COLUMNS.split(",").map(StringTools.trim);
		if (columns.length != 52 || columns[18] != "external_ref")
			failures.push("SQL projection must preserve external_ref NULL without COALESCE");
		if (columns.length != 52 || columns[22] != "compacted_at_commit")
			failures.push("SQL projection must preserve compacted_at_commit NULL without COALESCE");
		final cases:Array<SqlPresenceCase> = [
			{
				name: "NULL",
				externalRef: null,
				commit: null,
				externalJson: null,
				commitJson: null
			},
			{
				name: "empty",
				externalRef: "",
				commit: "",
				externalJson: '"external_ref": ""',
				commitJson: '"compacted_at_commit": ""'
			},
			{
				name: "distinct text",
				externalRef: "ext-17",
				commit: "commit-29",
				externalJson: '"external_ref": "ext-17"',
				commitJson: '"compacted_at_commit": "commit-29"'
			},
			{
				name: "NULL reference empty commit",
				externalRef: null,
				commit: "",
				externalJson: null,
				commitJson: '"compacted_at_commit": ""'
			},
			{
				name: "empty reference NULL commit",
				externalRef: "",
				commit: null,
				externalJson: '"external_ref": ""',
				commitJson: null
			},
			{
				name: "literal null text",
				externalRef: "NULL",
				commit: "null",
				externalJson: '"external_ref": "NULL"',
				commitJson: '"compacted_at_commit": "null"'
			}
		];
		for (testCase in cases) {
			final fields = scan(testCase.externalRef, testCase.commit);
			if (fields.externalRef != testCase.externalRef)
				failures.push(testCase.name + " SQL external_ref presence/value");
			if (fields.compactedAtCommit != testCase.commit)
				failures.push(testCase.name + " SQL compacted_at_commit presence/value");
			final record:IssueRecord = fields;
			final shared = Main.fieldsOf(Application.renderIssueRecordFields(record, "    "));
			Main.checkField(shared, "external_ref", testCase.externalJson, testCase.name + " SQL shared JSON");
			final related = relatedIssue(record, [], longFields(fields), "blocks");
			final raw = Main.fieldsOf(Application.renderRawIssueFields(related));
			Main.checkField(raw, "external_ref", testCase.externalJson, testCase.name + " SQL related JSON");
			Main.checkField(raw, "compacted_at_commit", testCase.commitJson, testCase.name + " SQL related JSON");
			// Ordinary nullable strings deliberately retain their previous empty omission rule.
			Main.checkField(raw, "assignee", null, testCase.name + " ordinary empty control");
		}
	}

	static function scan(externalRef:Null<String>, commit:Null<String>):SqlIssueFields {
		final opened = PresenceMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		final mock = opened.mock;
		mock.expectBegin();
		// Names and positions are independently spelled; this is not the separate52-slot ABI audit.
		// Independent pinned row order; NULL and present empty remain distinct cells.
		final columns = "id,content_hash,title,description,design,acceptance_criteria,notes,status,priority,issue_type,assignee,estimated_minutes,created_at,created_by,owner,updated_at,started_at,closed_at,external_ref,spec_id,compaction_level,compacted_at,compacted_at_commit,original_size,source_repo,close_reason,closed_by_session,sender,ephemeral,no_history,wisp_type,pinned,is_template,await_type,await_id,timeout_ns,waiters,mol_type,event_kind,actor,target,payload,due_at,defer_until,work_type,source_system,metadata,row_lock,storage_class,lease_expires_at,heartbeat_at,granted_node".split(",");
		final values:Array<Null<String>> = [for (_ in 0...52) ""];
		for (index in [11, 16, 17, 21, 23, 28, 29, 31, 32, 35, 42, 43, 47, 49, 50])
			values[index] = null;
		values[8] = "0";
		values[0] = "presence-1";
		values[2] = "Presence";
		values[7] = "open";
		values[9] = "task";
		values[12] = "2026-01-01T00:00:00Z";
		values[15] = values[12];
		values[18] = externalRef;
		values[20] = "1";
		values[22] = commit;
		values[36] = "[]";
		final rows = PresenceMocks.rows(go.NativeStringSlice.fromArray(columns));
		rows.addRow(...SqlTestValues.fromStrings(values));
		mock.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(rows).closed();
		mock.expectRollback();
		mock.expectClose();
		final context = ContextPkg.background();
		final tx = opened.database.beginTx(context, new TxOptions());
		if (tx.value2 != null)
			throw tx.value2.toString();
		final result = SqlIssueRow.readSqlIssueFields(context, tx.value1, SqlIssueRow.SQL_READ_ISSUE, "presence-1");
		final rollback = tx.value1.rollback();
		final close = opened.database.close();
		final verify = mock.verify();
		if (rollback != null || close != null || verify != null)
			throw "presence mock cleanup/expectations failed";
		return switch result {
			case Success(fields): if (fields == null) throw "presence row disappeared"; else fields;
			case Failure(message): throw message;
		};
	}

	static function longFields(fields:SqlIssueFields):IssueLongFields {
		return {
			isBlocked: fields.isBlocked,
			leaseExpiresAt: fields.leaseExpiresAt,
			heartbeatAt: fields.heartbeatAt,
			leaseGrantedNode: fields.leaseGrantedNode,
			compactionLevel: fields.compactionLevel,
			compactedAt: fields.compactedAt,
			compactedAtCommit: fields.compactedAtCommit,
			originalSize: fields.originalSize,
			sender: fields.sender,
			ephemeral: fields.ephemeral,
			noHistory: fields.noHistory,
			storageClass: fields.storageClass,
			pinned: fields.pinned,
			template: fields.template,
			bondedFrom: [],
			awaitType: fields.awaitType,
			awaitId: fields.awaitId,
			timeout: fields.timeout,
			timeoutNanos: fields.timeoutNanos,
			waiters: fields.waiters,
			sourceFormula: "",
			sourceLocation: "",
			workType: fields.workType,
			eventKind: fields.eventKind,
			actor: fields.actor,
			target: fields.target,
			payload: fields.payload
		};
	}
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock")
extern class PresenceMocks {
	@:go.name("New") @:go.tupleReturn public static function create():PresenceConnection;
	@:go.name("NewRows") public static function rows(columns:go.NativeStringSlice):PresenceRows;
}

class PresenceConnection {
	public final database:DB;
	public final mock:PresenceMock;
	public final error:go.NativeError;

	public function new(database:DB, mock:PresenceMock, error:go.NativeError) {
		this.database = database;
		this.mock = mock;
		this.error = error;
	}
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Sqlmock")
extern interface PresenceMock {
	@:go.name("ExpectBegin") public function expectBegin():PresenceBegin;
	@:go.name("ExpectRollback") public function expectRollback():PresenceRollback;
	@:go.name("ExpectClose") public function expectClose():PresenceClose;
	@:go.name("ExpectQuery") public function expectQuery(query:String):PresenceQuery;
	@:go.name("ExpectationsWereMet") public function verify():go.NativeError;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedBegin") extern class PresenceBegin {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedRollback") extern class PresenceRollback {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedClose") extern class PresenceClose {}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedQuery")
extern class PresenceQuery {
	@:go.name("WillReturnRows") public function rows(rows:haxe.Rest<PresenceRows>):PresenceQuery;
	@:go.name("RowsWillBeClosed") public function closed():PresenceQuery;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Rows")
extern class PresenceRows {
	@:go.name("AddRow") public function addRow(values:haxe.Rest<DriverValue>):PresenceRows;
}
