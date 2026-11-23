package beadshx.store;

/**
	Upstream `schema.LatestVersion()` in the pinned v1.2.1 binary: the highest
	main-lane migration, `0065_widen_wisp_comments_text`. The main lane of
	`compatibility/schema-migrations/plan.json` records the same number, and its
	check proves that number against the pinned upstream tree.
**/
final BINARY_SCHEMA_VERSION = 65;

/** Upstream `SchemaSkewError.EscapeHint`. */
final SCHEMA_SKEW_ESCAPE_HINT = "BD_IGNORE_SCHEMA_SKEW=1 bd <command>  or  bd --ignore-schema-skew <command>";

/** Why upstream's read-only store open stops a command before its body runs. */
enum SchemaSkewRefusal {
	/** Upstream `*schema.SchemaSkewError`: the database is ahead of the binary. */
	DatabaseAhead(databaseVersion:Int, binaryVersion:Int);

	/** Upstream `*schema.SchemaBehindError`: the database is behind, and the open cannot migrate it. */
	DatabaseBehind(databaseVersion:Int, binaryVersion:Int);

	/** The version read failed. `message` is upstream's whole error, such as `schema behind-drift check: ...`. */
	SchemaCheckFailed(message:String);
}

/**
	A command stopped at its store open because of schema skew.

	Why: upstream checks the schema once, when the root pre-run opens the
	store, and a refusal there ends the command before its body runs. This
	build opens the embedded store lazily, inside the first read, and the
	readers below that read wrap their own failures in command words.
	What: the refusal, raised past those readers to the command boundary,
	which prints it as upstream's pre-run does (`Application.run`).
	How: `EmbeddedSession.open` raises it from the version check, and
	`GoReadonlyStore` raises it for the same refusal from the native facade.
	Only `SchemaSkewBoundary` catches it.
**/
@:goNative
class SchemaSkewAbort extends haxe.Exception {
	public final refusal:SchemaSkewRefusal;

	public function new(refusal:SchemaSkewRefusal) {
		super(schemaSkewRefusalError(refusal));
		this.refusal = refusal;
	}
}

/** The places where a command meets a schema skew refusal, as upstream's pre-run does. */
@:goNative
final class SchemaSkewBoundary {
	/**
		Runs `body`, the whole command. A refusal from any store open below it
		ends the command with `refused`, which prints it and gives the exit code.
	**/
	public static function runCommand(body:() -> Int, refused:SchemaSkewRefusal->Int):Int {
		return try body() catch (abort:SchemaSkewAbort) refused(abort.refusal);
	}

	/** Runs `body`, or gives `fallback` when a store open below it refuses: upstream's `where` ignores a store that does not open. */
	public static function orElse<T>(body:() -> T, fallback:T):T {
		return try body() catch (_:SchemaSkewAbort) fallback;
	}

	/** Upstream's pre-run for `--ignore-schema-skew`: `os.Setenv("BD_IGNORE_SCHEMA_SKEW", "1")`, which every later store open reads. */
	public static function ignoreForProcess():Void {
		Sys.putEnv("BD_IGNORE_SCHEMA_SKEW", "1");
	}
}

/** Upstream's `Error()` text of each refusal. */
function schemaSkewRefusalError(refusal:SchemaSkewRefusal):String {
	return switch refusal {
		case DatabaseAhead(database, binary):
			final delta = database - binary;
			'schema version mismatch: database is at v${database}, binary knows up to v${binary} (${delta} ${delta == 1 ? "migration" : "migrations"} ahead)';
		case DatabaseBehind(database, binary):
			'schema version mismatch: database is at v${database}, binary expects v${binary}, and the read-only open cannot migrate it; ' +
			"run any bd write command in that workspace to migrate, or set BD_IGNORE_SCHEMA_SKEW=1 to read anyway (queries touching newer schema may fail)";
		case SchemaCheckFailed(message):
			message;
	};
}

/** Upstream `SchemaSkewError.UserMessage`, which the pre-run prints on stderr for a database ahead of the binary. */
function schemaSkewUserMessage(databaseVersion:Int, binaryVersion:Int):String {
	return schemaSkewRefusalError(DatabaseAhead(databaseVersion, binaryVersion))
		+ "\n"
		+ "\n"
		+ "  Your bd binary is stale. Queries for dropped or renamed columns will fail\n"
		+ "  with cryptic SQL errors (e.g. \"column X could not be found in any table in scope\").\n"
		+ "\n"
		+ "  Rebuild from main:\n"
		+ "    CGO_ENABLED=0 go build -tags gms_pure_go ./cmd/bd\n"
		+ "\n"
		+ "  Or install the latest release:\n"
		+ "    CGO_ENABLED=0 go install -tags gms_pure_go github.com/steveyegge/beads/cmd/bd@latest\n"
		+ "\n"
		+ "  To proceed despite the risk (some read commands may still work):\n"
		+ "    BD_IGNORE_SCHEMA_SKEW=1 bd <command>\n"
		+ "    bd --ignore-schema-skew <command>\n";
}

/**
	Whether upstream's escape hatch is on: `BD_IGNORE_SCHEMA_SKEW` is exactly
	`1`. The `--ignore-schema-skew` flag sets it, as upstream's pre-run does.
**/
function ignoresSchemaSkew():Bool {
	return Sys.getEnv("BD_IGNORE_SCHEMA_SKEW") == "1";
}

/**
	Upstream `checkSchemaSkew` and `CheckBehindDrift` over one read of the
	schema_migrations cursor, as upstream's `openReadOnly` runs them, one after
	the other.

	Why: upstream reads the cursor twice with the same query. The two reads see
	the same database, so one read gives both answers. The forward check takes
	a missing table or no row as version 0 and passes; the behind check fails
	with that read error.
	What: null when the command may go on; with the escape hatch on, a drift
	only gives upstream's warning (`SchemaSkewWarning`). Otherwise the refusal.
**/
function checkSchemaCursor(cursor:SchemaCursorRead):Null<SchemaSkewRefusal> {
	final forwardVersion = switch cursor {
		case CursorVersion(version): version;
		case CursorTableMissing(_) | CursorNoRow: 0;
		case CursorReadFailed(error): return SchemaCheckFailed('schema skew check: reading schema_migrations version: ${error}');
		case CursorDatabaseMissing: return null;
	};
	if (forwardVersion != 0 && forwardVersion > BINARY_SCHEMA_VERSION) {
		if (!ignoresSchemaSkew())
			return DatabaseAhead(forwardVersion, BINARY_SCHEMA_VERSION);
		SchemaSkewWarning.hold('Warning: schema skew ignored — database (v${forwardVersion}) is ahead of binary (v${BINARY_SCHEMA_VERSION}); some queries may fail\n');
	}
	final behindVersion = switch cursor {
		case CursorVersion(version): version;
		case CursorNoRow: return SchemaCheckFailed("schema behind-drift check: sql: no rows in result set");
		case CursorTableMissing(error) | CursorReadFailed(error): return SchemaCheckFailed('schema behind-drift check: ${error}');
		case CursorDatabaseMissing: return null;
	};
	if (behindVersion >= BINARY_SCHEMA_VERSION)
		return null;
	if (!ignoresSchemaSkew())
		return DatabaseBehind(behindVersion, BINARY_SCHEMA_VERSION);
	SchemaSkewWarning.hold('Warning: schema skew ignored — database (v${behindVersion}) is behind binary (v${BINARY_SCHEMA_VERSION}) and was opened read-only; some queries may fail\n');
	return null;
}

/** One read of `SELECT COALESCE(MAX(version), 0) FROM schema_migrations`. */
enum SchemaCursorRead {
	CursorVersion(version:Int);

	/** The query returned no row; Go's `database/sql` reports `sql.ErrNoRows` for it. */
	CursorNoRow;

	/** The table does not exist (upstream `dberrors.IsTableNotExist`). `error` is the driver's text. */
	CursorTableMissing(error:String);

	CursorReadFailed(error:String);

	/**
		The session's database does not exist. Upstream's open fails at its
		``USE `db` `` before the check, so there is no check to make; the
		command's own first query reports the missing database.
	**/
	CursorDatabaseMissing;
}

/**
	The same refusal that the native read-only facade reports in upstream's own
	error text, or null for any other message.

	Why: the facade opens the store with upstream `OpenReadOnly`, which runs
	the same check and returns only the error text here. The pre-run would stop
	the command at that error, so this build must stop it the same way.
	What: the facade returns upstream's errors unwrapped, so a refusal is the
	whole message. A message is a drift only when this module prints it again
	exactly from the versions that it names.
**/
function facadeSchemaRefusal(message:String):Null<SchemaSkewRefusal> {
	if (StringTools.startsWith(message, "schema skew check: ") || StringTools.startsWith(message, "schema behind-drift check: "))
		return SchemaCheckFailed(message);
	final prefix = "schema version mismatch: database is at v";
	if (!StringTools.startsWith(message, prefix))
		return null;
	final database = leadingVersion(message, prefix.length);
	if (database == null)
		return null;
	for (marker in [", binary knows up to v", ", binary expects v"]) {
		final at = message.indexOf(marker);
		if (at < 0)
			continue;
		final binary = leadingVersion(message, at + marker.length);
		if (binary == null)
			return null;
		for (refusal in [DatabaseAhead(database, binary), DatabaseBehind(database, binary)])
			if (schemaSkewRefusalError(refusal) == message)
				return refusal;
		return null;
	}
	return null;
}

/** The integer that Go's `%d` printed at `start`, or null; the caller compares the whole message again. */
private function leadingVersion(text:String, start:Int):Null<Int> {
	var end = start < text.length && text.charAt(start) == "-" ? start + 1 : start;
	final digits = end;
	while (end < text.length && text.charCodeAt(end) >= "0".code && text.charCodeAt(end) <= "9".code)
		end++;
	if (end == digits || end - digits > 9)
		return null;
	return Std.parseInt(text.substring(start, end));
}

/**
	Whether this process has already checked the schema of the workspace at
	`beadsDir`.

	Why: upstream checks once, when the pre-run opens the command's store, and
	its later connections do not check again. Each read here opens its own
	session, so the first one checks, and the rest skip the check: they cost no
	query, and the escape hatch warns once. A refusal is not recorded: it stops
	the command, and `where`, which goes on without the stored prefix, reads no
	more.
**/
@:goNative
final class SchemaSkewChecks {
	static final checked = new Map<String, Bool>();

	public static function isChecked(beadsDir:String):Bool {
		return checked.exists(beadsDir);
	}

	/** Records a check of `beadsDir` that let the command go on. */
	public static function markChecked(beadsDir:String):Void {
		checked.set(beadsDir, true);
	}
}

/**
	Upstream's escape-hatch warning from the embedded schema check, held until
	the command writes its next output.

	Why: upstream warns once, at the store open of the pre-run. Here the first
	embedded read checks, and the native facade, which opens the store with
	upstream `OpenReadOnly`, warns again by itself. `show` reads through both.
	What: the check holds the warning; the next output of the command writes it
	first (`SchemaSkewWarningOutput`), unless a facade store open printed the
	same warning in the meantime.
**/
@:goNative
final class SchemaSkewWarning {
	static var held:Null<String> = null;

	public static function hold(warning:String):Void {
		held = warning;
	}

	/** The native facade's store open printed the same warning itself. */
	public static function drop():Void {
		held = null;
	}

	/** The held warning, which the caller now writes, or null. */
	public static function take():Null<String> {
		final warning = held;
		held = null;
		return warning;
	}
}
