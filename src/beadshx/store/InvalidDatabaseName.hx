package beadshx.store;

import beadshx.nativeextern.strconv.StrconvPkg;

/** Where upstream embeddeddolt refuses a database name that is not an identifier. Each step has its own words. */
enum InvalidDatabaseNameStep {
	/** `OpenSQL` (open.go): `invalid database name: %q`, with the hyphen hint. */
	OpenSqlName;

	/**
		`newStore` (store.go), which every open that may create the database
		runs: `embeddeddolt: init schema: ` before initSchema's
		`embeddeddolt: invalid database name: %q` and the hyphen hint.
	**/
	InitSchemaName;

	/** `openReadOnly` (store.go), the strict read-only open: `embeddeddolt: invalid database name: %q`, without the hint. */
	ReadOnlyOpenName;
}

/**
	Upstream embeddeddolt's refusal of a database name that is not an
	identifier (`isEmbeddedDatabaseIdentifier`).

	Why: upstream refuses such a name in three places, and the command prints
	the words of the first one that it meets. What: those words for one step.
	How: the name is quoted as Go's `%q` quotes it, and a name with a hyphen
	gets upstream's hint except at the strict read-only open.
**/
@:goNative
final class InvalidDatabaseName {
	static final HYPHEN_HINT = "; hyphens are not allowed in embedded mode — replace with underscores in .beads/metadata.json dolt_database field, or run 'bd doctor'";

	/** Upstream's error at `step` for `name`. */
	public static function error(name:String, step:InvalidDatabaseNameStep):String {
		final words = 'invalid database name: ${StrconvPkg.quote(name)}';
		final hint = name.indexOf("-") >= 0 ? HYPHEN_HINT : "";
		return switch step {
			case OpenSqlName: words + hint;
			case InitSchemaName: 'embeddeddolt: init schema: embeddeddolt: ${words}${hint}';
			case ReadOnlyOpenName: 'embeddeddolt: ${words}';
		};
	}
}
