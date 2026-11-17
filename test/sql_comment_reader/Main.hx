import SqlTestValues.DriverValue;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.time.Time;
import beadshx.store.IssueComment;
import beadshx.store.SqlCommentReader;
import haxe.Json;

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock")
private extern class Mocks {
	@:go.name("New") @:go.tupleReturn public static function create():MockConnection;
	@:go.name("NewRows") public static function rows(columns:go.NativeStringSlice):MockRows;
}

private class MockConnection {
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
private extern interface Mock {
	@:go.name("ExpectBegin") public function expectBegin():ExpectedBegin;
	@:go.name("ExpectRollback") public function expectRollback():ExpectedRollback;
	@:go.name("ExpectClose") public function expectClose():ExpectedClose;
	@:go.name("ExpectQuery") public function expectQuery(query:String):ExpectedQuery;
	@:go.name("ExpectationsWereMet") public function verify():go.NativeError;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedBegin") private extern class ExpectedBegin {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedRollback") private extern class ExpectedRollback {}
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedClose") private extern class ExpectedClose {}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedQuery")
private extern class ExpectedQuery {
	@:go.name("WithArgs") public function withId(id:String):ExpectedQuery;
	@:go.name("WillReturnError") public function fail(error:go.NativeError):ExpectedQuery;
	@:go.name("WillReturnRows") public function rows(rows:haxe.Rest<MockRows>):ExpectedQuery;
	@:go.name("RowsWillBeClosed") public function closed():ExpectedQuery;
}

/** Only the timestamp argument is a Go value; text cells retain actual SQL NULL. */
@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Rows")
private extern class MockRows {
	@:go.name("AddRow") @:go.valueArgs("4") public function addTimed(id:DriverValue, issueId:DriverValue, author:DriverValue, text:DriverValue,
		createdAt:Time):MockRows;
	@:go.name("AddRow") public function addRow(values:haxe.Rest<DriverValue>):MockRows;
	@:go.name("RowError") public function rowError(index:Int, error:go.NativeError):MockRows;
	@:go.name("CloseError") public function closeError(error:go.NativeError):MockRows;
}

@:go.import("errors") private extern class NativeErrors {
	@:go.name("New") public static function create(message:String):go.NativeError;
}

@:go.import("regexp") private extern class Patterns {
	@:go.name("QuoteMeta") public static function quote(value:String):String;
}

@:go.import("time") private extern class TimeFunctions {
	@:go.name("Parse") @:go.tupleReturn @:go.tupleValueResults("0") public static function parse(layout:String, value:String):ParsedTime;
}

private class ParsedTime {
	public final value:Time;
	public final error:go.NativeError;

	public function new(value:Time, error:go.NativeError) {
		this.value = value;
		this.error = error;
	}
}

/** Native SQL observer compared with the independently run pinned Go callpath. */
@:goNative
class Main {
	static function main():Void {
		for (name in [
			"durable",
			"wisp",
			"empty",
			"empty_id",
			"literal_id",
			"foreign_row",
			"query_error",
			"null_id",
			"null_issue",
			"null_author",
			"null_text",
			"null_time",
			"text_time",
			"row_error",
			"eof_close",
			"deferred_close",
			"scan_close",
			"routing_query",
			"routing_scan",
			"routing_null",
			"routing_close"
		])
			observe(name);
	}

	static function observe(name:String):Void {
		final connection = Mocks.create();
		require(connection.error == null, "create SQL observer");
		connection.mock.expectBegin();
		final started = connection.database.beginTx(ContextPkg.background(), new TxOptions());
		require(started.value2 == null, "begin observer transaction");
		final transaction = started.value1;
		final id = name == "empty_id" ? "" : name == "literal_id" ? " \t'-- " : "bd-comments";
		final table = name == "wisp" ? "wisp_comments" : "comments";
		final route = connection.mock.expectQuery(Patterns.quote("SELECT 1 FROM wisps WHERE id = ? LIMIT 1")).withId(id);
		if (name == "routing_query") {
			route.fail(NativeErrors.create("routing denied"));
		} else {
			final rows = Mocks.rows(go.NativeStringSlice.fromArray(["exists"]));
			if (name == "wisp" || StringTools.startsWith(name, "routing_"))
				rows.addRow(...SqlTestValues.fromStrings([name == "routing_scan" ? "invalid" : name == "routing_null" ? null : "1"]));
			if (name == "routing_close")
				rows.closeError(NativeErrors.create("routing close failed"));
			route.closed().rows(rows);
		}
		{
			final query = 'SELECT id, issue_id, author, text, created_at FROM $table WHERE issue_id = ? ORDER BY created_at ASC, id ASC';
			final expected = connection.mock.expectQuery(Patterns.quote(query)).withId(id);
			if (name == "query_error") {
				expected.fail(NativeErrors.create("query denied"));
			} else {
				expected.closed();
				final rows = Mocks.rows(go.NativeStringSlice.fromArray(["id", "issue_id", "author", "text", "created_at"]));
				final parsed = TimeFunctions.parse("2006-01-02T15:04:05.999999999Z07:00", "2026-03-04T05:06:07.123456789+01:30");
				require(parsed.error == null, "fixture timestamp");
				final text:Array<Null<String>> = ["comment-02", id, "writer", "first\nline"];
				switch name {
					case "null_id", "scan_close":
						text[0] = null;
					case "null_issue":
						text[1] = null;
					case "null_author":
						text[2] = null;
					case "null_text":
						text[3] = null;
					case _:
				}
				if (name == "null_time" || name == "text_time") {
					text.push(name == "null_time" ? null : "2026-03-04");
					rows.addRow(...SqlTestValues.fromStrings(text));
				} else if (name != "empty") {
					addTimed(rows, text, parsed.value);
				}
				if (name == "durable" || name == "wisp")
					addTimed(rows, ["comment-10", id, "", 'second "quoted" λ'], parsed.value);
				if (name == "foreign_row")
					addTimed(rows, ["foreign", "another-issue", "other", "ignored"], parsed.value);
				if (name == "row_error")
					rows.rowError(0, NativeErrors.create("iteration failed"));
				if (name == "eof_close" || name == "deferred_close" || name == "scan_close")
					rows.closeError(NativeErrors.create("close failed"));
				if (name == "deferred_close")
					expected.rows(rows, Mocks.rows(go.NativeStringSlice.fromArray(["unused"])));
				else
					expected.rows(rows);
			}
		}
		connection.mock.expectRollback();
		final result = SqlCommentReader.readSqlIssueComments(ContextPkg.background(), transaction, {id: id});
		var error = "";
		var comments = new Array<IssueComment>();
		switch result {
			case Success(values):
				comments = values;
			case Failure(message):
				error = message;
		}
		require(transaction.rollback() == null, "rollback observer transaction");
		connection.mock.expectClose();
		final closeError = connection.database.close();
		require(closeError == null, 'close observer database for $name: ${closeError == null ? "" : closeError.toString()}');
		final verificationError = connection.mock.verify();
		require(verificationError == null, 'SQL expectations for $name: ${verificationError == null ? "" : verificationError.text()}');
		final rendered = [
			for (item in comments)
				'{"id":${Json.stringify(item.id)},"issueId":${Json.stringify(item.issueId)},"author":${Json.stringify(item.author)},"text":${Json.stringify(item.text)},"createdAt":${Json.stringify(item.createdAt)}}'
		];
		Sys.println('{"name":${Json.stringify(name)},"comments":[${rendered.join(",")}],"error":${Json.stringify(error)}}');
	}

	static function addTimed(rows:MockRows, text:Array<Null<String>>, time:Time):Void {
		final values = SqlTestValues.fromStrings(text);
		rows.addTimed(values[0], values[1], values[2], values[3], time);
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition) {
			Sys.println("comment observer assertion: " + message);
			throw message;
		}
	}
}
