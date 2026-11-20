import SqlTestValues.DriverValue;
import beadshx.cli.Application;
import beadshx.cli.Parser;
import beadshx.cli.EnvironmentPort;
import beadshx.cli.JsonSettingPort;
import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.cli.OutputPort;
import beadshx.cli.WatchPort;
import beadshx.identity.SystemActor;
import beadshx.git.GoGitHistory;
import beadshx.workspace.GoWorkspace;
import beadshx.profile.GoProfiler;
import beadshx.store.GoReadonlyStore;
import beadshx.store.IssueRecord;
import beadshx.store.IssueQueryRow;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.readSqlIssueFields;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.query.QueryPredicate;
import beadshx.query.QueryPlan.QueryPredicateExpression;
import beadshx.query.QueryPlan.QueryPredicateTest;
import beadshx.query.QuerySyntax.QueryComparisonOperator;

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock")
extern class Mocks {
	@:go.name("New") @:go.tupleReturn public static function create():MockConnection;
	@:go.name("NewRows") public static function rows(columns:go.NativeStringSlice):MockRows;
}

class MockConnection {
	public final database:DB;
	public final mock:Mock;
	public final error:go.NativeError;

	public function new(database:DB, mock:Mock, error:go.NativeError) {
		this.database = database;
		this.mock = mock;
		this.error = error;
	}
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Sqlmock")
extern interface Mock {
	@:go.name("ExpectBegin") public function expectBegin():ExpectedBegin;
	@:go.name("ExpectRollback") public function expectRollback():ExpectedRollback;
	@:go.name("ExpectClose") public function expectClose():ExpectedClose;
	@:go.name("ExpectQuery") public function expectQuery(query:String):ExpectedQuery;
	@:go.name("ExpectationsWereMet") public function verify():go.NativeError;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedBegin") extern class ExpectedBegin {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedRollback") extern class ExpectedRollback {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedClose") extern class ExpectedClose {}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedQuery")
extern class ExpectedQuery {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):ExpectedQuery;
	@:go.name("WillReturnRows") public function rows(rows:haxe.Rest<MockRows>):ExpectedQuery;
	@:go.name("RowsWillBeClosed") public function closed():ExpectedQuery;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Rows")
extern class MockRows {
	@:go.name("FromCSVString") public function fromCsv(values:String):MockRows;
	@:go.name("AddRow") public function addRow(values:haxe.Rest<DriverValue>):MockRows;
	@:go.name("RowError") public function rowError(row:Int, error:go.NativeError):MockRows;
	@:go.name("CloseError") public function closeError(error:go.NativeError):MockRows;
}

/** Deterministic environment and output isolate the real Application boundary. */
final class FixedEnvironment implements EnvironmentPort {
	public function new() {}

	public function value(name:String):String {
		return "";
	}
}

/** These contracts pass --json, so the `json` setting never decides their output. */
final class UnsetJsonSetting implements JsonSettingPort {
	public function new() {}

	public function enabled(selection:WorkspaceSelection):Bool {
		return false;
	}
}

final class UnusedWatch implements WatchPort {
	public function new() {}

	public function start():Void {
		throw "unexpected watch start";
	}

	public function waitForStop():Bool {
		throw "unexpected watch wait";
	}

	public function close():Void {
		throw "unexpected watch close";
	}
}

final class CapturedOutput implements OutputPort {
	public var stdout:String = "";
	public var stderr:String = "";

	final envelope:Bool;

	public function new(envelope:Bool) {
		this.envelope = envelope;
	}

	public function writeStdout(value:String):Void {
		stdout += value;
	}

	public function writeStderr(value:String):Void {
		stderr += value;
	}

	public function renderMarkdown(value:String):String {
		return value;
	}

	public function usesJsonEnvelope():Bool {
		return envelope;
	}

	public function shouldEmitJsonDeprecation():Bool {
		return !envelope;
	}

	public function isStdoutTerminal():Bool {
		return false;
	}

	public function isStderrTerminal():Bool {
		return true;
	}
}

/** SQL read acceptance and query selection must precede atomic JSON output validation. */
@:access(beadshx.cli.Application)
@:goNative
class Main {
	static function main():Void {
		final failures = new Array<String>();
		for (raw in [null, "", "{}", " { } ", "null", "42", "[]"]) {
			try {
				final fields = scan("control", raw);
				final expected = raw == null || raw == "" || raw == "{}" ? "" : raw;
				require(fields.metadata.wireValue() == expected, "SQL metadata bytes or omission changed: " + raw);
			} catch (error:haxe.Exception) {
				failures.push(error.message);
			}
		}
		for (envelope in [false, true]) {
			try {
				checkEscaping(envelope);
			} catch (error:haxe.Exception) {
				failures.push(error.message);
			}
			try {
				checkOutput(envelope);
			} catch (error:haxe.Exception) {
				failures.push(error.message);
			}
		}
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("raw metadata SQL-to-output contracts: PASS");
	}

	static function checkEscaping(envelope:Bool):Void {
		final raw = '{"text":"<>&\u2028\u2029","escaped":"\\u003C"}';
		final fields = scan("escaping", raw);
		require(fields.metadata.wireValue() == raw, "SQL scan normalized valid escape bytes");
		final output = new CapturedOutput(envelope);
		final parser = new Parser(new FixedEnvironment(), new UnsetJsonSetting());
		final application = new Application(parser, output, new SystemActor(), new GoGitHistory(), new GoWorkspace(), new GoReadonlyStore(), new GoProfiler(),
			new UnusedWatch());
		final invocation = switch parser.parse(["query", "status=open", "--json"]) {
			case Parsed(value): value;
			case _: throw "escaping query invocation did not parse";
		};
		require(application.renderQuery(invocation, [row(fields)], false) == 0, "valid escaping metadata failed output");
		require(output.stdout.indexOf('"text": "\\u003c\\u003e\\u0026\\u2028\\u2029"') >= 0,
			"metadata HTML or separator escapes differ from native JSON output");
		require(output.stdout.indexOf('"escaped": "\\u003C"') >= 0, "output normalized a pre-existing escaped token");
	}

	static function checkOutput(envelope:Bool):Void {
		final valid = scan("valid", '{"keep":1}');
		final invalid = scan("invalid", "{");
		require(invalid.metadata.wireValue() == "{", "malformed stored bytes changed");
		final first = row(valid);
		final second = row(invalid);
		final metadata = PredicateComparison(MetadataTest("missing", "x"));
		require(!QueryPredicate.matches(metadata, second), "malformed metadata predicate must not match");
		final selection = PredicateOr(metadata, PredicateComparison(StatusTest(Equal, "open")));
		require(QueryPredicate.matches(selection, first)
			&& QueryPredicate.matches(selection, second), "independent OR arm must select both rows");
		final output = new CapturedOutput(envelope);
		final parser = new Parser(new FixedEnvironment(), new UnsetJsonSetting());
		final application = new Application(parser, output, new SystemActor(), new GoGitHistory(), new GoWorkspace(), new GoReadonlyStore(), new GoProfiler(),
			new UnusedWatch());
		final invocation = switch parser.parse(["query", "metadata.missing=x OR status=open", "--json"]) {
			case Parsed(value): value;
			case _: throw "fixture query invocation did not parse";
		};
		final successOutput = new CapturedOutput(envelope);
		final successApplication = new Application(parser, successOutput, new SystemActor(), new GoGitHistory(), new GoWorkspace(), new GoReadonlyStore(),
			new GoProfiler(), new UnusedWatch());
		require(successApplication.renderQuery(invocation, [first], false) == 0, "valid metadata must render successfully");
		require(successOutput.stdout.indexOf('"keep": 1') >= 0, "valid metadata never reached real stdout");
		require(envelope ? successOutput.stderr == "" : successOutput.stderr.indexOf("NOTE: bd --json output format will change in v2.0.") == 0,
			"successful JSON notice control differs");
		final status = application.renderQuery(invocation, [first, second], false);
		require(status != 0, "selected malformed metadata must fail JSON output");
		require(output.stdout == "", "encoding failure wrote partial data or an error envelope");
		require(output.stderr == "Error: encoding JSON: json: error calling MarshalJSON for type json.RawMessage: unexpected end of JSON input\n",
			"encoding failure changed the pinned query diagnostic");
		require(output.stderr.indexOf("NOTE:") < 0 && output.stderr.indexOf("Hint:") < 0, "encoding failure emitted a success hint");
	}

	static function scan(id:String, raw:Null<String>):SqlIssueFields {
		final opened = Mocks.create();
		if (opened.error != null)
			throw opened.error.text();
		final mock = opened.mock;
		mock.expectBegin();
		final values:Array<Null<String>> = [for (_ in 0...52) null];
		for (index in [0, 2, 3, 4, 5, 6, 7, 9])
			values[index] = "";
		values[0] = id;
		values[2] = "metadata fixture";
		values[7] = "open";
		for (index in [8, 20])
			values[index] = "0";
		values[12] = "2026-01-01T00:00:00Z";
		values[15] = values[12];
		values[46] = raw;
		values[36] = "[]";
		final rows = Mocks.rows(go.NativeStringSlice.fromArray([for (i in 0...52) 'column_$i']));
		rows.addRow(...SqlTestValues.fromStrings(values));
		mock.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(rows).closed();
		mock.expectRollback();
		mock.expectClose();
		final context = ContextPkg.background();
		final tx = opened.database.beginTx(context, new TxOptions());
		if (tx.value2 != null)
			throw tx.value2.toString();
		final result = readSqlIssueFields(context, tx.value1, SQL_READ_ISSUE, id);
		final rollback = tx.value1.rollback();
		final close = opened.database.close();
		final verify = mock.verify();
		require(rollback == null && close == null && verify == null, "mock transaction cleanup failed");
		return switch result {
			case Success(fields): if (fields == null) throw "mock issue disappeared"; else fields;
			case Failure(message): throw 'stored metadata must survive SQL scan ($id): $message';
		};
	}

	static function row(fields:SqlIssueFields):IssueQueryRow {
		final record:IssueRecord = fields;
		final instant:beadshx.store.QueryInstant = {
			canonical: "2026-01-01T00:00:00Z",
			epochSeconds: "1767225600",
			nanosecond: 0,
			year: 2026,
			month: 1,
			day: 1
		};
		return {
			item: {
				id: record.id,
				title: record.title,
				description: record.description,
				design: record.design,
				acceptanceCriteria: record.acceptanceCriteria,
				notes: record.notes,
				specId: record.specId,
				status: record.status,
				priority: record.priority,
				issueType: record.issueType,
				assignee: record.assignee,
				owner: record.owner,
				estimatedMinutes: record.estimatedMinutes,
				createdAt: record.createdAt,
				createdBy: record.createdBy,
				updatedAt: record.updatedAt,
				startedAt: record.startedAt,
				closedAt: record.closedAt,
				closeReason: record.closeReason,
				closedBySession: record.closedBySession,
				dueAt: record.dueAt,
				deferUntil: record.deferUntil,
				externalRef: record.externalRef,
				sourceSystem: record.sourceSystem,
				metadata: record.metadata,
				wispType: record.wispType,
				moleculeType: record.moleculeType,
				longFields: {
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
				},
				sender: fields.sender,
				labels: [],
				dependencies: [],
				dependencyCount: 0,
				dependentCount: 0,
				commentCount: 0,
				parent: "",
				blockedBy: [],
				blocks: [],
				blockingParent: ""
			},
			pinned: false,
			ephemeral: false,
			template: false,
			created: instant,
			updated: instant,
			started: InstantAbsent,
			closed: InstantAbsent
		};
	}

	static function require(ok:Bool, message:String):Void {
		if (!ok)
			throw message;
	}
}
