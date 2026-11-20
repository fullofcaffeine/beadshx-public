package beadshx.config;

import beadshx.cli.CatalogViews.field;
import beadshx.cli.CatalogViews.renderCatalogJson;
import beadshx.store.CustomConfig.goTrimSpace;
import haxe.io.Bytes;

/** What upstream's validators ask of one config.yaml, read by a private Viper registry without defaults or environment. */
typedef ValidationYaml = {
	final isSet:String->Bool;
	final getString:String->String;
	final getStringSlice:String->Array<String>;
}

/** Go's os.Stat for one path, as upstream's validators classify it. */
enum PathStat {
	StatDirectory;
	StatNotDirectory;

	/** os.IsNotExist holds for the error. */
	StatMissing;

	/** Any other error, with its text. */
	StatFailed(message:String);
}

/** net/url.Parse: the parsed host and path, or the error text. */
enum ParsedUrl {
	UrlParts(host:String, path:String);
	UrlMalformed(message:String);
}

/**
	The native answers upstream's validators need, passed in so the rules stay
	plain Haxe: os.Stat, its `~` expansion (os.UserHomeDir and filepath.Join),
	Go's `%q`, net/url.Parse and path.Match (an invalid pattern matches nothing).
**/
typedef ValidationHost = {
	final stat:String->PathStat;
	final expandHome:String->String;
	final quote:String->String;
	final parseUrl:String->ParsedUrl;
	final matchPattern:(pattern:String, name:String) -> Bool;
}

/** Upstream's routing modes. It lists them from a Go map, in random order; this build prints them in this order. */
private final ROUTING_MODES = ["auto", "maintainer", "contributor", "explicit"];

private final BOOLEAN_KEYS = ["json", "no-db", "sync.require_confirmation_on_mass_delete"];
private final ROUTING_PATH_KEYS = ["routing.default", "routing.maintainer", "routing.contributor"];

/** Upstream remotecache.allowedSchemes. */
private final ALLOWED_SCHEMES = [
	"dolthub",
	"gs",
	"s3",
	"aws",
	"az",
	"oci",
	"file",
	"https",
	"http",
	"ssh",
	"git",
	"git+ssh",
	"git+https",
	"git+http",
	"git+file"
];

/** Upstream sortedSchemes, its display order. */
private final DISPLAYED_SCHEMES = "dolthub, https, http, ssh, git, git+ssh, git+https, git+http, git+file, s3, aws, gs, az, oci, file";

private final BOOLEAN_WORDS = ["true", "false", "yes", "no", "1", "0", "on", "off", "t", "f", "y", "n"];

/**
	Upstream doctor checkYAMLConfigValues, after the file parsed: issue-prefix,
	routing.mode and its auto-routing targets, the routing paths, actor, db, the
	boolean keys and the repos paths, in upstream's order. Relative paths are
	checked from the current directory, as upstream's os.Stat does.
**/
function yamlConfigIssues(yaml:ValidationYaml, host:ValidationHost):Array<String> {
	final issues = new Array<String>();
	final q = host.quote;
	if (yaml.isSet("issue-prefix")) {
		final prefix = yaml.getString("issue-prefix");
		if (prefix != "") {
			if (Bytes.ofString(prefix).length > 20)
				issues.push('issue-prefix: ${q(prefix)} is too long (max 20 characters)');
			if (!isIssuePrefixName(prefix))
				issues.push('issue-prefix: ${q(prefix)} is invalid (must start with letter, contain only letters, numbers, dashes, underscores)');
		}
	}
	if (yaml.isSet("routing.mode")) {
		final mode = yaml.getString("routing.mode");
		if (mode != "" && !ROUTING_MODES.contains(mode))
			issues.push('routing.mode: ${q(mode)} is invalid (valid values: ${ROUTING_MODES.join(", ")})');
		if (mode == "auto")
			for (issue in autoRoutingIssues(yaml, host))
				issues.push(issue);
	}
	for (key in ROUTING_PATH_KEYS)
		if (yaml.isSet(key)) {
			final path = yaml.getString(key);
			if (path != "" && path != "." && isMissing(host.stat(host.expandHome(path))))
				issues.push('${key}: path ${q(path)} does not exist');
		}
	if (yaml.isSet("actor")) {
		final actor = yaml.getString("actor");
		if (actor != "" && !isActorName(actor))
			issues.push('actor: ${q(actor)} is invalid (must start with letter/number, contain only letters, numbers, dashes, underscores, dots, or @)');
	}
	if (yaml.isSet("db")) {
		final database = yaml.getString("db");
		if (database.indexOf("\x00") >= 0)
			issues.push('db: ${q(database)} contains invalid characters');
	}
	for (key in BOOLEAN_KEYS)
		if (yaml.isSet(key)) {
			final value = yaml.getString(key);
			if (value != "" && !isBooleanWord(value))
				issues.push('${key}: ${q(value)} is not a valid boolean value (expected true/false, yes/no, 1/0, on/off)');
		}
	if (yaml.isSet("repos.primary")) {
		final primary = yaml.getString("repos.primary");
		if (primary != "")
			switch host.stat(host.expandHome(primary)) {
				case StatNotDirectory:
					issues.push('repos.primary: ${q(primary)} is not a directory');
				case StatFailed(message):
					issues.push('repos.primary: cannot access ${q(primary)}: ${message}');
				case StatDirectory | StatMissing:
			}
	}
	if (yaml.isSet("repos.additional"))
		for (path in yaml.getStringSlice("repos.additional"))
			if (path != "" && isNotDirectory(host.stat(host.expandHome(path))))
				issues.push('repos.additional: ${q(path)} is not a directory');
	return issues;
}

private function isMissing(stat:PathStat):Bool {
	return switch stat {
		case StatMissing: true;
		case StatDirectory | StatNotDirectory | StatFailed(_): false;
	};
}

private function isNotDirectory(stat:PathStat):Bool {
	return switch stat {
		case StatNotDirectory: true;
		case StatDirectory | StatMissing | StatFailed(_): false;
	};
}

/** Upstream's routing and hydration consistency check for routing.mode=auto. */
private function autoRoutingIssues(yaml:ValidationYaml, host:ValidationHost):Array<String> {
	final contributor = yaml.getString("routing.contributor");
	final maintainer = yaml.getString("routing.maintainer");
	final hasTargets = (contributor != "" && contributor != ".") || (maintainer != "" && maintainer != ".");
	if (!hasTargets)
		return [];
	final additional = yaml.getStringSlice("repos.additional");
	if (additional.length == 0)
		return [
			"routing.mode=auto with routing targets but repos.additional not configured. " + "Issues created via routing will not be visible in bd list. " +
			"Run 'bd repo add <routing-target>' to enable hydration."
		];
	final hydrated = [for (path in additional) host.expandHome(path)];
	final issues = new Array<String>();
	final q = host.quote;
	if (contributor != "" && !hydrated.contains(host.expandHome(contributor)))
		issues.push('routing.contributor=${q(contributor)} is not in repos.additional. Run \'bd repo add ${contributor}\' to make routed issues visible.');
	if (maintainer != "" && maintainer != "." && !hydrated.contains(host.expandHome(maintainer)))
		issues.push('routing.maintainer=${q(maintainer)} is not in repos.additional. Run \'bd repo add ${maintainer}\' to make routed issues visible.');
	return issues;
}

/** The metadata.json fields upstream's checks read; an absent int field is 0. */
typedef MetadataFacts = {
	final database:String;
	final doltDatabase:String;
	final deletionsRetentionDays:String;
}

/**
	Upstream doctor checkMetadataConfigValues for a Dolt workspace that is not in
	server mode: the database file name, the embedded dolt_database name and the
	retention days. Null facts mean no metadata.json.
**/
function metadataConfigIssues(facts:Null<MetadataFacts>, quote:String->String):Array<String> {
	final issues = new Array<String>();
	if (facts == null)
		return issues;
	final database = facts.database;
	if (database != "") {
		if (database.indexOf("/") >= 0)
			issues.push('metadata.json database: ${quote(database)} should be a filename, not a path');
		if (StringTools.endsWith(database, ".db")
			|| StringTools.endsWith(database, ".sqlite")
			|| StringTools.endsWith(database, ".sqlite3"))
			issues.push('metadata.json database: ${quote(database)} looks like a SQLite file, but backend is dolt (expected a directory like ${quote("dolt")})');
		if (database == "beads.db")
			issues.push('metadata.json database: ${quote(database)} is misleading for dolt backend (expected ${quote("dolt")})');
	}
	final doltDatabase = facts.doltDatabase;
	if (doltDatabase != "") {
		final sanitized = StringTools.replace(StringTools.replace(doltDatabase, "-", "_"), ".", "_");
		if (sanitized != doltDatabase)
			issues.push('metadata.json dolt_database: ${quote(doltDatabase)} contains characters invalid in embedded mode — '
				+ 'replace with ${quote(sanitized)} or set dolt_mode to "server" (GH#3231)');
	}
	final days = facts.deletionsRetentionDays;
	if (StringTools.startsWith(days, "-") && days != "-0")
		issues.push('metadata.json deletions_retention_days: ${days} is invalid (must be >= 0)');
	return issues;
}

/**
	Upstream validateSyncConfig for a project config.yaml that parsed:
	federation.sovereignty, then federation.remote's presence, its URL and the
	allowed-remote-patterns list. A URL that fails the structural check also
	fails the pattern check, so upstream reports that problem twice.
**/
function syncConfigIssues(yaml:ValidationYaml, host:ValidationHost):Array<String> {
	final issues = new Array<String>();
	final sovereignty = yaml.getString("federation.sovereignty");
	final remote = yaml.getString("federation.remote");
	if (sovereignty != "" && !isValidSovereignty(sovereignty))
		issues.push('federation.sovereignty: ${host.quote(sovereignty)} is invalid (valid values: T1, T2, T3, T4, or empty for no restriction)');
	if (remote == "") {
		issues.push("federation.remote: required for Dolt sync");
		return issues;
	}
	final problem = remoteUrlProblem(remote, host);
	if (problem != null)
		issues.push('federation.remote: ${problem}');
	final patterns = yaml.getStringSlice("federation.allowed-remote-patterns");
	if (patterns.length > 0) {
		var patternProblem = problem;
		if (patternProblem == null) {
			patternProblem = 'remote URL ${host.quote(remote)} does not match any allowed pattern';
			for (pattern in patterns)
				if (host.matchPattern(pattern, remote))
					patternProblem = null;
		}
		if (patternProblem != null)
			issues.push('federation.remote: ${patternProblem}');
	}
	return issues;
}

/** Upstream config.IsValidSovereignty for a non-empty value. */
private function isValidSovereignty(value:String):Bool {
	return ["T1", "T2", "T3", "T4"].contains(goTrimSpace(value).toUpperCase());
}

/**
	Upstream remotecache.ValidateRemoteURL for a non-empty URL: no control
	characters, no leading dash, then an SCP-style address or a URL whose scheme
	is allowed and whose parts fit that scheme. Null when the URL passes.
**/
function remoteUrlProblem(raw:String, host:ValidationHost):Null<String> {
	// Control characters are single bytes in UTF-8, so the first one's byte offset is Go's range index.
	final bytes = Bytes.ofString(raw);
	for (index in 0...bytes.length) {
		final byte = bytes.get(index);
		if (byte < 0x20 || byte == 0x7f)
			return 'remote URL contains control character at position ${index} (0x${StringTools.hex(byte, 2).toLowerCase()})';
	}
	if (StringTools.startsWith(raw, "-"))
		return "remote URL must not start with a dash";
	if (isScpAddress(raw))
		return null;
	final separator = raw.indexOf("://");
	final scheme = separator > 0 ? raw.substr(0, separator) : "";
	if (scheme == "")
		return 'remote URL has no scheme (expected one of: ${DISPLAYED_SCHEMES})';
	if (!ALLOWED_SCHEMES.contains(scheme))
		return 'remote URL scheme ${host.quote(scheme)} is not allowed (expected one of: ${DISPLAYED_SCHEMES})';
	// net/url does not take git+ssh:// and the like, so upstream parses those under a placeholder scheme.
	final normalized = StringTools.startsWith(scheme, "git+") ? "placeholder://" + raw.substr(separator + 3) : raw;
	return switch host.parseUrl(normalized) {
		case UrlMalformed(message): 'remote URL is malformed: ${message}';
		case UrlParts(urlHost, path): schemeProblem(scheme, urlHost, path);
	};
}

/** Upstream's per-scheme structural checks. */
private function schemeProblem(scheme:String, urlHost:String, path:String):Null<String> {
	switch scheme {
		case "dolthub":
			final trimmedPath = StringTools.startsWith(path, "/") ? path.substr(1) : path;
			final combined = trimmedPath != "" ? urlHost + "/" + trimmedPath : urlHost;
			final parts = combined.split("/");
			if (parts.length < 2 || parts[0] == "" || parts[1] == "")
				return "dolthub:// URL must have org/repo format (e.g., dolthub://myorg/myrepo)";
		case "https" | "http" | "git+https" | "git+http" | "ssh" | "git" | "git+ssh":
			if (urlHost == "")
				return '${scheme}:// URL must include a hostname';
		case "s3" | "aws" | "gs":
			if (urlHost == "")
				return '${scheme}:// URL must include a bucket name';
		case "az":
			if (urlHost == "")
				return "az:// URL must include a storage account hostname";
		case "oci":
			if (urlHost == "")
				return "oci:// URL must include a namespace or bucket host";
		case _:
	}
	return null;
}

/**
	Upstream gitSSHPattern, `^[a-zA-Z0-9._-]+@[a-zA-Z0-9][a-zA-Z0-9._-]*:[^\x00-\x1f\x7f]+$`.
	Neither name class holds `@` or `:`, so the first of each ends its part; the
	caller has already refused control characters, so the path need only be
	non-empty.
**/
private function isScpAddress(raw:String):Bool {
	final at = raw.indexOf("@");
	if (at <= 0)
		return false;
	final colon = raw.indexOf(":", at);
	if (colon < 0 || colon == at + 1 || colon == raw.length - 1)
		return false;
	final user = raw.substring(0, at);
	final host = raw.substring(at + 1, colon);
	return allBytes(user, isUserNameByte) && isAsciiAlphanumeric(host.charCodeAt(0)) && allBytes(host.substr(1), isUserNameByte);
}

/** `^[a-zA-Z][a-zA-Z0-9_-]*$` */
private function isIssuePrefixName(value:String):Bool {
	return isAsciiLetter(value.charCodeAt(0))
		&& allBytes(value.substr(1), code -> isAsciiAlphanumeric(code) || code == "_".code || code == "-".code);
}

/** `^[a-zA-Z0-9][a-zA-Z0-9._@-]*$` */
private function isActorName(value:String):Bool {
	return isAsciiAlphanumeric(value.charCodeAt(0))
		&& allBytes(value.substr(1), code -> isAsciiAlphanumeric(code) || code == ".".code || code == "_".code || code == "@".code || code == "-".code);
}

private function isUserNameByte(code:Int):Bool {
	return isAsciiAlphanumeric(code) || code == ".".code || code == "_".code || code == "-".code;
}

/** Upstream isValidBoolString: the trimmed, lower-cased value is a boolean word strconv.ParseBool also accepts. */
private function isBooleanWord(value:String):Bool {
	return BOOLEAN_WORDS.contains(goTrimSpace(value).toLowerCase());
}

/** Every UTF-8 byte of the text passes; a non-ASCII rune never passes the ASCII classes these patterns use. */
private function allBytes(text:String, accepts:Int->Bool):Bool {
	final bytes = Bytes.ofString(text);
	for (index in 0...bytes.length)
		if (!accepts(bytes.get(index)))
			return false;
	return true;
}

private function isAsciiLetter(code:Null<Int>):Bool {
	return code != null && ((code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code));
}

private function isAsciiAlphanumeric(code:Null<Int>):Bool {
	return code != null && (isAsciiLetter(code) || (code >= "0".code && code <= "9".code));
}

/**
	Upstream configValidateCmd's list: the doctor checks joined with newlines and
	split again, so an issue that holds newlines becomes several entries, then
	the sync issues.
**/
function validationIssues(doctorIssues:Array<String>, syncIssues:Array<String>):Array<String> {
	final issues = doctorIssues.length == 0 ? [] : doctorIssues.join("\n").split("\n");
	return issues.concat(syncIssues);
}

/** Upstream configValidateCmd text; it leaves out empty entries. */
function renderValidationText(issues:Array<String>):String {
	if (issues.length == 0)
		return "✓ All sync-related configuration is valid\n";
	final rendered = new StringBuf();
	rendered.add("Configuration validation found issues:\n");
	for (issue in issues)
		if (issue != "")
			rendered.add('  • ${issue}\n');
	rendered.add("\nRun 'bd config set <key> <value>' to fix configuration issues.\n");
	return rendered.toString();
}

/** Upstream configValidateCmd JSON: a Go map, so the keys print sorted, with schema_version added. */
function renderValidationJson(issues:Array<String>):String {
	return renderCatalogJson(JsonObject([
		field("issues", JsonList([for (issue in issues) JsonText(issue)])),
		field("schema_version", JsonNumber("1")),
		field("valid", JsonNumber(issues.length == 0 ? "true" : "false"))
	]));
}
