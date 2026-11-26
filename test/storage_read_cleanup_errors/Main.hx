import haxe.Int64;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.CustomConfig.DatabaseCustomStatuses;
import beadshx.store.CustomConfig.DatabaseCustomTypes;
import beadshx.store.EmbeddedCustomConfigReader;
import beadshx.store.EmbeddedEventsJournalReader;
import beadshx.store.EmbeddedGraphReader;
import beadshx.store.EmbeddedIssueListReader;
import beadshx.store.EmbeddedIssueSummaryReader;
import beadshx.store.EmbeddedIssueSummaryReader.EmbeddedIssueSummaryResult;
import beadshx.store.EmbeddedReadyReader;
import beadshx.store.EmbeddedReadyReader.ReadyPageRead;
import beadshx.store.EmbeddedSession;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.EventsJournal.EventsJournalRead;
import beadshx.store.EventsJournal.EventsJournalWindow;
import beadshx.store.IssueListResult;
import beadshx.store.ReadyLoadResult;
import beadshx.store.SqlGraphReader.AllGraphLoad;
import beadshx.store.SqlReadyWorkReader.ReadyWorkFilter;
import beadshx.store.StoreResult;

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock")
extern class CleanupMocks {
	@:go.name("New") @:go.tupleReturn public static function create():CleanupMockConnection;
}

class CleanupMockConnection {
	public final database:DB;
	public final mock:CleanupMock;
	public final error:go.NativeError;

	public function new(database:DB, mock:CleanupMock, error:go.NativeError) {
		this.database = database;
		this.mock = mock;
		this.error = error;
	}
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("Sqlmock")
extern interface CleanupMock {
	@:go.name("ExpectBegin") public function expectBegin():CleanupExpectedBegin;
	@:go.name("ExpectQuery") public function expectQuery(query:String):CleanupExpectedQuery;
	@:go.name("ExpectRollback") public function expectRollback():CleanupExpectedRollback;
	@:go.name("ExpectClose") public function expectClose():CleanupExpectedClose;
	@:go.name("ExpectationsWereMet") public function verify():go.NativeError;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedBegin")
extern class CleanupExpectedBegin {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):CleanupExpectedBegin;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedQuery")
extern class CleanupExpectedQuery {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):CleanupExpectedQuery;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedRollback")
extern class CleanupExpectedRollback {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):CleanupExpectedRollback;
}

@:go.import("github.com/DATA-DOG/go-sqlmock") @:go.package("sqlmock") @:go.name("ExpectedClose")
extern class CleanupExpectedClose {
	@:go.name("WillReturnError") public function fail(error:go.NativeError):CleanupExpectedClose;
}

@:go.import("errors") extern class CleanupErrors {
	@:go.name("New") public static function create(message:String):go.NativeError;
}

/** One read through the real session over sqlmock, and the release steps that failed. */
private typedef ObservedRead = {
	final read:EmbeddedRead<StoreResult<Bool>>;
	final cleanup:Array<EmbeddedSessionCleanupFailure>;
}

/**
	Upstream `withConn` (internal/storage/embeddeddolt/store.go) on a read:
	a failed body returns `errors.Join(fnErr, tx.Rollback())`, a successful
	body returns the bare `tx.Rollback()` error, and the deferred cleanup joins
	the close errors after either. `errors.Join` prints one error per line and
	adds no words. These cases drive the real `EmbeddedSession.read` over
	sqlmock, whose rollback and close fail on request, and check the error
	that each reader policy returns.
**/
@:goNative
@:access(beadshx.store.EmbeddedSession)
@:access(beadshx.store.EmbeddedIssueSummaryReader)
@:access(beadshx.store.EmbeddedCustomConfigReader)
@:access(beadshx.store.EmbeddedEventsJournalReader)
@:access(beadshx.store.EmbeddedGraphReader)
@:access(beadshx.store.EmbeddedIssueListReader)
@:access(beadshx.store.EmbeddedReadyReader)
class Main {
	static inline final READ_ERROR = "query failed";
	static inline final ROLLBACK_ERROR = "rollback failed";
	static inline final CLOSE_ERROR = "close failed";

	static final mismatches = new Array<String>();

	static function main():Void {
		for (readFailed in [false, true])
			for (rollbackFailed in [false, true])
				for (closeFailed in [false, true]) {
					final name = 'read=${flag(readFailed)} rollback=${flag(rollbackFailed)} close=${flag(closeFailed)}';
					final observed = observe(readFailed, rollbackFailed, closeFailed);
					final expected = upstreamError([
						readFailed ? 'read issues: $READ_ERROR' : null,
						rollbackFailed ? ROLLBACK_ERROR : null,
						closeFailed ? CLOSE_ERROR : null
					]);
					record(() -> checkReaderPolicies(name, observed, expected));
					record(() -> checkSummary(name, readFailed, observed.cleanup, expected));
				}
		record(checkBeginFailure);
		record(() -> checkPerCallReaders(observe(false, true, false).cleanup));
		if (mismatches.length > 0) {
			for (failure in mismatches)
				// One line per case; Haxe unescapes a single-quoted string before its `${}` parts.
				Sys.stderr().writeString("FAIL: " + StringTools.replace(failure, "\n", "\\n") + "\n");
			Sys.stderr().writeString('Embedded read cleanup contracts: ${mismatches.length} failed\n');
			Sys.exit(1);
		}
		Sys.println("Embedded read cleanup contracts: PASS");
	}

	/** Runs one check and keeps its failure, so one run lists every case that differs from upstream. */
	static function record(check:() -> Void):Void {
		try
			check()
		catch (error:haxe.Exception)
			mismatches.push(error.message);
	}

	static function flag(value:Bool):String
		return value ? "fails" : "ok";

	/** `errors.Join` of the errors that are not nil: null when every step succeeded. */
	static function upstreamError(parts:Array<Null<String>>):Null<String> {
		final present = [for (part in parts) if (part != null) part];
		return present.length == 0 ? null : present.join("\n");
	}

	/**
		Runs one read through `EmbeddedSession.read` on a sqlmock database. A
		failed close comes from sqlmock's `Close`, after the rollback, in the
		order of upstream's cleanup.
	**/
	static function observe(readFailed:Bool, rollbackFailed:Bool, closeFailed:Bool):ObservedRead {
		final opened = CleanupMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin();
		if (readFailed)
			opened.mock.expectQuery("SELECT").fail(CleanupErrors.create(READ_ERROR));
		final rollback = opened.mock.expectRollback();
		if (rollbackFailed)
			rollback.fail(CleanupErrors.create(ROLLBACK_ERROR));
		final close = opened.mock.expectClose();
		if (closeFailed)
			close.fail(CleanupErrors.create(CLOSE_ERROR));
		// The session's read uses only its database and context; the connector belongs to `close`.
		final session = new EmbeddedSession(null, opened.database, ContextPkg.background());
		final read = session.read((context, transaction) -> readIssues(context, transaction, readFailed));
		final cleanup = switch read {
			case EmbeddedReadFinished(_, failures): failures.copy();
			case EmbeddedReadNotStarted(stage, error, _): throw 'read did not start: $stage ${error.toString()}';
		};
		final closeError = opened.database.close();
		if (closeError != null)
			cleanup.push(SessionCloseDatabaseFailed(closeError));
		final verification = opened.mock.verify();
		if (verification != null)
			throw verification.text();
		return {read: withCleanup(read, cleanup), cleanup: cleanup};
	}

	/** The session read with the database close of `withRead` added, as `withRead` adds it. */
	static function withCleanup<T>(read:EmbeddedRead<T>, cleanup:Array<EmbeddedSessionCleanupFailure>):EmbeddedRead<T> {
		return switch read {
			case EmbeddedReadFinished(value, _): EmbeddedReadFinished(value, cleanup);
			case EmbeddedReadNotStarted(stage, error, failures): EmbeddedReadNotStarted(stage, error, failures);
		};
	}

	/** A reader body: one query, whose failure the body reports in its own words. */
	static function readIssues(context:Context, transaction:Tx, fails:Bool):StoreResult<Bool> {
		if (!fails)
			return Success(true);
		final queried = transaction.queryContext(context, "SELECT id FROM issues");
		if (queried.value2 != null)
			return Failure('read issues: ${queried.value2.toString()}');
		queried.value1.close();
		return Success(true);
	}

	/** The policy that the readers of `StoreResult` use must give upstream's error. */
	static function checkReaderPolicies(name:String, observed:ObservedRead, expected:Null<String>):Void {
		final wording = EmbeddedReadWording.forNoun("relation", false);
		for (policy in [{name: "joinedResult", result: wording.joinedResult(observed.read)}])
			record(() -> requireResult('$name ${policy.name}', policy.result, expected));
	}

	/**
		The readers whose upstream call treats a failed release step in its own
		way, each with a read whose rollback failed (`rollback`) and, where it
		matters, one whose body failed too.
	**/
	static function checkPerCallReaders(rollback:Array<EmbeddedSessionCleanupFailure>):Void {
		// GetCustomTypes and GetCustomStatusesDetailed fall back, and `bd types` and `bd statuses` ignore the error.
		record(() -> switch EmbeddedCustomConfigReader.fallBackAfterRelease(EmbeddedReadFinished(StoredTypes(["custom"]), rollback), UnreadableTypes) {
			case Success(UnreadableTypes):
			case other: throw 'types after a failed rollback: expected the fallback, received $other';
		});
		record(() -> switch EmbeddedCustomConfigReader.fallBackAfterRelease(EmbeddedReadFinished(StoredTypes(["custom"]), []), UnreadableTypes) {
			case Success(StoredTypes(["custom"])):
			case other: throw 'types after a clean read: expected the stored types, received $other';
		});
		record(() -> switch EmbeddedCustomConfigReader.fallBackAfterRelease(EmbeddedReadFinished(StoredStatuses([]), rollback), NoStoredStatuses) {
			case Success(NoStoredStatuses):
			case other: throw 'statuses after a failed rollback: expected the fallback, received $other';
		});

		// `bd events` finds a truncated window through the join with errors.As; records take the join.
		final window:EventsJournalWindow = {since: Int64.ofInt(1), floor: Int64.ofInt(5), head: Int64.ofInt(9)};
		record(() -> switch EmbeddedEventsJournalReader.finishJournalRead(EmbeddedReadFinished(Success(JournalTruncated(window)), rollback)) {
			case Success(JournalTruncated(kept)) if (Int64.toStr(kept.floor) == "5"):
			case other: throw 'truncated journal after a failed rollback: expected the window, received $other';
		});
		record(() -> requireResult("journal records after a failed rollback",
			done(EmbeddedEventsJournalReader.finishJournalRead(EmbeddedReadFinished(Success(JournalRecords([])), rollback))), ROLLBACK_ERROR));

		// loadGraphSubgraph wraps GetIssue, its first store call; a failed body already carries those words.
		record(() -> requireResult("graph subgraph after a failed rollback",
			EmbeddedGraphReader.finishSubgraph(EmbeddedReadFinished(Success(true), rollback)), 'failed to get issue: $ROLLBACK_ERROR'));
		record(() -> requireResult("graph subgraph after a failed root read",
			EmbeddedGraphReader.finishSubgraph(EmbeddedReadFinished(Failure('failed to get issue: get issue: $READ_ERROR'), rollback)),
			'failed to get issue: get issue: $READ_ERROR\n$ROLLBACK_ERROR'));
		// loadAllGraphSubgraphs wraps SearchIssues; handleMaxRowsError finds a row cap through the join.
		record(() -> switch EmbeddedGraphReader.finishAllGraphs(EmbeddedReadFinished(Success(AllGraphRowLimitExceeded(5, 3)), rollback)) {
			case Success(AllGraphRowLimitExceeded(5, 3)):
			case other: throw 'graph --all row cap after a failed rollback: expected the cap, received $other';
		});
		record(() -> requireResult("graph --all after a failed rollback",
			done(EmbeddedGraphReader.finishAllGraphs(EmbeddedReadFinished(Success(AllGraphRows([], [])), rollback))),
			'failed to search issues: $ROLLBACK_ERROR'));

		// A list page: the row cap stays, a page gives the bare release errors, a failed page joins them.
		final listWording = EmbeddedReadWording.forNoun("list", false);
		record(() -> switch EmbeddedIssueListReader.finishListRead(listWording, EmbeddedReadFinished(ListRowLimitExceeded(5, "--limit", 3), rollback)) {
			case ListRowLimitExceeded(5, "--limit", 3):
			case other: throw 'list row cap after a failed rollback: expected the cap, received $other';
		});
		record(() -> requireResult("list page after a failed rollback",
			listDone(EmbeddedIssueListReader.finishListRead(listWording, EmbeddedReadFinished(ListSuccess({
				items: [],
				hasMore: false,
				formatted: ""
			}), rollback))), ROLLBACK_ERROR));
		record(() -> requireResult("failed list page after a failed rollback",
			listDone(EmbeddedIssueListReader.finishListRead(listWording, EmbeddedReadFinished(ListFailure('read issues: $READ_ERROR'), rollback))),
			'read issues: $READ_ERROR\n$ROLLBACK_ERROR'));

		// The ready page, likewise.
		record(() -> switch EmbeddedReadyReader.finishPageRead(EmbeddedReadFinished(ReadyStopped(ReadyRowLimitExceeded(5, "--limit", 3)), rollback)) {
			case ReadyStopped(ReadyRowLimitExceeded(5, "--limit", 3)):
			case other: throw 'ready row cap after a failed rollback: expected the cap, received $other';
		});
		record(() -> switch EmbeddedReadyReader.finishPageRead(EmbeddedReadFinished(ReadyPage(new ReadyWorkFilter(), []), rollback)) {
			case ReadyStopped(ReadyFailure(message)) if (message == ROLLBACK_ERROR):
			case other: throw 'ready page after a failed rollback: expected "$ROLLBACK_ERROR", received $other';
		});
		record(() -> switch EmbeddedReadyReader.finishPageRead(EmbeddedReadFinished(ReadyStopped(ReadyFailure('read issues: $READ_ERROR')), rollback)) {
			case ReadyStopped(ReadyFailure(message)) if (message == 'read issues: $READ_ERROR\n$ROLLBACK_ERROR'):
			case other: throw 'failed ready page after a failed rollback: received $other';
		});
	}

	static function done<T>(result:StoreResult<T>):StoreResult<Bool> {
		return switch result {
			case Success(_): Success(true);
			case Failure(message): Failure(message);
		};
	}

	static function listDone(result:IssueListResult):StoreResult<Bool> {
		return switch result {
			case ListSuccess(_): Success(true);
			case ListFailure(message): Failure(message);
			case ListRowLimitExceeded(found, _, cap): Failure('row cap: $found over $cap');
		};
	}

	static function requireResult(name:String, result:StoreResult<Bool>, expected:Null<String>):Void {
		switch result {
			case Success(_):
				if (expected != null)
					throw '$name: expected "$expected", received success';
			case Failure(message):
				if (message != expected)
					throw '$name: expected "$expected", received "$message"';
		}
	}

	/** The summary reader joins in its own result type; a missing issue stands for a successful read. */
	static function checkSummary(name:String, readFailed:Bool, cleanup:Array<EmbeddedSessionCleanupFailure>, expected:Null<String>):Void {
		final input = readFailed ? EmbeddedIssueSummaryFailure('read issues: $READ_ERROR') : EmbeddedIssueSummaryMissing;
		switch EmbeddedIssueSummaryReader.finishSummaryRead(input, cleanup) {
			case EmbeddedIssueSummaryFailure(message):
				if (message != expected)
					throw '$name summary: expected "$expected", received "$message"';
			case EmbeddedIssueSummaryMissing:
				if (expected != null)
					throw '$name summary: expected "$expected", received missing';
			case EmbeddedIssueSummaryFound(_):
				throw '$name summary: unexpected issue';
		}
	}

	/** A read whose transaction does not begin keeps the reader's begin words; the body does not run. */
	static function checkBeginFailure():Void {
		final opened = CleanupMocks.create();
		if (opened.error != null)
			throw opened.error.text();
		opened.mock.expectBegin().fail(CleanupErrors.create("begin failed"));
		opened.mock.expectClose();
		final session = new EmbeddedSession(null, opened.database, ContextPkg.background());
		var ran = false;
		final read = session.read((context, transaction) -> {
			ran = true;
			return Success(true);
		});
		final closeError = opened.database.close();
		if (closeError != null)
			throw closeError.toString();
		final verification = opened.mock.verify();
		if (verification != null)
			throw verification.text();
		if (ran)
			throw "begin failure: the body ran";
		requireResult("begin failure", EmbeddedReadWording.forNoun("relation", false).joinedResult(read), "begin embedded relation transaction: begin failed");
	}
}
