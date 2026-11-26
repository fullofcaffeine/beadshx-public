import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedSession;
import beadshx.store.InvalidDatabaseName;
import beadshx.store.InvalidDatabaseName.InvalidDatabaseNameStep;
import beadshx.store.StoreResult;

/**
	Proves the shared embedded session over an upstream-created disposable
	workspace: one read transaction, two reads on one session, rollback of every
	read, release after a throwing body, waiting for a locked database as
	upstream's backoff does, the refusal of a database name that is not an
	identifier, and the readers' error words for a missing store and a missing
	database.
**/
@:goNative
@:access(beadshx.store.EmbeddedSession)
class Main {
	static final PROBE_KEY = "beadshx.session.probe";

	static function main():Void {
		final args = Sys.args();
		if (args.length != 3)
			throw "usage: embedded-session-test <workspace .beads> <missing-store .beads> <issue id>";
		final beadsDir = args[0];
		final missingStore = args[1];
		final issueId = args[2];
		for (directory in [beadsDir, missingStore])
			if (!sys.FileSystem.exists(haxe.io.Path.join([haxe.io.Path.directory(directory), ".beadshx-disposable-fixture"])))
				throw 'embedded session test requires a disposable fixture: $directory';
		// A leaked session holds the database lock, and the next open waits for it forever.
		go.Go.spawn(() -> {
			Sys.sleep(90);
			Sys.stderr().writeString("embedded session test: timed out\n");
			Sys.exit(3);
		});

		try {
			readsOneTransaction(beadsDir, issueId);
			reusesOneSession(beadsDir, issueId);
			rollsBackEveryRead(beadsDir);
			releasesAfterThrowingBody(beadsDir, issueId);
			waitsForLockedDatabase(beadsDir, issueId);
			reportsMissingStore(missingStore);
			reportsMissingDatabase(beadsDir);
			refusesInvalidDatabaseName(beadsDir);
			keepsReaderMessages(beadsDir, missingStore, issueId);
		} catch (error:haxe.Exception) {
			Sys.stderr().writeString('embedded session: FAIL: ${error.message}\n');
			Sys.exit(1);
		}
		Sys.println("embedded session: PASS");
	}

	static function readsOneTransaction(beadsDir:String, issueId:String):Void {
		switch EmbeddedSession.withRead(beadsDir, "", (context, transaction) -> countIssue(context, transaction, issueId)) {
			case EmbeddedReadFinished(Success("1"), []):
			case other:
				throw 'one read: expected the issue once and no cleanup failure, received $other';
		}
	}

	static function reusesOneSession(beadsDir:String, issueId:String):Void {
		final session = opened(beadsDir, "");
		if (session.database.stats().maxOpenConnections != 2)
			throw 'session pool: expected upstream limit 2, received ${session.database.stats().maxOpenConnections}';
		for (attempt in 0...2)
			switch session.read((context, transaction) -> countIssue(context, transaction, issueId)) {
				case EmbeddedReadFinished(Success("1"), []):
				case other:
					throw 'session read $attempt: received $other';
			}
		if (session.database.stats().openConnections > 1)
			throw "session reads: expected one reused connection";
		requireNoCleanupFailure("session close", session.close());
		if (session.database.stats().openConnections != 0)
			throw "session close: connections remain open";
		requireNoCleanupFailure("second close", session.close());
		switch session.read((context, transaction) -> countIssue(context, transaction, issueId)) {
			case EmbeddedReadNotStarted(SessionBegin, _, []):
			case other:
				throw 'read after close: expected a begin failure, received $other';
		}
	}

	/** A write inside a read is visible to that read only: the session always rolls back. */
	static function rollsBackEveryRead(beadsDir:String):Void {
		switch EmbeddedSession.withRead(beadsDir, "", (context, transaction) -> {
			final inserted = transaction.queryContext(context, "INSERT INTO config (`key`, value) VALUES (?, 'inside')", PROBE_KEY);
			if (inserted.value2 != null)
				return Failure('insert probe: ${inserted.value2.toString()}');
			inserted.value1.close();
			return probeValue(context, transaction);
		}) {
			case EmbeddedReadFinished(Success("inside"), []):
			case other:
				throw 'write inside read: expected the probe inside the transaction, received $other';
		}
		switch EmbeddedSession.withRead(beadsDir, "", probeValue) {
			case EmbeddedReadFinished(Success(""), []):
			case other:
				throw 'rollback: expected no probe after the read, received $other';
		}
	}

	static function releasesAfterThrowingBody(beadsDir:String, issueId:String):Void {
		var thrown = false;
		try {
			EmbeddedSession.withRead(beadsDir, "", (context, transaction) -> {
				countIssue(context, transaction, issueId);
				throw new haxe.Exception("body failed");
			});
		} catch (error:haxe.Exception) {
			thrown = error.message == "body failed";
		}
		if (!thrown)
			throw "throwing body: the exception did not reach the caller";
		final session = opened(beadsDir, "");
		var rethrown = false;
		try {
			session.read((context, transaction) -> throw new haxe.Exception("read failed"));
		} catch (error:haxe.Exception) {
			rethrown = error.message == "read failed";
		}
		if (!rethrown)
			throw "throwing read: the exception did not reach the caller";
		if (session.database.stats().inUse != 0)
			throw "throwing read: the transaction kept its connection";
		requireNoCleanupFailure("close after throwing read", session.close());
		// With the lock still held by a leaked session, this open would never return.
		readsOneTransaction(beadsDir, issueId);
	}

	/**
		Upstream's backoff makes an open wait while another engine holds the
		database. Without it, the driver opens the database read-only after
		100 ms and does not wait.
	**/
	static function waitsForLockedDatabase(beadsDir:String, issueId:String):Void {
		final holder = opened(beadsDir, "");
		final released = go.Go.newChan(1);
		go.Go.spawn(() -> {
			Sys.sleep(1.5);
			requireNoCleanupFailure("holder close", holder.close());
			released.send(true);
		});
		final waiter = opened(beadsDir, "");
		if (!released.tryRecv().isOk())
			throw "locked database: the second open did not wait for the first session";
		switch waiter.read((context, transaction) -> countIssue(context, transaction, issueId)) {
			case EmbeddedReadFinished(Success("1"), []):
			case other:
				throw 'locked database: read after waiting received $other';
		}
		requireNoCleanupFailure("waiter close", waiter.close());
	}

	static function reportsMissingStore(missingStore:String):Void {
		var ran = false;
		switch EmbeddedSession.withRead(missingStore, "", (context, transaction) -> {
			ran = true;
			return true;
		}) {
			case EmbeddedReadNotStarted(SessionConnector, error, []):
				final expected = "'" + haxe.io.Path.join([missingStore, "embeddeddolt"]) + "' does not exist";
				if (error.toString() != expected)
					throw 'missing store: expected "$expected", received "${error.toString()}"';
			case other:
				throw 'missing store: expected a connector failure, received $other';
		}
		if (ran)
			throw "missing store: the body ran";
	}

	/** The connector starts each connection in the selected database, so a missing one fails at the first query. */
	static function reportsMissingDatabase(beadsDir:String):Void {
		switch EmbeddedSession.withRead(beadsDir, "absent_db", (context, transaction) -> countIssue(context, transaction, "any")) {
			case EmbeddedReadFinished(Failure(message), []):
				if (message != "count issue: Error 1049: database not found: absent_db")
					throw 'missing database: received "$message"';
			case other:
				throw 'missing database: expected the body to fail, received $other';
		}
	}

	/** Upstream `OpenSQL` refuses a name that is not an identifier after its ping, before any read; only a hyphen adds the hint. */
	static function refusesInvalidDatabaseName(beadsDir:String):Void {
		final hint = "; hyphens are not allowed in embedded mode — replace with underscores in .beads/metadata.json dolt_database field, or run 'bd doctor'";
		for (name => expected in [
			"te-st" => 'invalid database name: "te-st"$hint',
			"te.st" => 'invalid database name: "te.st"',
			"1x" => 'invalid database name: "1x"'
		]) {
			var ran = false;
			switch EmbeddedSession.withRead(beadsDir, name, (context, transaction) -> {
				ran = true;
				return true;
			}) {
				case EmbeddedReadNotStarted(SessionDatabaseName, error, []):
					if (error.toString() != expected)
						throw 'invalid name $name: expected "$expected", received "${error.toString()}"';
				case other:
					throw 'invalid name $name: expected a database name failure, received $other';
			}
			if (ran)
				throw 'invalid name $name: the body ran';
		}
		// The refused session released the database: the next open does not wait for it.
		requireNoCleanupFailure("open after an invalid name", opened(beadsDir, "").close());
		// The store opens that a command meets first: newStore adds `embeddeddolt: init schema: `, openReadOnly drops the hint; all quote with %q.
		for (actual => expected in [
			InvalidDatabaseName.error("te-st", InitSchemaName) => 'embeddeddolt: init schema: embeddeddolt: invalid database name: "te-st"$hint',
			InvalidDatabaseName.error("te-st", ReadOnlyOpenName) => 'embeddeddolt: invalid database name: "te-st"',
			InvalidDatabaseName.error("te.st", InitSchemaName) => 'embeddeddolt: init schema: embeddeddolt: invalid database name: "te.st"',
			InvalidDatabaseName.error('t"é\n', OpenSqlName) => 'invalid database name: "t\\"é\\n"'
		])
			if (actual != expected)
				throw 'invalid name words: expected "$expected", received "$actual"';
	}

	static function keepsReaderMessages(beadsDir:String, missingStore:String, issueId:String):Void {
		final actual = ReaderMessages.observe("ok", beadsDir, "", issueId)
			.concat(ReaderMessages.observe("no-db", beadsDir, "absent_db", issueId))
			.concat(ReaderMessages.observe("no-store", missingStore, "", issueId));
		final expected = expectedReaderMessages(issueId);
		for (index in 0...Std.int(Math.max(actual.length, expected.length)))
			if (actual[index] != expected[index])
				throw 'reader message $index: expected "${expected[index]}", received "${actual[index]}"';
	}

	/** Each reader's words before the shared session, captured from the readers as they were. */
	static function expectedReaderMessages(issueId:String):Array<String> {
		// Each reader, in call order, and the noun its connector error names.
		final nouns = [
			"types:config",
			"statuses:config",
			"config-get:config",
			"config-list:config",
			"blocked:blocked",
			"stale:stale",
			"list:list",
			"ready:ready",
			"count:count",
			"search:search",
			"query:query",
			"ping:ping",
			"comments:comments",
			"cycles:cycle",
			"events:events",
			"graph-cycles:graph",
			"graph-subgraph:graph",
			"graph-all:graph",
			"history:history",
			"history-events:history",
			"relations:relation",
			"tree:tree",
			"assigned:assigned-issue",
			"id-search:issue-ID",
			"dependencies:dependency",
			"summary:issue",
			"details:detail",
			"dependents:relation"
		];
		final missingDatabase = "Error 1049: database not found: absent_db";
		final noDatabase = [
			"types: ok",
			"statuses: ok",
			'config-get: error: get config issue_prefix: $missingDatabase',
			'config-list: error: get all config: $missingDatabase',
			'blocked: error: read blocked ids from issues: $missingDatabase',
			'stale: error: failed to get stale issues: $missingDatabase',
			'list: error: search issues with counts: wisp dependency probe: $missingDatabase',
			'ready: error: get ready work with counts: wisp dependency probe: $missingDatabase',
			'count: error: count by column status: $missingDatabase',
			'search: error: search issues with counts: wisp dependency probe: $missingDatabase',
			'query: error: search issues with counts: wisp dependency probe: $missingDatabase',
			'ping: error: count issues: $missingDatabase',
			'comments: error: get issue comments from comments: $missingDatabase',
			'cycles: error: dependency graph: query dependencies: $missingDatabase',
			'events: error: journal: read since 0: $missingDatabase',
			'graph-cycles: error: dependency graph: query dependencies: $missingDatabase',
			'graph-subgraph: error: failed to get issue: get issue: $missingDatabase',
			'graph-all: error: failed to search issues: search issues: search issues: $missingDatabase',
			'history: error: failed to get issue history: $missingDatabase',
			'history-events: error: get events: $missingDatabase',
			'relations: error: check issue existence in issues: $missingDatabase',
			'tree: error: get issue: $missingDatabase',
			'assigned: error: read assigned issue: $missingDatabase',
			'id-search: error: search embedded issue IDs: $missingDatabase',
			'dependencies: error: read dependency anchor "$issueId": $missingDatabase',
			'summary: error: get issue: $missingDatabase'
		];
		final missing = "'<beads>/embeddeddolt' does not exist";
		final noStore = [
			for (pair in nouns)
				'${pair.split(":")[0]}: error: open embedded ${pair.split(":")[1]} connector: $missing'
		];
		return [for (pair in nouns) 'ok/${pair.split(":")[0]}: ok'].concat([for (line in noDatabase) 'no-db/$line'])
			.concat([for (line in noStore) 'no-store/$line']);
	}

	static function opened(beadsDir:String, database:String):EmbeddedSession {
		return switch EmbeddedSession.open(beadsDir, database) {
			case EmbeddedSessionOpened(session): session;
			case EmbeddedSessionUnavailable(stage, error, _): throw 'open $stage: ${error.toString()}';
		};
	}

	static function requireNoCleanupFailure(step:String, failures:Array<EmbeddedSessionCleanupFailure>):Void {
		if (failures.length != 0)
			throw '$step: $failures';
	}

	static function countIssue(context:Context, transaction:Tx, issueId:String):StoreResult<String> {
		return firstValue(context, transaction, "count issue", "SELECT CAST(COUNT(*) AS CHAR) FROM issues WHERE id = ?", issueId);
	}

	static function probeValue(context:Context, transaction:Tx):StoreResult<String> {
		return firstValue(context, transaction, "read probe", "SELECT value FROM config WHERE `key` = ?", PROBE_KEY);
	}

	/** The first column of the first row, or empty when there is no row. */
	static function firstValue(context:Context, transaction:Tx, step:String, query:String, argument:String):StoreResult<String> {
		final queried = transaction.queryContext(context, query, argument);
		if (queried.value2 != null)
			return Failure('$step: ${queried.value2.toString()}');
		final rows = queried.value1;
		var value = "";
		if (rows.next()) {
			final scanned = new NullString();
			final scanError = rows.scan(scanned);
			if (scanError != null) {
				rows.close();
				return Failure('$step: ${scanError.toString()}');
			}
			value = scanned.valid ? scanned.string : "";
		}
		final rowError = rows.err();
		rows.close();
		return rowError == null ? Success(value) : Failure('$step: ${rowError.toString()}');
	}
}
