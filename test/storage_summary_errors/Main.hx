import SqlTestValues.DriverValue;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.store.EmbeddedIssueSummaryReader.EmbeddedIssueSummaryResult;

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock")
extern class SummaryMocks {
	@:go.name("New") @:go.tupleReturn public static function create():SummaryMockConnection;
	@:go.name("NewRows") public static function rows(columns:go.NativeStringSlice):SummaryMockRows;
}

class SummaryMockConnection {
	public final database:DB;
	public final mock:SummaryMock;
	public final error:go.NativeError;

	public function new(database:DB, mock:SummaryMock, error:go.NativeError) {
		this.database = database;
		this.mock = mock;
		this.error = error;
	}
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Sqlmock")
extern interface SummaryMock {
	@:go.name("ExpectBegin") public function expectBegin():SummaryExpectedBegin;
	@:go.name("ExpectRollback") public function expectRollback():SummaryExpectedRollback;
	@:go.name("ExpectClose") public function expectClose():SummaryExpectedClose;
	@:go.name("ExpectQuery") public function expectQuery(query:String):SummaryExpectedQuery;
	@:go.name("ExpectationsWereMet") public function verify():go.NativeError;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedBegin") extern class SummaryExpectedBegin {}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedRollback") extern class SummaryExpectedRollback {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):SummaryExpectedRollback;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedClose") extern class SummaryExpectedClose {}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedQuery")
extern class SummaryExpectedQuery {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):SummaryExpectedQuery;
	@:go.name("WillReturnRows") public function rows(rows:haxe.Rest<SummaryMockRows>):SummaryExpectedQuery;
	@:go.name("RowsWillBeClosed") public function closed():SummaryExpectedQuery;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Rows")
extern class SummaryMockRows {
	@:go.name("AddRow") public function addRow(values:haxe.Rest<DriverValue>):SummaryMockRows;
	@:go.name("RowError") public function rowError(row:Int, error:go.NativeError):SummaryMockRows;
	@:go.name("CloseError") public function closeError(error:go.NativeError):SummaryMockRows;
}

@:go.import("errors") extern class SummaryErrors {
	@:go.name("New") public static function create(message:String):go.NativeError;
}

@:go.import("github.com/go-sql-driver/mysql") @:go.name("MySQLError") @:go.struct
extern class SummaryMySqlError {
	public function new();
	@:go.name("Number") public var number:Int;
	@:go.name("Message") public var message:String;
}

@:go.import("fmt") extern class SummaryFormat {
	@:go.name("Errorf") public static function wrapMysql(format:String, error:SummaryMySqlError):go.NativeError;
}

private enum LookupExpected {
	ExpectFound(priority:String);
	ExpectMissing;
	ExpectFailure(message:String);
}

/** Native sqlmock observer for the summary reader's pinned 52-column scan. */
@:goNative
@:access(beadshx.store.EmbeddedIssueSummaryReader)
class Main {
	static final COLUMNS = go.NativeStringSlice.fromArray([
		for (index in 0...52)
			switch index {
				case 0:
					"id";
				case 2:
					"title";
				case 7:
					"status";
				case 8:
					"priority";
				case 9:
					"issue_type";
				case _:
					'column_$index';
			}
	]);

	static function fullValues(values:Array<Null<String>>):Array<Null<String>> {
		final full:Array<Null<String>> = [for (_ in 0...52) null];
		for (index in [3, 4, 5, 6])
			full[index] = "";
		full[20] = "0";
		full[0] = values[0];
		full[2] = values[1];
		full[7] = values[2];
		full[8] = values[3];
		full[9] = values[4];
		return full;
	}

	static function row(values:Array<Null<String>>):SummaryMockRows
		return SummaryMocks.rows(COLUMNS).addRow(...SqlTestValues.fromStrings(fullValues(values)));

	static function rowWithOriginal(value:String):SummaryMockRows {
		final values = fullValues(["issue-1", "title", "open", "7", "task"]);
		values[23] = value;
		return SummaryMocks.rows(COLUMNS).addRow(...SqlTestValues.fromStrings(values));
	}

	static function missingTable():go.NativeError {
		final error = new SummaryMySqlError();
		error.number = 1146;
		error.message = "opaque driver detail";
		return SummaryFormat.wrapMysql("%w", error);
	}

	static function misleadingTable():go.NativeError {
		final error = new SummaryMySqlError();
		error.number = 999;
		error.message = "Error 1146 appears in text only";
		return SummaryFormat.wrapMysql("%w", error);
	}

	static function checkLookup(name:String, setup:SummaryMock->Void, expected:LookupExpected):Void {
		final opened = SummaryMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		setup(opened.mock);
		opened.mock.expectRollback();
		opened.mock.expectClose();
		final context = ContextPkg.background();
		final begun = opened.database.beginTx(context, new TxOptions());
		if (begun.value2 != null)
			throw begun.value2.toString();
		final result = beadshx.store.EmbeddedIssueSummaryReader.readSummaryInTx(context, begun.value1, "issue-1");
		final rollbackError = begun.value1.rollback();
		if (rollbackError != null)
			throw rollbackError.toString();
		final closeError = opened.database.close();
		if (closeError != null)
			throw closeError.toString();
		final verification = opened.mock.verify();
		if (verification != null)
			throw '$name: ${verification.text()}';
		switch expected {
			case ExpectFound(priority):
				switch result {
					case EmbeddedIssueSummaryFound(summary):
						if (summary.priority.wireValue() != priority) throw '$name: expected priority $priority, received ${summary.priority.wireValue()}';
					case EmbeddedIssueSummaryFailure(message): throw '$name: expected issue, received $message';
					case EmbeddedIssueSummaryMissing: throw '$name: expected issue, received missing';
				}
			case ExpectMissing:
				switch result {
					case EmbeddedIssueSummaryMissing:
					case EmbeddedIssueSummaryFailure(message): throw '$name: expected missing, received $message';
					case EmbeddedIssueSummaryFound(_): throw '$name: expected missing, received issue';
				}
			case ExpectFailure(message):
				switch result {
					case EmbeddedIssueSummaryFailure(actual):
						if (actual != message) throw '$name: expected $message, received $actual';
					case EmbeddedIssueSummaryMissing: throw '$name: expected $message, received missing';
					case EmbeddedIssueSummaryFound(_): throw '$name: expected $message, received issue';
				}
		}
	}

	static function check(name:String, values:Array<Null<String>>, expectedError:Null<String>, expectedPriority:Null<String>, closeError:Bool = false):Void {
		final opened = SummaryMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		final first = row(values);
		if (closeError)
			first.closeError(SummaryErrors.create("close failed"));
		final expectation = opened.mock.expectQuery("SELECT");
		if (closeError)
			expectation.rows(first, SummaryMocks.rows(go.NativeStringSlice.fromArray(["unused"])).addRow(...SqlTestValues.fromStrings(["unused"]))).closed();
		else
			expectation.rows(first).closed();
		opened.mock.expectRollback();
		opened.mock.expectClose();
		final context = ContextPkg.background();
		final begun = opened.database.beginTx(context, new TxOptions());
		if (begun.value2 != null)
			throw begun.value2.toString();
		final queried = begun.value1.queryContext(context, "SELECT full issue row");
		if (queried.value2 != null)
			throw queried.value2.toString();
		final result = beadshx.store.EmbeddedIssueSummaryReader.scanSummaryRows(queried.value1, "row-contract");
		final rollbackError = begun.value1.rollback();
		if (rollbackError != null)
			throw rollbackError.toString();
		final closeDatabaseError = opened.database.close();
		if (closeDatabaseError != null)
			throw closeDatabaseError.toString();
		final verifyError = opened.mock.verify();
		if (verifyError != null)
			throw verifyError.text();
		switch result {
			case EmbeddedIssueSummaryFailure(message):
				if (expectedError == null || message != expectedError)
					throw '$name: expected ${expectedError}, received ${message}';
			case EmbeddedIssueSummaryFound(summary):
				if (expectedError != null || expectedPriority == null || summary.priority.wireValue() != expectedPriority)
					throw '$name: unexpected summary priority ${summary.priority.wireValue()}';
			case EmbeddedIssueSummaryMissing:
				throw '$name: unexpected missing row';
		}
	}

	static function checkNoRowClose():Void {
		final opened = SummaryMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		final first = SummaryMocks.rows(COLUMNS).closeError(SummaryErrors.create("close failed"));
		final second = SummaryMocks.rows(go.NativeStringSlice.fromArray(["unused"])).addRow(...SqlTestValues.fromStrings(["unused"]));
		opened.mock.expectQuery("SELECT").rows(first, second).closed();
		opened.mock.expectRollback();
		opened.mock.expectClose();
		final context = ContextPkg.background();
		final begun = opened.database.beginTx(context, new TxOptions());
		if (begun.value2 != null)
			throw begun.value2.toString();
		final queried = begun.value1.queryContext(context, "SELECT full issue row");
		if (queried.value2 != null)
			throw queried.value2.toString();
		final result = beadshx.store.EmbeddedIssueSummaryReader.scanSummaryRows(queried.value1, "row-contract");
		final rollbackError = begun.value1.rollback();
		if (rollbackError != null)
			throw rollbackError.toString();
		final closeDatabaseError = opened.database.close();
		if (closeDatabaseError != null)
			throw closeDatabaseError.toString();
		final verifyError = opened.mock.verify();
		if (verifyError != null)
			throw verifyError.text();
		switch result {
			case EmbeddedIssueSummaryMissing:
			case EmbeddedIssueSummaryFailure(message):
				throw 'no row with close failure: expected missing, received $message';
			case EmbeddedIssueSummaryFound(_):
				throw 'no row with close failure: unexpected found row';
		}
	}

	static function checkTransactionCleanup(readFailed:Bool, rollbackFailed:Bool):Void {
		final opened = SummaryMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		final rollback = opened.mock.expectRollback();
		if (rollbackFailed)
			rollback.fail(SummaryErrors.create("rollback failed"));
		opened.mock.expectClose();
		final begun = opened.database.beginTx(ContextPkg.background(), new TxOptions());
		if (begun.value2 != null)
			throw begun.value2.toString();
		final input = readFailed ? EmbeddedIssueSummaryFailure("summary read failed") : EmbeddedIssueSummaryMissing;
		final result = beadshx.store.EmbeddedIssueSummaryReader.finishSummaryTransaction(input, begun.value1);
		final closed = opened.database.close();
		if (closed != null)
			throw closed.toString();
		final verification = opened.mock.verify();
		if (verification != null)
			throw verification.text();
		final expected = readFailed ? (rollbackFailed ? "summary read failed\nrollback failed" : "summary read failed") : (rollbackFailed ? "rollback failed" : null);
		switch result {
			case EmbeddedIssueSummaryFailure(actual):
				if (actual != expected)
					throw 'cleanup read=$readFailed rollback=$rollbackFailed: expected $expected, received $actual';
			case EmbeddedIssueSummaryMissing:
				if (expected != null)
					throw 'cleanup: expected failure $expected';
			case EmbeddedIssueSummaryFound(_):
				throw "cleanup: unexpected issue";
		}
	}

	static function main():Void {
		for (readFailed in [false, true])
			for (rollbackFailed in [false, true])
				checkTransactionCleanup(readFailed, rollbackFailed);
		checkFullIssueProjection();
		check("wide priority", ["id", "title", "open", "9007199254740993", "task"], null, "9007199254740993");
		check("null id", [null, "title", "open", "1", "task"],
			'get issue: sql: Scan error on column index 0, name "id": converting NULL to string is unsupported', null);
		check("null title", ["id", null, "open", "1", "task"],
			'get issue: sql: Scan error on column index 2, name "title": converting NULL to string is unsupported', null);
		check("null status", ["id", "title", null, "1", "task"],
			'get issue: sql: Scan error on column index 7, name "status": converting NULL to string is unsupported', null);
		check("null priority", ["id", "title", "open", null, "task"],
			'get issue: sql: Scan error on column index 8, name "priority": converting NULL to int is unsupported', null);
		check("null type", ["id", "title", "open", "1", null],
			'get issue: sql: Scan error on column index 9, name "issue_type": converting NULL to string is unsupported', null);
		check("scan beats close", ["id", "title", "open", "bad", "task"],
			'get issue: sql: Scan error on column index 8, name "priority": converting driver.Value type string ("bad") to a int: invalid syntax', null, true);
		check("successful scan returns close error", ["id", "title", "open", "1", "task"], 'get issue: close failed', null, true);
		checkNoRowClose();
		checkRoutes();
		Sys.println("Summary SQL scan contracts: PASS");
	}

	static function checkRoutes():Void {
		final issue = ["issue-1", "title", "open", "7", "task"];
		final wisp = ["issue-1", "wisp", "open", "8", "task"];
		final emptyLabels = () -> SummaryMocks.rows(go.NativeStringSlice.fromArray(["label"]));

		checkLookup("issue hit avoids wisp", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue)).closed();
			mock.expectQuery("FROM labels").rows(emptyLabels()).closed();
		}, ExpectFound("7"));
		checkLookup("wisp fallback", mock -> {
			mock.expectQuery("FROM issues").rows(SummaryMocks.rows(COLUMNS)).closed();
			mock.expectQuery("FROM wisps").rows(row(wisp)).closed();
			mock.expectQuery("FROM wisp_labels").rows(emptyLabels()).closed();
		}, ExpectFound("8"));
		checkLookup("both absent", mock -> {
			mock.expectQuery("FROM issues").rows(SummaryMocks.rows(COLUMNS)).closed();
			mock.expectQuery("FROM wisps").rows(SummaryMocks.rows(COLUMNS)).closed();
		}, ExpectMissing);
		checkLookup("non-summary field scan fails before wisp", mock -> {
			mock.expectQuery("FROM issues").rows(rowWithOriginal("bad")).closed();
		},
			ExpectFailure('get issue: sql: Scan error on column index 23, name "column_23": converting driver.Value type string ("bad") to a int64: invalid syntax'));

		final missing = missingTable();
		checkLookup("typed missing issue table", mock -> {
			mock.expectQuery("FROM issues").fail(missing);
			mock.expectQuery("FROM wisps").rows(row(wisp)).closed();
			mock.expectQuery("FROM wisp_labels").rows(emptyLabels()).closed();
		}, ExpectFound("8"));
		checkLookup("typed missing table from deferred row error", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue).rowError(0, missing)).closed();
			mock.expectQuery("FROM wisps").rows(row(wisp)).closed();
			mock.expectQuery("FROM wisp_labels").rows(emptyLabels()).closed();
		}, ExpectFound("8"));
		final misleading = misleadingTable();
		checkLookup("text 1146 is not table absence", mock -> {
			mock.expectQuery("FROM issues").fail(misleading);
		}, ExpectFailure('get issue: ${misleading.text()}'));

		checkLookup("typed missing table from successful scan close", mock -> {
			final first = row(issue).closeError(missing);
			mock.expectQuery("FROM issues").rows(first, row(issue)).closed();
			mock.expectQuery("FROM wisps").rows(row(wisp)).closed();
			mock.expectQuery("FROM wisp_labels").rows(emptyLabels()).closed();
		}, ExpectFound("8"));
		checkLookup("no row ignores deferred close error", mock -> {
			final first = SummaryMocks.rows(COLUMNS).closeError(SummaryErrors.create("ignored close"));
			mock.expectQuery("FROM issues").rows(first, row(issue)).closed();
			mock.expectQuery("FROM wisps").rows(row(wisp)).closed();
			mock.expectQuery("FROM wisp_labels").rows(emptyLabels()).closed();
		}, ExpectFound("8"));

		checkLookup("label query failure blocks wisp", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue)).closed();
			mock.expectQuery("FROM labels").fail(SummaryErrors.create("labels failed"));
		}, ExpectFailure("get issue labels: get labels: labels failed"));
		checkLookup("required label scan", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue)).closed();
			mock.expectQuery("FROM labels").rows(emptyLabels().addRow(...SqlTestValues.fromStrings([null]))).closed();
		},
			ExpectFailure('get issue labels: get labels: scan: sql: Scan error on column index 0, name "label": converting NULL to string is unsupported'));
		checkLookup("label rows error remains raw", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue)).closed();
			mock.expectQuery("FROM labels")
				.rows(emptyLabels().addRow(...SqlTestValues.fromStrings(["x"])).rowError(0, SummaryErrors.create("label rows failed")))
				.closed();
		}, ExpectFailure("get issue labels: label rows failed"));
		checkLookup("deferred label close is ignored", mock -> {
			mock.expectQuery("FROM issues").rows(row(issue)).closed();
			final first = emptyLabels().closeError(SummaryErrors.create("ignored label close"));
			mock.expectQuery("FROM labels").rows(first, emptyLabels().addRow(...SqlTestValues.fromStrings(["later"]))).closed();
		}, ExpectFound("7"));
	}

	/** A valid pinned issue row has 52 destinations, including fields summary hides. */
	static function checkFullIssueProjection():Void {
		final opened = SummaryMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		final values:Array<Null<String>> = [for (_ in 0...52) null];
		for (index in [0, 2, 3, 4, 5, 6, 7, 9])
			values[index] = "";
		values[0] = "issue-1";
		values[2] = "title";
		values[7] = "open";
		values[8] = "7";
		values[9] = "task";
		values[20] = "0";
		final columns = go.NativeStringSlice.fromArray([for (index in 0...52) 'column_$index']);
		opened.mock.expectQuery("SELECT").rows(SummaryMocks.rows(columns).addRow(...SqlTestValues.fromStrings(values))).closed();
		opened.mock.expectRollback();
		opened.mock.expectClose();
		final context = ContextPkg.background();
		final begun = opened.database.beginTx(context, new TxOptions());
		if (begun.value2 != null)
			throw begun.value2.toString();
		final queried = begun.value1.queryContext(context, "SELECT full issue row");
		if (queried.value2 != null)
			throw queried.value2.toString();
		final result = beadshx.store.EmbeddedIssueSummaryReader.scanSummaryRows(queried.value1, "issue-1");
		begun.value1.rollback();
		opened.database.close();
		final verifyError = opened.mock.verify();
		if (verifyError != null)
			throw verifyError.text();
		switch result {
			case EmbeddedIssueSummaryFound(summary):
				if (summary.priority.wireValue() != "7")
					throw 'full issue row: priority ${summary.priority.wireValue()}';
			case EmbeddedIssueSummaryFailure(message):
				throw 'full issue row: $message';
			case EmbeddedIssueSummaryMissing:
				throw "full issue row: missing";
		}
	}
}
