import SqlTestValues.DriverValue;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.time.Time;
import beadshx.store.IssueComment;
import beadshx.store.JsonInteger;
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
	@:go.name("AddRow") public function addCount(id:DriverValue, count:Int):MockRows;
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

/** Direct-store SQL count contract plus the pinned detail assembler's policy. */
@:goNative
class Main {
	static function main():Void {
		for (name in [
			"include",
			"omit",
			"wisp_include",
			"wisp_omit",
			"zero_include",
			"zero_omit",
			"missing_count_include",
			"missing_count_omit",
			"count_query_include",
			"count_query_omit",
			"count_scan_include",
			"count_rows_include",
			"count_eof_close_include",
			"count_deferred_close_include",
			"null_count_include",
			"extra_row_omit",
			"negative_count_omit",
			"overflow_count_include",
			"max_count_omit",
			"min_count_omit",
			"empty_id_include",
			"empty_id_omit",
			"literal_id_include",
			"body_query_error_after_count",
			"body_scan_error_after_count"
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
		final id = StringTools.startsWith(name, "empty_id_") ? "" : name == "literal_id_include" ? " \t'-- " : "bd-comments";
		final include = name != "omit" && !StringTools.endsWith(name, "_omit");
		final expectedCount = connection.mock.expectQuery(Patterns.quote("SELECT count(*) FROM comments WHERE issue_id = ?")).withId(id);
		if (StringTools.startsWith(name, "count_query_")) {
			expectedCount.fail(NativeErrors.create("count denied"));
		} else {
			final rows = Mocks.rows(go.NativeStringSlice.fromArray(["count"]));
			if (!StringTools.startsWith(name, "missing_count_")) {
				final count:Null<String> = switch name {
					case "zero_include", "zero_omit": "0";
					case "count_scan_include": "invalid";
					case "null_count_include": null;
					case "negative_count_omit": "-1";
					case "overflow_count_include": "9223372036854775808";
					case "max_count_omit": "9223372036854775807";
					case "min_count_omit": "-9223372036854775808";
					case _: "2";
				};
				rows.addRow(...SqlTestValues.fromStrings([count]));
				if (name == "extra_row_omit")
					rows.addRow(...SqlTestValues.fromStrings(["7"]));
				if (name == "count_rows_include")
					rows.rowError(0, NativeErrors.create("count iteration failed"));
			}
			if (name == "count_eof_close_include" || name == "count_deferred_close_include")
				rows.closeError(NativeErrors.create("count close failed"));
			expectedCount.closed();
			if (name == "count_deferred_close_include")
				expectedCount.rows(rows, Mocks.rows(go.NativeStringSlice.fromArray(["unused"])));
			else
				expectedCount.rows(rows);
		}
		if (include) {
			final routing = Mocks.rows(go.NativeStringSlice.fromArray(["exists"]));
			if (StringTools.startsWith(name, "wisp_"))
				routing.addRow(...SqlTestValues.fromStrings(["1"]));
			connection.mock.expectQuery(Patterns.quote("SELECT 1 FROM wisps WHERE id = ? LIMIT 1"))
				.withId(id)
				.closed()
				.rows(routing);
			final table = StringTools.startsWith(name, "wisp_") ? "wisp_comments" : "comments";
			final query = 'SELECT id, issue_id, author, text, created_at FROM $table WHERE issue_id = ? ORDER BY created_at ASC, id ASC';
			final expected = connection.mock.expectQuery(Patterns.quote(query)).withId(id);
			if (name == "body_query_error_after_count")
				expected.fail(NativeErrors.create("body denied"));
			else {
				final rows = Mocks.rows(go.NativeStringSlice.fromArray(["id", "issue_id", "author", "text", "created_at"]));
				final parsed = TimeFunctions.parse("2006-01-02T15:04:05.999999999Z07:00", "2026-03-04T05:06:07.123456789+01:30");
				require(parsed.error == null, "fixture timestamp");
				final values = SqlTestValues.fromStrings([
					"comment-02",
					id,
					name == "body_scan_error_after_count" ? null : "writer",
					"body differs from count"
				]);
				rows.addTimed(values[0], values[1], values[2], values[3], parsed.value);
				expected.closed().rows(rows);
			}
		}
		connection.mock.expectRollback();
		final result = SqlCommentReader.readSqlIssueCommentDetails(ContextPkg.background(), transaction, {id: id, includeComments: include});
		var error = "";
		var comments = new Array<IssueComment>();
		var count:JsonInteger = 0;
		var omitted = false;
		switch result {
			case Success(details):
				comments = details.comments;
				count = details.commentCount;
				omitted = details.commentsOmitted;
			case Failure(message):
				error = message;
		}
		require(transaction.rollback() == null, "rollback observer transaction");
		connection.mock.expectClose();
		final closed = connection.database.close();
		require(closed == null, 'close observer database for $name: ${closed == null ? "" : closed.toString()}');
		final verified = connection.mock.verify();
		require(verified == null, 'SQL expectations for $name: ${verified == null ? "" : verified.text()}');
		final rendered = [
			for (item in comments)
				'{"id":${Json.stringify(item.id)},"issueId":${Json.stringify(item.issueId)},"author":${Json.stringify(item.author)},"text":${Json.stringify(item.text)},"createdAt":${Json.stringify(item.createdAt)}}'
		];
		Sys.println('{"name":${Json.stringify(name)},"comments":[${rendered.join(",")}],"count":${count.wireValue()},"omitted":$omitted,"error":${Json.stringify(error)}}');
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition) {
			Sys.println("comment detail observer assertion: " + message);
			throw message;
		}
	}
}
