import SqlTestValues.DriverValue;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.relation.RelationRead.prepareRelationRead;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.readSqlIssueFields;
import beadshx.store.SqlRelationReader.readSqlRelations;
import beadshx.store.JsonValue;

private typedef IssueRowCase = {
	final name:String;
	final created:String;
	final updated:String;
	final waiters:String;
	final metadata:Null<String>;
	final expectedCreated:String;
	final expectedUpdated:String;
	final expectedWaiters:Array<String>;
	final expectedMetadataPresent:Bool;
	final ?expectedMetadataBytes:String;
}

@:go.import("github.com/go-sql-driver/mysql") @:go.name("MySQLError") @:go.struct
extern class TestMySqlError {
	public function new();
	@:go.name("Number") public var number:Int;
	@:go.name("Message") public var message:String;
}

@:go.import("fmt") extern class TestFormat {
	@:go.name("Errorf") public static function wrapMysql(format:String, error:TestMySqlError):go.NativeError;
}

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

@:go.import("errors") extern class NativeErrors {
	@:go.name("New") public static function create(message:String):go.NativeError;
}

private enum ScalarReadErrorScenario {
	ScalarScanFailure;
	ScalarCloseFailure;
	ScalarRowsFailure;
	ScalarNoRowCloseFailure;
}

private enum ErrorScenario {
	MissingIssueTable;
	MissingBothTables;
	DeniedIssueTable;
	MissingDependencyTable;
	MissingWispsWithDanglingNeighbor;
	EmptyWispsWithDanglingNeighbor;
	AnchorDeferredMissingIssue;
	AnchorCloseMissingIssue;
	AnchorDeferredMissingWisp;
	AnchorCloseMissingWisp;
	AnchorDeferredDenied;
	AnchorCloseDenied;
	AnchorInvalidBoolean;
	AnchorNullBoolean;
	AnchorInvalidBooleanWithClose;
	AnchorFalseThenWispTrue;
	AnchorFalseThenFalse;
	AnchorNoRow;
	AnchorNoRowWithClose;
	AnchorOtherErrorMentionsMissingCode;
	IncomingEdgeNullId;
	IncomingEdgeNullType;
	OutgoingEdgeNullId;
	WispIdNull;
	LabelNullIssueId;
	LabelNullValue;
	WispProbeDeferredMissing;
	WispProbeCloseMissing;
	WispProbeNoRowCloseMissing;
	WispProbeCloseError;
	WispProbeDeferredDenied;
	HydrationQueryDenied;
	HydrationRowsDenied;
	LabelQueryDenied;
	LabelRowsDenied;
	EdgeCloseErrorWithPendingResultSet;
	HydrationCloseErrorWithPendingResultSet;
	LabelCloseErrorWithPendingResultSet;
	HydrationScanFailure;
	LabelScanFailure;
}

/** Ordered SQL observer: no files, sockets, or real database are used. */
@:goNative
class Main {
	static function main():Void {
		for (scenario in [
			MissingIssueTable,
			MissingBothTables,
			DeniedIssueTable,
			MissingDependencyTable,
			MissingWispsWithDanglingNeighbor,
			EmptyWispsWithDanglingNeighbor,
			AnchorDeferredMissingIssue,
			AnchorCloseMissingIssue,
			AnchorDeferredMissingWisp,
			AnchorCloseMissingWisp,
			AnchorDeferredDenied,
			AnchorCloseDenied,
			AnchorInvalidBoolean,
			AnchorNullBoolean,
			AnchorInvalidBooleanWithClose,
			AnchorFalseThenWispTrue,
			AnchorFalseThenFalse,
			AnchorNoRow,
			AnchorNoRowWithClose,
			AnchorOtherErrorMentionsMissingCode,
			IncomingEdgeNullId,
			IncomingEdgeNullType,
			OutgoingEdgeNullId,
			WispIdNull,
			LabelNullIssueId,
			LabelNullValue,
			WispProbeDeferredMissing,
			WispProbeCloseMissing,
			WispProbeNoRowCloseMissing,
			WispProbeCloseError,
			WispProbeDeferredDenied,
			HydrationQueryDenied,
			HydrationRowsDenied,
			LabelQueryDenied,
			LabelRowsDenied,
			EdgeCloseErrorWithPendingResultSet,
			HydrationCloseErrorWithPendingResultSet,
			LabelCloseErrorWithPendingResultSet,
			HydrationScanFailure,
			LabelScanFailure
		])
			checkScenario(scenario);
		for (scenario in [
			ScalarScanFailure,
			ScalarCloseFailure,
			ScalarRowsFailure,
			ScalarNoRowCloseFailure
		])
			checkScalarErrorPrecedence(scenario);
		for (testCase in issueRowCases()) {
			checkScalarIssueRow(testCase);
			checkRelationIssueRow(testCase);
		}
		switch JsonValue.parseStringArray('[null,"a"]', "strict array control") {
			case Failure(_):
			case Success(_):
				throw "default string-array parser accepted null element";
		}
		Sys.println("Haxe relation SQL error contracts: PASS");
	}

	static function checkScenario(scenario:ErrorScenario):Void {
		final connection = Mocks.create();
		if (connection.error != null)
			throw connection.error.text();
		final observer = connection.mock;
		observer.expectBegin();
		final expectedFailure = switch scenario {
			case IncomingEdgeNullId, IncomingEdgeNullType, OutgoingEdgeNullId:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				final outgoing = scenario == OutgoingEdgeNullId;
				final relationId:Null<String> = scenario == IncomingEdgeNullType ? "neighbor" : null;
				final relationType:Null<String> = scenario == IncomingEdgeNullType ? null : "blocks";
				final firstColumn = outgoing ? "depends_on_id" : "issue_id";
				final edgeQuery = outgoing ? "SELECT .* AS depends_on_id, type FROM dependencies WHERE issue_id = " : "SELECT issue_id, type FROM dependencies WHERE ";
				observer.expectQuery(edgeQuery)
					.rows(Mocks.rows(go.NativeStringSlice.fromArray([firstColumn, "type"])).addRow(...SqlTestValues.fromStrings([relationId, relationType])))
					.closed();
				final columnIndex = scenario == IncomingEdgeNullType ? 1 : 0;
				final columnName = scenario == IncomingEdgeNullType ? "type" : firstColumn;
				final role = outgoing ? "dependencies" : "dependents";
				'get $role: scan: sql: Scan error on column index $columnIndex, name "$columnName": converting NULL to string is unsupported';
			case WispIdNull, LabelNullIssueId, LabelNullValue:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				final wispProbe = Mocks.rows(go.NativeStringSlice.fromArray(["1"]));
				if (scenario == WispIdNull)
					wispProbe.fromCsv("1");
				observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(wispProbe).closed();
				if (scenario == WispIdNull) {
					observer.expectQuery("SELECT id FROM wisps WHERE id IN")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["id"])).addRow(...SqlTestValues.fromStrings([null])))
						.closed();
					"get dependents: fetch issues: get issues by IDs: build wisp set: wisp id set: scan: sql: Scan error on column index 0, name \"id\": converting NULL to string is unsupported";
				} else {
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(hydratedIssueRows()).closed();
					final labelId:Null<String> = scenario == LabelNullIssueId ? null : "neighbor";
					final labelText:Null<String> = scenario == LabelNullValue ? null : "label";
					observer.expectQuery("SELECT issue_id, label FROM labels WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label"])).addRow(...SqlTestValues.fromStrings([labelId, labelText])))
						.closed();
					final columnIndex = scenario == LabelNullIssueId ? 0 : 1;
					final columnName = scenario == LabelNullIssueId ? "issue_id" : "label";
					'get dependents: fetch issues: get issues by IDs: scan label: sql: Scan error on column index $columnIndex, name "$columnName": converting NULL to string is unsupported';
				}
			case AnchorInvalidBoolean:
				// QueryRow.Scan must decode EXISTS into *bool before any edge read.
				observer.expectQuery("SELECT").rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("invalid")).closed();
				"check issue existence in issues: sql: Scan error on column index 0, name \"exists\": sql/driver: couldn't convert \"invalid\" into type bool";
			case AnchorNullBoolean:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("NULL"))
					.closed();
				"check issue existence in issues: sql: Scan error on column index 0, name \"exists\": sql/driver: couldn't convert <nil> (<nil>) into type bool";
			case AnchorInvalidBooleanWithClose:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("invalid").closeError(NativeErrors.create("close denied")))
					.closed();
				"check issue existence in issues: sql: Scan error on column index 0, name \"exists\": sql/driver: couldn't convert \"invalid\" into type bool";
			case AnchorFalseThenWispTrue, AnchorFalseThenFalse:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("0"))
					.closed();
				observer.expectQuery("SELECT EXISTS.*FROM wisps WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv(scenario == AnchorFalseThenWispTrue ? "1" : "0"))
					.closed();
				if (scenario == AnchorFalseThenWispTrue) {
					observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
						.closed();
					observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
						.closed();
					null;
				} else "not found: issue anchor";
			case AnchorNoRow, AnchorNoRowWithClose:
				final issueRows:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["exists"]));
				if (scenario == AnchorNoRowWithClose)
					issueRows.closeError(NativeErrors.create("close denied"));
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").rows(issueRows).closed();
				scenario == AnchorNoRow ? "check issue existence in issues: sql: no rows in result set" : "check issue existence in issues: close denied";
			case AnchorOtherErrorMentionsMissingCode:
				final error = new TestMySqlError();
				error.number = 1205;
				error.message = "error 1146";
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1").closeError(TestFormat.wrapMysql("%w", error)))
					.closed();
				"check issue existence in issues: Error 1205: error 1146";
			case HydrationScanFailure, LabelScanFailure:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
				if (scenario == HydrationScanFailure) {
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["id"])).fromCsv("neighbor").closeError(NativeErrors.create("hydrate cleanup failed")))
						.closed();
					// Pinned complete-row scan consumes all 52 destinations.
					"get dependents: fetch issues: get issues by IDs: scan: sql: expected 1 destination arguments in Scan, not 52";
				} else {
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(hydratedIssueRows()).closed();
					observer.expectQuery("SELECT issue_id, label FROM labels WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label", "extra"]))
							.fromCsv("neighbor,label,unused")
							.closeError(NativeErrors.create("label cleanup failed")))
						.closed();
					"get dependents: fetch issues: get issues by IDs: scan label: sql: expected 3 destination arguments in Scan, not 2";
				}
			case EdgeCloseErrorWithPendingResultSet:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				final first:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"]))
					.fromCsv("neighbor,blocks")
					.closeError(NativeErrors.create("edge close failed"));
				final pending:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"]));
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ").rows(first, pending).closed();
				"get dependents: rows from dependencies: edge close failed";
			case HydrationCloseErrorWithPendingResultSet, LabelCloseErrorWithPendingResultSet:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
				if (scenario == HydrationCloseErrorWithPendingResultSet) {
					final first:MockRows = hydratedIssueRows().closeError(NativeErrors.create("hydration close failed"));
					final pending:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["id"]));
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(first, pending).closed();
					"get dependents: fetch issues: get issues by IDs: rows: hydration close failed";
				} else {
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(hydratedIssueRows()).closed();
					final first:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label"]))
						.fromCsv("neighbor,label")
						.closeError(NativeErrors.create("label close failed"));
					final pending:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label"]));
					observer.expectQuery("SELECT issue_id, label FROM labels WHERE ").rows(first, pending).closed();
					"get dependents: fetch issues: get issues by IDs: label rows: label close failed";
				}
			case LabelQueryDenied, LabelRowsDenied:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
				observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(hydratedIssueRows()).closed();
				final labelQuery = observer.expectQuery("SELECT issue_id, label FROM labels WHERE ");
				if (scenario == LabelQueryDenied)
					labelQuery.fail(NativeErrors.create("labels denied"));
				else
					labelQuery.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label"]))
						.fromCsv("neighbor,label")
						.rowError(0, NativeErrors.create("label rows denied")))
						.closed();
				scenario == LabelQueryDenied ? "get dependents: fetch issues: get issues by IDs: labels from labels: labels denied" : "get dependents: fetch issues: get issues by IDs: label rows: label rows denied";
			case HydrationQueryDenied, HydrationRowsDenied:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
				final hydration = observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ");
				if (scenario == HydrationQueryDenied)
					hydration.fail(NativeErrors.create("hydrate denied"));
				else
					hydration.rows(Mocks.rows(go.NativeStringSlice.fromArray(["id"])).fromCsv("neighbor").rowError(0, NativeErrors.create("hydrate denied")))
						.closed();
				scenario == HydrationQueryDenied ? "get dependents: fetch issues: get issues by IDs from issues: hydrate denied" : "get dependents: fetch issues: get issues by IDs: rows: hydrate denied";
			case MissingWispsWithDanglingNeighbor, EmptyWispsWithDanglingNeighbor, WispProbeDeferredMissing, WispProbeCloseMissing,
				WispProbeNoRowCloseMissing, WispProbeCloseError, WispProbeDeferredDenied:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("missing-neighbor,blocks"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				if (scenario == MissingWispsWithDanglingNeighbor)
					observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").fail(NativeErrors.create("table 'wisps' does not exist"));
				else if (scenario == WispProbeDeferredMissing || scenario == WispProbeDeferredDenied)
					observer.expectQuery("SELECT 1 FROM wisps LIMIT 1")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))
							.fromCsv("1")
							.rowError(0, scenario == WispProbeDeferredMissing ? missingTable() : NativeErrors.create("probe denied")))
						.closed();
				else if (scenario == WispProbeNoRowCloseMissing)
					observer.expectQuery("SELECT 1 FROM wisps LIMIT 1")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"])).closeError(missingTable()))
						.closed();
				else if (scenario == WispProbeCloseMissing || scenario == WispProbeCloseError)
					observer.expectQuery("SELECT 1 FROM wisps LIMIT 1")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))
							.fromCsv("1")
							.closeError(scenario == WispProbeCloseMissing ? missingTable() : NativeErrors.create("probe close failed")))
						.closed();
				else
					observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
				if (scenario != WispProbeCloseError && scenario != WispProbeDeferredDenied)
					observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(Mocks.rows(go.NativeStringSlice.fromArray(["id"]))).closed();
				switch scenario {
					case WispProbeCloseError: "get dependents: fetch issues: get issues by IDs: build wisp set: wisp id set: probe: probe close failed";
					case WispProbeDeferredDenied: "get dependents: fetch issues: get issues by IDs: build wisp set: wisp id set: probe: probe denied";
					case _: null;
				}
			case AnchorDeferredMissingIssue, AnchorCloseMissingIssue:
				final issueRows:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1");
				if (scenario == AnchorDeferredMissingIssue)
					issueRows.rowError(0, missingTable());
				else
					issueRows.closeError(missingTable());
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").rows(issueRows).closed();
				observer.expectQuery("SELECT EXISTS.*FROM wisps WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
					.closed();
				null;
			case AnchorDeferredMissingWisp, AnchorCloseMissingWisp:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("0"))
					.closed();
				final wispRows:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1");
				if (scenario == AnchorDeferredMissingWisp)
					wispRows.rowError(0, missingTable());
				else
					wispRows.closeError(missingTable());
				observer.expectQuery("SELECT EXISTS.*FROM wisps WHERE id = ").rows(wispRows).closed();
				"not found: issue anchor";
			case AnchorDeferredDenied, AnchorCloseDenied:
				final issueRows:MockRows = Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1");
				if (scenario == AnchorDeferredDenied)
					issueRows.rowError(0, NativeErrors.create("anchor denied"));
				else
					issueRows.closeError(NativeErrors.create("anchor close denied"));
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").rows(issueRows).closed();
				scenario == AnchorDeferredDenied ? "check issue existence in issues: anchor denied" : "check issue existence in issues: anchor close denied";
			case DeniedIssueTable:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").fail(NativeErrors.create("access denied"));
				"check issue existence in issues: access denied";
			case MissingBothTables:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").fail(NativeErrors.create("table 'issues' does not exist"));
				observer.expectQuery("SELECT EXISTS.*FROM wisps WHERE id = ").fail(NativeErrors.create("table 'wisps' does not exist"));
				"not found: issue anchor";
			case MissingIssueTable, MissingDependencyTable:
				observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").fail(NativeErrors.create("table 'issues' does not exist"));
				observer.expectQuery("SELECT EXISTS.*FROM wisps WHERE id = ")
					.rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1"))
					.closed();
				if (scenario == MissingDependencyTable) {
					observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ").fail(NativeErrors.create("table 'dependencies' does not exist"));
					"get dependents from dependencies: table 'dependencies' does not exist";
				} else {
					observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
						.closed();
					observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
						.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
						.closed();
					null;
				}
		};
		observer.expectRollback();
		observer.expectClose();
		final context = ContextPkg.background();
		final started = connection.database.beginTx(context, new TxOptions());
		if (started.value2 != null)
			throw started.value2.toString();
		final direction = scenario == OutgoingEdgeNullId ? "out" : "in";
		final plan = switch prepareRelationRead("anchor", direction, []) {
			case RelationPlanReady(value): value;
			case RelationPlanInvalid(message): throw message;
		};
		final result = readSqlRelations(context, started.value1, plan);
		final rolledBack = started.value1.rollback();
		final closed = connection.database.close();
		switch result {
			case Failure(message):
				if (message != expectedFailure) {
					Sys.println(message);
					throw "unexpected relation failure";
				}
			case Success(rows):
				if (expectedFailure != null || rows.length != 0)
					throw "unexpected relation success";
		}
		if (rolledBack != null || closed != null)
			throw "transaction cleanup failed";
		final mismatch = observer.verify();
		if (mismatch != null)
			throw mismatch.text();
	}

	static function missingTable():go.NativeError {
		final error = new TestMySqlError();
		error.number = 1146;
		error.message = "opaque driver detail";
		return TestFormat.wrapMysql("%w", error);
	}

	/** One decoded issue makes the reader reach the label query. */
	static function hydratedIssueRows():MockRows {
		final columns = [for (index in 0...52) 'column_$index'];
		final values:Array<Null<String>> = [for (_ in 0...52) null];
		for (index in [0, 2, 3, 4, 5, 6, 7, 9])
			values[index] = "";
		values[0] = "neighbor";
		for (index in [8, 20])
			values[index] = "0";
		return Mocks.rows(go.NativeStringSlice.fromArray(columns)).addRow(...SqlTestValues.fromStrings(values));
	}

	static function issueRowCases():Array<IssueRowCase> {
		return [
			{
				name: "mysql datetime",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: '["a"]',
				metadata: null,
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: ["a"],
				expectedMetadataPresent: false
			},
			{
				name: "rfc3339 nano",
				created: "2024-01-02T03:04:05.123456789+02:00",
				updated: "2024-01-03T04:05:06Z",
				waiters: '["a"]',
				metadata: null,
				expectedCreated: "2024-01-02T03:04:05.123456789+02:00",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: ["a"],
				expectedMetadataPresent: false
			},
			{
				name: "invalid time and waiters",
				created: "not-a-time",
				updated: "bad-time",
				waiters: "[1]",
				metadata: null,
				expectedCreated: "0001-01-01T00:00:00Z",
				expectedUpdated: "0001-01-01T00:00:00Z",
				expectedWaiters: [],
				expectedMetadataPresent: false
			},
			{
				name: "null waiter element",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: '[null,"a"]',
				metadata: null,
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: ["", "a"],
				expectedMetadataPresent: false
			},
			{
				name: "whole null waiter array",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "null",
				metadata: null,
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: false
			},
			{
				name: "empty waiter array",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "[]",
				metadata: null,
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: false
			},
			{
				name: "literal empty object metadata",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "[]",
				metadata: "{}",
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: false
			},
			{
				name: "spaced empty object metadata",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "[]",
				metadata: "{ }",
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: true
			},
			{
				name: "metadata retains surrounding whitespace",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "[]",
				metadata: " { } ",
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: true,
				expectedMetadataBytes: " { } "
			},
			{
				name: "malformed metadata remains a successful raw scan",
				created: "2024-01-02 03:04:05",
				updated: "2024-01-03 04:05:06",
				waiters: "[]",
				metadata: "{",
				expectedCreated: "2024-01-02T03:04:05Z",
				expectedUpdated: "2024-01-03T04:05:06Z",
				expectedWaiters: [],
				expectedMetadataPresent: true,
				expectedMetadataBytes: "{"
			}
		];
	}

	/** Row.Scan returns a scan error before deferred cleanup, but reports close errors after a successful scan. */
	static function checkScalarErrorPrecedence(scenario:ScalarReadErrorScenario):Void {
		final connection = Mocks.create();
		if (connection.error != null)
			throw connection.error.text();
		final observer = connection.mock;
		observer.expectBegin();
		final rows = switch scenario {
			case ScalarCloseFailure: hydratedIssueRows();
			case ScalarScanFailure, ScalarRowsFailure: Mocks.rows(go.NativeStringSlice.fromArray(["id"])).fromCsv("neighbor");
			case ScalarNoRowCloseFailure: Mocks.rows(go.NativeStringSlice.fromArray(["id"]));
		};
		rows.closeError(NativeErrors.create("competing close failure"));
		if (scenario == ScalarRowsFailure)
			rows.rowError(0, NativeErrors.create("iteration failure"));
		observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(rows).closed();
		observer.expectRollback();
		observer.expectClose();
		final context = ContextPkg.background();
		final started = connection.database.beginTx(context, new TxOptions());
		if (started.value2 != null)
			throw started.value2.toString();
		final result = readSqlIssueFields(context, started.value1, SQL_READ_ISSUE, "neighbor");
		final rolledBack = started.value1.rollback();
		final closed = connection.database.close();
		switch result {
			case Failure(message):
				final expectedText = switch scenario {
					case ScalarScanFailure: 'scan scalar issue "neighbor": sql: expected 1 destination arguments in Scan, not ';
					case ScalarCloseFailure: 'close scalar issue "neighbor": competing close failure';
					case ScalarRowsFailure: 'finish scalar issue "neighbor": iteration failure';
					case ScalarNoRowCloseFailure: 'finish scalar issue "neighbor": competing close failure';
				};
				final expected = scenario == ScalarScanFailure ? StringTools.startsWith(message, expectedText) : message == expectedText;
				if (!expected) {
					Sys.println('scalar error precedence expected: $expectedText; received: $message');
					throw 'scalar error precedence: $message';
				}
			case Success(_):
				throw "scalar error precedence unexpectedly succeeded";
		}
		if (rolledBack != null || closed != null)
			throw "scalar error precedence cleanup failed";
		final mismatch = observer.verify();
		if (mismatch != null)
			throw mismatch.text();
	}

	/** The shared decoder must give scalar and relation reads identical fields. */
	static function checkScalarIssueRow(testCase:IssueRowCase):Void {
		final connection = Mocks.create();
		if (connection.error != null)
			throw connection.error.text();
		final observer = connection.mock;
		observer.expectBegin();
		observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(issueRows(testCase)).closed();
		observer.expectRollback();
		observer.expectClose();
		final context = ContextPkg.background();
		final started = connection.database.beginTx(context, new TxOptions());
		if (started.value2 != null)
			throw started.value2.toString();
		final result = readSqlIssueFields(context, started.value1, SQL_READ_ISSUE, "neighbor");
		final rolledBack = started.value1.rollback();
		final closed = connection.database.close();
		switch result {
			case Failure(message):
				Sys.println('scalar ${testCase.name}: $message');
				throw "scalar row failure";
			case Success(fields):
				if (fields == null)
					throw 'scalar ${testCase.name}: missing issue';
				checkIssueFields(fields, testCase);
		}
		if (rolledBack != null || closed != null)
			throw 'scalar ${testCase.name}: cleanup failed';
		final mismatch = observer.verify();
		if (mismatch != null)
			throw mismatch.text();
	}

	static function checkRelationIssueRow(testCase:IssueRowCase):Void {
		final connection = Mocks.create();
		if (connection.error != null)
			throw connection.error.text();
		final observer = connection.mock;
		observer.expectBegin();
		observer.expectQuery("SELECT EXISTS.*FROM issues WHERE id = ").rows(Mocks.rows(go.NativeStringSlice.fromArray(["exists"])).fromCsv("1")).closed();
		observer.expectQuery("SELECT issue_id, type FROM dependencies WHERE ")
			.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])).fromCsv("neighbor,blocks"))
			.closed();
		observer.expectQuery("SELECT issue_id, type FROM wisp_dependencies WHERE ")
			.rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "type"])))
			.closed();
		observer.expectQuery("SELECT 1 FROM wisps LIMIT 1").rows(Mocks.rows(go.NativeStringSlice.fromArray(["1"]))).closed();
		observer.expectQuery("SELECT .* FROM issues LEFT JOIN leases ").rows(issueRows(testCase)).closed();
		observer.expectQuery("SELECT issue_id, label FROM labels WHERE ").rows(Mocks.rows(go.NativeStringSlice.fromArray(["issue_id", "label"]))).closed();
		observer.expectRollback();
		observer.expectClose();
		final context = ContextPkg.background();
		final started = connection.database.beginTx(context, new TxOptions());
		if (started.value2 != null)
			throw started.value2.toString();
		final plan = switch prepareRelationRead("anchor", "in", []) {
			case RelationPlanReady(value): value;
			case RelationPlanInvalid(message): throw message;
		};
		final result = readSqlRelations(context, started.value1, plan);
		final rolledBack = started.value1.rollback();
		final closed = connection.database.close();
		switch result {
			case Failure(message):
				Sys.println('relation ${testCase.name}: $message');
				throw "relation row failure";
			case Success(rows):
				if (rows.length != 1)
					throw 'relation ${testCase.name}: wrong row count';
				checkIssueFields(rows[0].fields, testCase);
		}
		if (rolledBack != null || closed != null)
			throw 'relation ${testCase.name}: cleanup failed';
		final mismatch = observer.verify();
		if (mismatch != null)
			throw mismatch.text();
	}

	static function checkIssueFields(fields:SqlIssueFields, testCase:IssueRowCase):Void {
		// Pinned ScanIssueFrom retains metadata bytes before any JSON rendering.
		final expectedMetadataBytes = testCase.expectedMetadataBytes;
		if (expectedMetadataBytes != null && fields.metadata.wireValue() != expectedMetadataBytes)
			throw '${testCase.name}: scanned metadata bytes changed';
		if (fields.createdAt != testCase.expectedCreated
			|| fields.updatedAt != testCase.expectedUpdated
			|| fields.waiters.join(",") != testCase.expectedWaiters.join(",")
			|| fields.metadata.isAbsent() == testCase.expectedMetadataPresent) {
			Sys.println('${testCase.name}: created=${fields.createdAt} updated=${fields.updatedAt} waiters=${fields.waiters.join(",")} metadataAbsent=${fields.metadata.isAbsent()}');
			throw '${testCase.name}: decoded timestamp, waiters, or metadata differs';
		}
	}

	/** A full 52-column sqlmock row uses the same positions as SQL_ISSUE_COLUMNS. */
	static function issueRows(testCase:IssueRowCase):MockRows {
		final columns = [for (index in 0...52) 'column_$index'];
		final values:Array<Null<String>> = [for (_ in 0...52) null];
		for (index in [0, 2, 3, 4, 5, 6, 7, 9])
			values[index] = "";
		values[0] = "neighbor";
		for (index in [8, 20])
			values[index] = "0";
		values[12] = testCase.created;
		values[15] = testCase.updated;
		values[36] = testCase.waiters;
		values[46] = testCase.metadata;
		final rows = Mocks.rows(go.NativeStringSlice.fromArray(columns));
		return rows.addRow(...SqlTestValues.fromStrings(values));
	}
}
