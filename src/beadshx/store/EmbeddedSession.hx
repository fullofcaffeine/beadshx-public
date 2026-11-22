package beadshx.store;

import beadshx.nativeextern.backoff.BackoffPkg;
import beadshx.nativeextern.backoff.ExponentialBackOff;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.Connector;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** The step that failed before a read could run its body. */
enum EmbeddedSessionStage {
	/** `embedded.NewConnector` refused the configuration, for example because the store directory does not exist. */
	SessionConnector;

	/** `(*sql.DB).PingContext` could not open a connection to the engine. */
	SessionPing;

	/** `(*sql.DB).BeginTx` could not start the read transaction. */
	SessionBegin;
}

/** One release step that failed. Lists of these keep upstream's order: rollback, the database, then the connector. */
enum EmbeddedSessionCleanupFailure {
	SessionRollbackFailed(error:go.Error);
	SessionCloseDatabaseFailed(error:go.Error);
	SessionCloseConnectorFailed(error:go.Error);
}

/** The result of `EmbeddedSession.open`. */
enum EmbeddedSessionOpen {
	EmbeddedSessionOpened(session:EmbeddedSession);

	/** Nothing is left open. `cleanup` lists the release steps that also failed. */
	EmbeddedSessionUnavailable(stage:EmbeddedSessionStage, error:go.Error, cleanup:Array<EmbeddedSessionCleanupFailure>);
}

/** The result of one read transaction. */
enum EmbeddedRead<T> {
	/** The body did not run. `cleanup` lists the release steps that also failed. */
	EmbeddedReadNotStarted(stage:EmbeddedSessionStage, error:go.Error, cleanup:Array<EmbeddedSessionCleanupFailure>);

	/** The body ran and returned `value`. `cleanup` is empty when every release step succeeded. */
	EmbeddedReadFinished(value:T, cleanup:Array<EmbeddedSessionCleanupFailure>);
}

/**
	One open embedded Dolt database, owned by authored Haxe and read-only.

	Why: every embedded read used to open the Dolt connector itself, each with
	its own commit identity, only some with a ping, and none with upstream's
	retry policy for a locked database. This module is the one place that opens
	the store, so later work (the schema skew check, snapshots and Haxe-owned
	writes) has one session to build on.

	What: a port of upstream `internal/storage/embeddeddolt`:
	- `open` is `OpenSQL` (open.go): commit identity `beads` / `beads@local`,
	  multi-statement mode, the selected database, an exponential backoff that
	  waits up to 5 seconds between attempts until the context ends, a pool of
	  at most two connections, and a ping;
	- `read` is the read half of `withConn` (store.go): begin a transaction,
	  run the body, and roll the transaction back;
	- `close` is `OpenSQL`'s cleanup function: close the `*sql.DB`, then the
	  connector;
	- `withRead` is `withConn(ctx, false, fn)`: open, read, and close, with
	  every resource released on every path, also when the body throws.

	How: each step returns its native error instead of a message, so each
	caller keeps the words it showed before. The session has no way to commit
	or run a statement outside a transaction: `Tx` and `DB` have no exec or
	commit extern. A later unit of work adds a write transaction next to `read`
	and is the only code that may reach a commit.

	Upstream steps that are not here yet:
	- `OpenSQL` checks the database name, runs ``USE `db` `` and sets the
	  branch head with `SET`. Those need an exec outside a transaction, which
	  this read-only build does not have. The connector already starts every
	  connection in the selected database. An invalid or missing name therefore
	  fails at the first query of the body, as the readers did before.
	- Upstream's cleanup ignores `context.Canceled` from each close; this one
	  does not. The pinned engine never returns it (`BackgroundThreads.Shutdown`
	  returns nil), and haxe.go cannot yet read a Go package error variable
	  such as `context.Canceled`.
	- `withConn` also refuses a closed store, refuses a commit on a read-only
	  store and scopes the events journal. A closed session fails at `BeginTx`
	  instead, and the other two steps concern writes.

	Each reader opens its own session, as each upstream store call opens its
	own connection. One session kept open across readers would hold the
	database lock while the native facade opens the same database, and the
	facade's backoff would then wait for it forever.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedSession {
	/** Upstream `embeddeddolt.commitName`; Dolt uses it only for commits. */
	public static inline final COMMIT_NAME = "beads";

	/** Upstream `embeddeddolt.commitEmail`. */
	public static inline final COMMIT_EMAIL = "beads@local";

	/** Upstream `db.SetMaxOpenConns(2)` and `db.SetMaxIdleConns(2)`. */
	static inline final MAX_CONNECTIONS = 2;

	final connector:Connector;
	final database:DB;
	final context:Context;
	var closed = false;

	function new(connector:Connector, database:DB, context:Context) {
		this.connector = connector;
		this.database = database;
		this.context = context;
	}

	/**
		Opens the embedded database of the workspace at `beadsDir`, like
		upstream `OpenSQL(ctx, <beadsDir>/embeddeddolt, database, branch)`.
		`selectedDatabase` is a `--db` database name, or empty for the name
		that the workspace configures (`resolveEmbeddedDatabaseName`).
	**/
	public static function open(beadsDir:String, selectedDatabase:String):EmbeddedSessionOpen {
		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, selectedDatabase);
		config.commitName = COMMIT_NAME;
		config.commitEmail = COMMIT_EMAIL;
		config.multiStatements = true;
		config.backOff = openRetryPolicy();
		final created = DoltDriverPkg.newConnector(config);
		if (created.value2 != null)
			return EmbeddedSessionUnavailable(SessionConnector, created.value2, []);
		final database = SqlPkg.openDoltDB(created.value1);
		// Zero means no limit, as upstream's SetConnMaxIdleTime(0) and SetConnMaxLifetime(0).
		final noLimit = constantDuration("0s");
		database.setMaxOpenConns(MAX_CONNECTIONS);
		database.setMaxIdleConns(MAX_CONNECTIONS);
		database.setConnMaxIdleTime(noLimit);
		database.setConnMaxLifetime(noLimit);
		final session = new EmbeddedSession(created.value1, database, ContextPkg.background());
		final pingError = database.pingContext(session.context);
		if (pingError != null)
			return EmbeddedSessionUnavailable(SessionPing, pingError, session.close());
		// beadshx-m08.12 runs upstream's schema.CheckForwardDrift and CheckBehindDrift here,
		// as upstream openReadOnly does right after OpenSQL.
		return EmbeddedSessionOpened(session);
	}

	/**
		Runs `body` in one read transaction and rolls it back, like upstream
		`withConn` with `commit` false, without the open and the close. A
		session can run more than one read.
	**/
	public function read<T>(body:(Context, Tx) -> T):EmbeddedRead<T> {
		final begun = database.beginTx(context, new TxOptions());
		if (begun.value2 != null)
			return EmbeddedReadNotStarted(SessionBegin, begun.value2, []);
		final transaction = begun.value1;
		final value = try body(context, transaction) catch (error:haxe.Exception) {
			transaction.rollback();
			throw error;
		}
		final rollbackError = transaction.rollback();
		return EmbeddedReadFinished(value, rollbackError == null ? [] : [SessionRollbackFailed(rollbackError)]);
	}

	/**
		Closes the database, then the connector, like upstream `OpenSQL`'s
		cleanup function. Both are closed even when the first fails. A second
		call does nothing.
	**/
	public function close():Array<EmbeddedSessionCleanupFailure> {
		if (closed)
			return [];
		closed = true;
		final failures = new Array<EmbeddedSessionCleanupFailure>();
		final databaseError = database.close();
		if (databaseError != null)
			failures.push(SessionCloseDatabaseFailed(databaseError));
		final connectorError = connector.close();
		if (connectorError != null)
			failures.push(SessionCloseConnectorFailed(connectorError));
		return failures;
	}

	/**
		Opens a session, runs `body` in one read transaction and closes the
		session, like upstream `withConn(ctx, false, fn)`. The session is closed
		on every path. If the body throws, the transaction is rolled back and
		the session closed before the exception goes on.
	**/
	public static function withRead<T>(beadsDir:String, selectedDatabase:String, body:(Context, Tx) -> T):EmbeddedRead<T> {
		return switch open(beadsDir, selectedDatabase) {
			case EmbeddedSessionUnavailable(stage, error, cleanup):
				EmbeddedReadNotStarted(stage, error, cleanup);
			case EmbeddedSessionOpened(session):
				final outcome = try session.read(body) catch (error:haxe.Exception) {
					session.close();
					throw error;
				}
				final released = session.close();
				switch outcome {
					case EmbeddedReadNotStarted(stage, error, cleanup): EmbeddedReadNotStarted(stage, error, cleanup.concat(released));
					case EmbeddedReadFinished(value, cleanup): EmbeddedReadFinished(value, cleanup.concat(released));
				}
		};
	}

	/**
		Upstream's `backoff.NewExponentialBackOff()` with `MaxElapsedTime` 0 and
		`MaxInterval` 5 seconds. With a policy, the driver fails an open of a
		locked database at once and tries again until the context ends; without
		one, it would open the database read-only after a short wait.
	**/
	static function openRetryPolicy():ExponentialBackOff {
		final policy = BackoffPkg.newExponentialBackOff();
		policy.maxElapsedTime = constantDuration("0s");
		policy.maxInterval = constantDuration("5s");
		return policy;
	}

	/** A duration written as a valid constant; Go's ParseDuration cannot fail for it. */
	static function constantDuration(text:String):beadshx.nativeextern.time.Duration {
		return TimePkg.parseDuration(text).value1;
	}
}

/**
	The words that one reader puts before each session error.

	Why: before the shared session, each reader opened the store itself and
	named each failed step in its own words. Commands print those words, so the
	readers keep them.
	What: one phrase per step, and the two orders in which the readers report a
	failed release step. How: a reader builds its wording once and passes the
	session's result through `cleanupFailureFirst` or `bodyFailureFirst`.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedReadWording {
	final connector:String;
	final ping:String;
	final begin:String;
	final rollback:String;
	final closeDatabase:String;
	final closeConnector:String;

	public function new(connector:String, ping:String, begin:String, rollback:String, closeDatabase:String, closeConnector:String) {
		this.connector = connector;
		this.ping = ping;
		this.begin = begin;
		this.rollback = rollback;
		this.closeDatabase = closeDatabase;
		this.closeConnector = closeConnector;
	}

	/**
		`open embedded <noun> connector`, `begin embedded <noun> transaction`,
		`roll back embedded <noun> transaction`, `close embedded <noun>
		database` and `close embedded <noun> connector`. A reader that pinged
		before says `ping embedded <noun> database`. A reader that did not ping
		before uses its begin words for a failed ping: the ping meets the same
		connection error that `BeginTx` met before.
	**/
	public static function forNoun(noun:String, pinged:Bool):EmbeddedReadWording {
		final begin = 'begin embedded $noun transaction';
		return new EmbeddedReadWording('open embedded $noun connector', pinged ? 'ping embedded $noun database' : begin, begin,
			'roll back embedded $noun transaction', 'close embedded $noun database', 'close embedded $noun connector');
	}

	public function stageMessage(stage:EmbeddedSessionStage, error:go.Error):String {
		final words = switch stage {
			case SessionConnector: connector;
			case SessionPing: ping;
			case SessionBegin: begin;
		};
		return '$words: ${error.toString()}';
	}

	public function cleanupMessage(failure:EmbeddedSessionCleanupFailure):String {
		return switch failure {
			case SessionRollbackFailed(error): '$rollback: ${error.toString()}';
			case SessionCloseDatabaseFailed(error): '$closeDatabase: ${error.toString()}';
			case SessionCloseConnectorFailed(error): '$closeConnector: ${error.toString()}';
		};
	}

	/** The first failed release step replaces the body's result, even a failed one. */
	public function cleanupFailureFirst<T>(read:EmbeddedRead<StoreResult<T>>):StoreResult<T> {
		return switch read {
			case EmbeddedReadNotStarted(stage, error, _): Failure(stageMessage(stage, error));
			case EmbeddedReadFinished(value, cleanup): cleanup.length == 0 ? value : Failure(cleanupMessage(cleanup[0]));
		};
	}

	/** A failed body wins over failed release steps; after a successful body, the first failed step replaces it. */
	public function bodyFailureFirst<T>(read:EmbeddedRead<StoreResult<T>>):StoreResult<T> {
		return switch read {
			case EmbeddedReadNotStarted(stage, error, _): Failure(stageMessage(stage, error));
			case EmbeddedReadFinished(Failure(message), _): Failure(message);
			case EmbeddedReadFinished(value, cleanup): cleanup.length == 0 ? value : Failure(cleanupMessage(cleanup[0]));
		};
	}
}
