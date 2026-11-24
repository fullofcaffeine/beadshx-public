import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.cli.ConfigView.renderBackupEnabledJson;
import beadshx.cli.ConfigView.renderBackupEnabledText;
import beadshx.cli.ConfigView.renderConfigGetJson;
import beadshx.cli.ConfigView.renderConfigGetText;
import beadshx.cli.ConfigView.renderConfigListJson;
import beadshx.cli.ConfigView.renderConfigListText;
import beadshx.cli.ConfigView.renderConfigShowJson;
import beadshx.cli.ConfigView.renderConfigShowText;
import beadshx.config.BeadsDirPermissions.beadsDirPermissionWarning;
import beadshx.config.ConfigShow.ConfigShowEntry;
import beadshx.config.ConfigShow.filterConfigShowEntries;
import beadshx.config.ConfigShow.layeredEntries;
import beadshx.config.ConfigShow.METADATA_CONFIG;
import beadshx.config.ConfigShow.metadataEntries;
import beadshx.config.ConfigShow.metadataLoadFailure;
import beadshx.config.ConfigShow.metadataLoadWarning;
import beadshx.config.ConfigShow.sortConfigShowEntries;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.config.ConfigKeys.configSourceName;
import beadshx.config.ConfigKeys.environmentNames;
import beadshx.config.ConfigKeys.isConfigContainerKey;
import beadshx.config.ConfigKeys.isKvPlaneKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.config.ConfigKeys.isYamlOnlyKey;
import beadshx.config.ConfigDrift.DriftItem;
import beadshx.config.ConfigDrift.hasDrift;
import beadshx.config.ConfigDrift.hookStatus;
import beadshx.config.ConfigDrift.hookVersion;
import beadshx.config.ConfigDrift.hooksDriftItems;
import beadshx.config.ConfigDrift.isFalsyBool;
import beadshx.config.ConfigDrift.plainItem;
import beadshx.config.ConfigDrift.remoteOpenFailureItem;
import beadshx.config.ConfigDrift.renderDriftJson;
import beadshx.config.ConfigDrift.renderDriftText;
import beadshx.config.ConfigDrift.serverDriftItem;
import beadshx.config.ConfigDrift.testDatabaseRefusal;
import beadshx.config.ConfigDrift.unreachableServerMessage;
import beadshx.config.ConfigValidate.ParsedUrl;
import beadshx.config.ConfigValidate.PathStat;
import beadshx.config.ConfigValidate.ValidationHost;
import beadshx.config.ConfigValidate.ValidationYaml;
import beadshx.config.ConfigValidate.metadataConfigIssues;
import beadshx.config.ConfigValidate.remoteUrlProblem;
import beadshx.config.ConfigValidate.renderValidationJson;
import beadshx.config.ConfigValidate.renderValidationText;
import beadshx.config.ConfigValidate.syncConfigIssues;
import beadshx.config.ConfigValidate.validationIssues;
import beadshx.config.ConfigValidate.yamlConfigIssues;
import beadshx.store.DoltDirectoryName;
import beadshx.store.EmbeddedDatabaseLookup.MissingDatabaseEntry;
import beadshx.store.EmbeddedDatabaseLookup.configuredEmbeddedDatabase;
import beadshx.store.EmbeddedDatabaseLookup.embeddedDatabaseExists;
import beadshx.store.EmbeddedDatabaseLookup.isEmbeddedDatabaseIdentifier;
import beadshx.store.EmbeddedDatabaseLookup.missingDatabaseEntry;
import beadshx.store.EmbeddedDatabaseLookup.redirectSourceDatabase;
import beadshx.store.JsonValue.GoJsonDecode;
import beadshx.store.JsonValue.decodeGoStruct;
import sys.FileSystem;
import sys.io.File;

/**
	Pins `bd config get`, `bd config list` and `bd config show` key routing and
	rendering against upstream config.IsYamlOnlyKey, IsUserGlobalKey,
	EnvVarName, showConfigYAMLOverrides, collectViperEntries,
	collectMetadataEntries and printConfigEntries, and the `bd config validate`
	and `bd config drift` rules against upstream's doctor checks,
	validateSyncConfig, ValidateRemoteURL, getHookVersion, checkHooksDrift and
	printDriftItems, and the warning of CheckBeadsDirPermissions, by hand. Viper,
	os.Stat, net/url, git and the server dial are native; parity covers the
	real runs.
**/
class Main {
	static function main():Void {
		keyContracts();
		getContracts();
		listContracts();
		showLayeredContracts();
		showMetadataContracts();
		metadataLoadContracts();
		embeddedDatabaseContracts();
		showRenderContracts();
		validateYamlContracts();
		validateMetadataContracts();
		validateSyncContracts();
		validateRenderContracts();
		driftHookContracts();
		driftRenderContracts();
		permissionContracts();
		Sys.println("config Haxe contracts: PASS");
	}

	static function keyContracts():Void {
		// Exact startup keys and secrets, and whole namespaces, live in config.yaml.
		for (key in [
			"json",
			"actor",
			"node_id",
			"jira.api_token",
			"ado.pat",
			"sync.remote",
			"export.auto",
			"dolt.anything",
			"storage-class.event"
		])
			equal(isYamlOnlyKey(key), true);
		// Database keys: no dot-namespace match, and a namespace needs its dot.
		for (key in [
			"issue_prefix",
			"jira.url",
			"custom.api_token",
			"routing",
			"exports.auto",
			"status.custom",
			"beads.role",
			"kv.x"
		])
			equal(isYamlOnlyKey(key), false);
		equal(isUserGlobalKey("metrics.disabled"), true);
		equal(isUserGlobalKey("node_id"), true);
		equal(isUserGlobalKey("metrics"), false);
		equal(isKvPlaneKey("kv.memory.x"), true);
		equal(isKvPlaneKey("kvetch"), false);
		equal(environmentNames("events-journal.retain-days").join("|"), "BD_EVENTS_JOURNAL_RETAIN_DAYS|BEADS_EVENTS_JOURNAL_RETAIN_DAYS");
		equal(environmentNames("Zeta.Upper").join("|"), "BD_ZETA_UPPER|BEADS_ZETA_UPPER");
		equal(configSourceName(EnvironmentSource), "env_var");
		equal(configSourceName(ConfigFileSource), "config_file");
		equal(configSourceName(DefaultSource), "default");
	}

	static function getContracts():Void {
		equal(renderConfigGetText("issue_prefix", "test", null), "test\n");
		// An empty stored value reads as not set, like a missing one.
		equal(renderConfigGetText("custom.empty", "", null), "custom.empty (not set)\n");
		equal(renderConfigGetText("export.path", "", "config.yaml"), "export.path (not set in config.yaml)\n");
		equal(renderConfigGetJson("k", "v", null), '{\n  "key": "k",\n  "schema_version": 1,\n  "value": "v"\n}\n');
		equal(renderConfigGetJson("k", "", "git config"), '{\n  "key": "k",\n  "location": "git config",\n  "schema_version": 1,\n  "value": ""\n}\n');
		equal(renderBackupEnabledText(false, "env var"), "false (env var)\n");
		equal(renderBackupEnabledJson(true, ConfigFileSource),
			'{\n  "effective": true,\n  "key": "backup.enabled",\n  "schema_version": 1,\n  "source": "config_file",\n  "value": true\n}\n');
	}

	static function listContracts():Void {
		// Go's json map encoding sorts every key in byte order, schema_version among them.
		equal(renderConfigListJson([{key: "z", value: "1"}, {key: "Z", value: "2"}, {key: "t", value: "3"}]),
			'{\n  "Z": "2",\n  "schema_version": 1,\n  "t": "3",\n  "z": "1"\n}\n');
		equal(renderConfigListJson([]), '{\n  "schema_version": 1\n}\n');
		equal(renderConfigListText([], ["actor"], key -> facts("", "", DefaultSource, ""), quote), "No configuration set\n");
		final known = [
			"issue_prefix" => facts("BD_ISSUE_PREFIX", "zzz", EnvironmentSource, "zzz"),
			"same" => facts("BD_SAME", "v", EnvironmentSource, "v"),
			"actor" => facts("BEADS_ACTOR", "fixture", EnvironmentSource, ""),
			"export.auto" => facts("", "", ConfigFileSource, "true"),
			"export.path" => facts("", "", ConfigFileSource, ""),
			"routing.default" => facts("", "", DefaultSource, "."),
			"jira.url" => facts("", "", ConfigFileSource, "https://jira.example.invalid")
		];
		final text = renderConfigListText([{key: "same", value: "v"}, {key: "issue_prefix", value: "test"}], [
			"routing.default",
			"export.path",
			"export.auto",
			"jira.url",
			"actor",
			"issue_prefix",
			"same"
		],
			key -> known.exists(key) ? known.get(key) : facts("", "", DefaultSource, ""), quote);
		// Stored rows sort; only YAML-only keys set in a file and not stored print; env notes sort.
		equal(text, [
			"",
			"Configuration:",
			"  issue_prefix = test",
			"  same = v",
			"",
			"Also set in config.yaml (not shown above):",
			"  export.auto = true",
			"",
			"⚠ Environment variable overrides detected:",
			"  actor: env BEADS_ACTOR=<fixture> overrides config",
			"  issue_prefix: DB has <test>, but env BD_ISSUE_PREFIX=<zzz> takes precedence",
			"",
			"Tip: Run 'bd config show' for all effective config with provenance.",
			""
		].join("\n"));
	}

	static function showLayeredContracts():Void {
		equal(isConfigContainerKey("directory.labels"), true);
		equal(isConfigContainerKey("directory.labels.frontend"), false);
		equal(isConfigContainerKey("repos"), true);
		final known = [
			"actor" => facts("BD_ACTOR", "bd-fixture", EnvironmentSource, "bd-fixture"),
			"routing.mode" => facts("BEADS_ROUTING_MODE", "legacy", EnvironmentSource, "Maintainer"),
			"export.path" => facts("", "", ConfigFileSource, ""),
			"routing.default" => facts("", "", DefaultSource, "."),
			"identity" => facts("", "", DefaultSource, ""),
			"node_id" => facts("BEADS_NODE_ID", "fake-node", EnvironmentSource, "fake-node"),
			"metrics.endpoint" => facts("", "", DefaultSource, "https://metrics.example.invalid"),
			"repos" => facts("", "", ConfigFileSource, "")
		];
		final keys = [
			"routing.mode",
			"actor",
			"export.path",
			"routing.default",
			"identity",
			"node_id",
			"metrics.endpoint",
			"repos",
			"actor"
		];
		final lookup = key -> known.get(key);
		// Unset defaults, user-global keys, map containers and repeats drop out; a set empty value stays.
		equal(render(layeredEntries(keys, lookup, "")),
			"routing.mode=Maintainer(env: BEADS_ROUTING_MODE)|actor=bd-fixture(env: BD_ACTOR)|export.path=(config.yaml)|routing.default=.(default)");
		// A non-empty BEADS_ACTOR replaces the actor value and its label.
		equal(render(layeredEntries(["actor"], lookup, "fixture")), "actor=fixture(env: BEADS_ACTOR)");
		equal(render(layeredEntries(["actor"], key -> facts("", "", DefaultSource, ""), "fixture")), "actor=fixture(env: BEADS_ACTOR)");
		equal(render(layeredEntries(["actor"], key -> facts("", "", DefaultSource, ""), "")), "");
	}

	static function showMetadataContracts():Void {
		equal(render(metadataEntries('{"database":"dolt","backend":"dolt","dolt_mode":"embedded","dolt_database":"test","project_id":"p-1"}')),
			"dolt_mode=embedded(metadata)|dolt_database=test(metadata)|project_id=p-1(metadata)");
		// Upstream's order, not the file's; zero values and nulls drop out; ints print in decimal.
		equal(render(metadataEntries('{"stale_closed_issues_days":-5,"dolt_server_tls":true,"dolt_server_port":3307,'
			+ '"deletions_retention_days":0,"dolt_server_host":"","dolt_server_user":null,"dolt_remotesapi_port":-0}')),
			"dolt_server_port=3307(metadata)|dolt_server_tls=true(metadata)|stale_closed_issues_days=-5(metadata)");
		// encoding/json matches keys under its case folding, where ſ and the Kelvin sign fold into
		// ASCII but the dotless ı and the dotted İ do not; the last matching member wins.
		equal(render(metadataEntries('{"Project_ID":"a","DOLT_MODE":"server","dolt_mode":"embedded","project_ıd":"b","dolt_data_dİr":"/x",'
			+ '"ſtale_closed_issues_days":9}')),
			"dolt_mode=embedded(metadata)|project_id=a(metadata)|stale_closed_issues_days=9(metadata)");
		equal(metadataEntries('{"bac\u212Aend":1}'), null);
		equal(render(metadataEntries('{"project_ıd":1,"dolt_data_dİr":true}')), "");
		equal(render(metadataEntries('{"dolt_mode":"server","DOLT_MODE":"embedded"}')), "dolt_mode=embedded(metadata)");
		// Unknown members of any type are ignored; a JSON null document decodes to nothing.
		equal(render(metadataEntries('{"extra":{"x":[1,2]},"dolt_mode":"embedded"}')), "dolt_mode=embedded(metadata)");
		equal(render(metadataEntries(" null ")), "");
		equal(render(metadataEntries("{}")), "");
		equal(render(metadataEntries('{"dolt_server_port":9223372036854775807}')), "dolt_server_port=9223372036854775807(metadata)");
		// Any decode error rejects the whole file, even in a field upstream does not list.
		for (raw in [
			'{"dolt_server_port":9223372036854775808}',
			'{"dolt_server_port":-9223372036854775809}',
			'{"dolt_server_port":1.0}',
			'{"dolt_server_port":1e3}',
			'{"dolt_server_port":"3307"}',
			'{"dolt_server_tls":"true"}',
			'{"dolt_mode":1}',
			'{"backend":false}',
			'{"dolt_team_server":1}',
			'{"dolt_mode":"embedded","dolt_mode":2}',
			'[]',
			'"metadata"',
			'{"dolt_mode":"embedded"',
			'{"dolt_mode":"embedded"} x',
			'\u000C{}'
		])
			equal(metadataEntries(raw), null);
	}

	/**
		json.Unmarshal's error texts for configfile.Config, as upstream's oracle
		prints them, and the pre-run warning and error built from them. Syntax
		errors come from Go's own scanner, which the interpreter does not have.
	**/
	static function metadataLoadContracts():Void {
		final field = "json: cannot unmarshal ";
		equal(decodeError('{"database":7}'), field + "number into Go struct field Config.database of type string");
		equal(decodeError('{"deletions_retention_days":"7"}'), field + "string into Go struct field Config.deletions_retention_days of type int");
		equal(decodeError('{"dolt_server_tls":"yes"}'), field + "string into Go struct field Config.dolt_server_tls of type bool");
		equal(decodeError('{"dolt_server_tls":1}'), field + "number into Go struct field Config.dolt_server_tls of type bool");
		equal(decodeError('{"database":true}'), field + "bool into Go struct field Config.database of type string");
		equal(decodeError('{"database":{"a":1}}'), field + "object into Go struct field Config.database of type string");
		equal(decodeError('{"dolt_server_port":[1]}'), field + "array into Go struct field Config.dolt_server_port of type int");
		// An int that strconv.ParseInt rejects names the number as written.
		equal(decodeError('{"dolt_server_port":1.5}'), field + "number 1.5 into Go struct field Config.dolt_server_port of type int");
		equal(decodeError('{"dolt_server_port":1e3}'), field + "number 1e3 into Go struct field Config.dolt_server_port of type int");
		equal(decodeError('{"dolt_server_port":9223372036854775808}'),
			field + "number 9223372036854775808 into Go struct field Config.dolt_server_port of type int");
		// The field is named by its tag, whatever the key's case.
		equal(decodeError('{"DOLT_DATABASE":7}'), field + "number into Go struct field Config.dolt_database of type string");
		// The first mismatch wins, even when a later duplicate fits.
		equal(decodeError('{"backend":1,"database":2}'), field + "number into Go struct field Config.backend of type string");
		equal(decodeError('{"dolt_database":7,"dolt_database":"test"}'), field + "number into Go struct field Config.dolt_database of type string");
		equal(decodeError('{"dolt_database":"test","dolt_database":7}'), field + "number into Go struct field Config.dolt_database of type string");
		// A top level that is not an object or null names the Go type.
		equal(decodeError("[1,2]"), field + "array into Go value of type configfile.Config");
		equal(decodeError('"text"'), field + "string into Go value of type configfile.Config");
		equal(decodeError("42"), field + "number into Go value of type configfile.Config");
		equal(decodeError("true"), field + "bool into Go value of type configfile.Config");
		// Unknown members, null members and a null document decode; the last duplicate wins.
		equal(decodeError('{"unknown":{"x":[1,{"y":null}]},"dolt_mode":null}'), "");
		equal(decodeError("null"), "");
		equal(switch decodeGoStruct('{"dolt_database":"other","dolt_database":"test"}', METADATA_CONFIG) {
			case GoJsonDecoded(fields): fields.get("dolt_database");
			case GoJsonFailed(_) | GoJsonUnsupported: "<failed>";
		}, "test");
		// Without Go's scanner the interpreter cannot name a syntax error.
		equal(decodeGoStruct('{"database":', METADATA_CONFIG), GoJsonUnsupported);
		final error = "parsing config: " + field + "number into Go struct field Config.database of type string";
		equal(metadataLoadWarning("/work/.beads", error),
			"warning: load /work/.beads/metadata.json: " + error +
			"; no storage database was opened or modified (storage mode unknown; data commands refuse to fall back to the embedded store)\n");
		equal(metadataLoadFailure(error), "Error: loading config: " + error + "\n");
	}

	/**
		The database an embedded workspace opens and whether the store has it,
		against upstream GetDoltDatabase, ResolveRedirect, embeddeddolt's
		validIdentifier and Dolt's lower-case database lookup.
	**/
	static function embeddedDatabaseContracts():Void {
		for (name in ["beads", "test", "_x", "A_1", "B"])
			equal(isEmbeddedDatabaseIdentifier(name), true);
		for (name in ["", "1x", "my-db", "bad name", "t\u00e9st", "a.b"])
			equal(isEmbeddedDatabaseIdentifier(name), false);
		final temporary = Sys.getEnv("TMPDIR");
		final root = '${temporary == null || temporary == "" ? "/tmp" : temporary}/beadshx-database-name-contract-${Date.now().getTime()}-${Std.random(1000000)}';
		final beadsDir = '$root/.beads';
		FileSystem.createDirectory('$beadsDir/embeddeddolt/Test/.dolt');
		// A directory without a Dolt repository, and a file, are not databases.
		FileSystem.createDirectory('$beadsDir/embeddeddolt/other');
		File.saveContent('$beadsDir/embeddeddolt/plain', "");
		for (name in ["test", "TEST", "Test"])
			equal(embeddedDatabaseExists(beadsDir, name), true);
		for (name in ["other", "plain", "beads"])
			equal(embeddedDatabaseExists(beadsDir, name), false);
		equal(embeddedDatabaseExists('$root/missing', "test"), false);
		// Dolt's create checks the path named like a missing database: a directory, a file, nothing, or an unfinished create.
		FileSystem.createDirectory('$beadsDir/embeddeddolt/started/.dolt');
		FileSystem.createDirectory('$beadsDir/embeddeddolt/marked/.dolt');
		File.saveContent('$beadsDir/embeddeddolt/marked/.dolt/repo_state.json', "{}");
		File.saveContent('$beadsDir/embeddeddolt/marked/.dolt_safe_to_ignore', "");
		equal(embeddedDatabaseExists(beadsDir, "marked"), false);
		for (name => expected in [
			"other" => EntryDirectory,
			"plain" => EntryFile,
			"beads" => EntryAbsent,
			"started" => EntryIncomplete,
			"marked" => EntryIncomplete
		])
			equal(missingDatabaseEntry(beadsDir, name), expected);
		// DOLT_DBNAME_REPLACE makes Dolt name a database after its directory with spaces and hyphens as one `_`.
		FileSystem.createDirectory('$beadsDir/embeddeddolt/my--db/.dolt');
		final previousReplace = Sys.getEnv("DOLT_DBNAME_REPLACE");
		Sys.putEnv("DOLT_DBNAME_REPLACE", "1");
		equal(DoltDirectoryName.databaseName(" a - b\tc__d "), "a_b_c_d");
		equal(embeddedDatabaseExists(beadsDir, "MY_DB"), true);
		equal(embeddedDatabaseExists(beadsDir, "test"), true);
		Sys.putEnv("DOLT_DBNAME_REPLACE", "");
		equal(DoltDirectoryName.databaseName(" a-b "), " a-b ");
		equal(embeddedDatabaseExists(beadsDir, "my_db"), false);
		Sys.putEnv("DOLT_DBNAME_REPLACE", previousReplace == null ? "" : previousReplace);
		// No metadata.json, null, {} and an empty name select the default; the last duplicate and a folded key count.
		equal(configuredEmbeddedDatabase(beadsDir, ""), "beads");
		// Without metadata.json upstream's pre-run takes the default before it would read BEADS_DOLT_SERVER_DATABASE.
		equal(configuredEmbeddedDatabase(beadsDir, "fromenv"), "beads");
		for (raw => expected in [
			"null" => "beads",
			"{}" => "beads",
			'{"dolt_database":""}' => "beads",
			'{"dolt_database":"test","dolt_database":"other"}' => "other",
			'{"dolt_database":"other","dolt_database":null}' => "other",
			'{"DOLT_DATABASE":"test"}' => "test"
		]) {
			File.saveContent('$beadsDir/metadata.json', raw);
			equal(configuredEmbeddedDatabase(beadsDir, ""), expected);
		}
		// BEADS_DOLT_SERVER_DATABASE comes before metadata.json.
		equal(configuredEmbeddedDatabase(beadsDir, "fromenv"), "fromenv");
		// ResolveRedirect keeps a string dolt_database and ignores the rest; a type error keeps nothing.
		equal(redirectSourceDatabase('$root/missing'), "");
		for (raw => expected in [
			'{"dolt_database":"other","database":7}' => "other",
			'{"dolt_database":7}' => "",
			"[1]" => "",
			"null" => ""
		]) {
			File.saveContent('$beadsDir/metadata.json', raw);
			equal(redirectSourceDatabase(beadsDir), expected);
		}
		removeTree(root);
	}

	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree('$path/$entry');
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	/** The json.Unmarshal error text for `raw` and configfile.Config, or "" when it decodes. */
	static function decodeError(raw:String):String {
		return switch decodeGoStruct(raw, METADATA_CONFIG) {
			case GoJsonDecoded(_): "";
			case GoJsonFailed(message): message;
			case GoJsonUnsupported: "<unsupported>";
		};
	}

	static function showRenderContracts():Void {
		equal(renderConfigShowText([]), "No configuration found\n");
		equal(renderConfigShowJson([]), "null\n");
		final sorted = sortConfigShowEntries([
			entry("z", "1", "database"),
			entry("issue_prefix", "yaml", "config.yaml"),
			entry("Z", "2", "database"),
			entry("issue_prefix", "db", "database"),
			entry("ünï", "3", "database")
		]);
		// Byte order, and rows with one key stay in the order given.
		equal(render(sorted), "Z=2(database)|issue_prefix=yaml(config.yaml)|issue_prefix=db(database)|z=1(database)|ünï=3(database)");
		equal(render(filterConfigShowEntries(sorted, "data")), "Z=2(database)|issue_prefix=db(database)|z=1(database)|ünï=3(database)");
		equal(render(filterConfigShowEntries(sorted, "")), render(sorted));
		equal(render(filterConfigShowEntries(sorted, "git")), "");
		// Widths count bytes; padding counts runes, so a multi-byte key or value gets more spaces.
		equal(renderConfigShowText([entry("ünï", "é", "database"), entry("abcde", "abc", "git")]), "  ünï   = é    (database)\n  abcde = abc  (git)\n");
		// A value over 60 bytes keeps 57 and gains "..."; the column caps at 60.
		final long = [for (_ in 0...7) "0123456789"].join("");
		final sixty = long.substr(0, 60);
		equal(renderConfigShowText([entry("k", long, "database"), entry("kk", "v", "env: BD_KK")]),
			'  k  = ${long.substr(0, 57)}...  (database)\n  kk = v${[for (_ in 0...59) " "].join("")}  (env: BD_KK)\n');
		equal(renderConfigShowText([entry("k", sixty, "database")]), '  k = ${sixty}  (database)\n');
		// Multi-byte text truncates by bytes, and this cut falls between characters; the column is
		// 60 bytes wide, so the 32 characters shown get 28 spaces.
		final wide = "a" + [for (_ in 0...35) "é"].join("");
		equal(renderConfigShowText([entry("k", wide, "database")]), '  k = ${wide.substr(0, 29)}...${[for (_ in 0...28) " "].join("")}  (database)\n');
		equal(renderConfigShowJson([entry("k", "<v>\t", "database")]), '[\n  {\n    "key": "k",\n    "value": "<v>\\t",\n    "source": "database"\n  }\n]\n');
	}

	static function validateYamlContracts():Void {
		final host = fakeHost([
			"./present" => StatDirectory,
			"file.txt" => StatNotDirectory,
			"/fixture-home/plan" => StatDirectory,
			"locked" => StatFailed("stat locked: permission denied")
		]);
		// A key the file does not set is not checked, even where an empty value would fail.
		equal(yamlConfigIssues(yaml([]), host).join("|"), "");
		equal(yamlConfigIssues(yaml(["issue-prefix" => "abcdefghijklmnopqrstu"]), host).join("|"),
			'issue-prefix: "abcdefghijklmnopqrstu" is too long (max 20 characters)');
		// Go counts bytes: ten two-byte runes pass the length check but fail the pattern.
		equal(yamlConfigIssues(yaml(["issue-prefix" => "éééééééééé"]), host).join("|"),
			'issue-prefix: "éééééééééé" is invalid (must start with letter, contain only letters, numbers, dashes, underscores)');
		equal(yamlConfigIssues(yaml([
			"issue-prefix" => "a-B_9",
			"actor" => "me@example.com",
			"json" => " YES ",
			"no-db" => "f"
		]), host).join("|"), "");
		equal(yamlConfigIssues(yaml(["actor" => ".dot"]), host)[0],
			'actor: ".dot" is invalid (must start with letter/number, contain only letters, numbers, dashes, underscores, dots, or @)');
		equal(yamlConfigIssues(yaml(["json" => "maybe"]), host)[0], 'json: "maybe" is not a valid boolean value (expected true/false, yes/no, 1/0, on/off)');
		equal(yamlConfigIssues(yaml(["routing.mode" => "Auto"]), host)[0],
			'routing.mode: "Auto" is invalid (valid values: auto, maintainer, contributor, explicit)');
		equal(yamlConfigIssues(yaml(["routing.mode" => "auto", "routing.maintainer" => "."]), host).join("|"), "");
		equal(yamlConfigIssues(yaml(["routing.mode" => "auto", "routing.contributor" => "~/plan"]), host)[0],
			"routing.mode=auto with routing targets but repos.additional not configured. Issues created via routing will not be visible in bd list. Run 'bd repo add <routing-target>' to enable hydration.");
		// Hydrated targets compare after `~` expansion; a "." contributor is still checked once a maintainer target exists.
		equal(yamlConfigIssues(yaml([
			"routing.mode" => "auto",
			"routing.contributor" => "~/plan",
			"repos.additional" => "/fixture-home/plan"
		]), host).join("|"), "");
		equal(yamlConfigIssues(yaml([
			"routing.mode" => "auto",
			"routing.contributor" => ".",
			"routing.maintainer" => "./present",
			"repos.additional" => "other"
		]),
			host).join("|"),
			"routing.contributor=\".\" is not in repos.additional. Run 'bd repo add .' to make routed issues visible.|" +
			"routing.maintainer=\"./present\" is not in repos.additional. Run 'bd repo add ./present' to make routed issues visible.");
		equal(yamlConfigIssues(yaml([
			"routing.default" => "./missing",
			"routing.maintainer" => ".",
			"routing.contributor" => "locked"
		]), host).join("|"), 'routing.default: path "./missing" does not exist');
		equal(yamlConfigIssues(yaml(["repos.primary" => "file.txt", "repos.additional" => "./present,file.txt,"]), host).join("|"),
			'repos.primary: "file.txt" is not a directory|repos.additional: "file.txt" is not a directory');
		equal(yamlConfigIssues(yaml(["repos.primary" => "locked"]), host)[0], 'repos.primary: cannot access "locked": stat locked: permission denied');
	}

	static function validateMetadataContracts():Void {
		equal(metadataConfigIssues(null, goQuote).join("|"), "");
		equal(metadataConfigIssues({database: "dolt", doltDatabase: "test_db", deletionsRetentionDays: "0"}, goQuote).join("|"), "");
		equal(metadataConfigIssues({database: "beads.db", doltDatabase: "a-b.c", deletionsRetentionDays: "-3"}, goQuote).join("|"),
			'metadata.json database: "beads.db" looks like a SQLite file, but backend is dolt (expected a directory like "dolt")|'
			+ 'metadata.json database: "beads.db" is misleading for dolt backend (expected "dolt")|'
			+ 'metadata.json dolt_database: "a-b.c" contains characters invalid in embedded mode — replace with "a_b_c" or set dolt_mode to "server" (GH#3231)|'
			+ 'metadata.json deletions_retention_days: -3 is invalid (must be >= 0)');
		equal(metadataConfigIssues({database: "sub/x.sqlite", doltDatabase: "", deletionsRetentionDays: "-0"}, goQuote).join("|"),
			'metadata.json database: "sub/x.sqlite" should be a filename, not a path|' +
			'metadata.json database: "sub/x.sqlite" looks like a SQLite file, but backend is dolt (expected a directory like "dolt")');
	}

	static function validateSyncContracts():Void {
		final host = fakeHost([]);
		equal(syncConfigIssues(yaml([]), host).join("|"), "federation.remote: required for Dolt sync");
		equal(syncConfigIssues(yaml(["federation.sovereignty" => " t2 ", "federation.remote" => "dolthub://org/repo"]), host).join("|"), "");
		equal(syncConfigIssues(yaml(["federation.sovereignty" => "T5", "federation.remote" => "file:///x"]), host).join("|"),
			'federation.sovereignty: "T5" is invalid (valid values: T1, T2, T3, T4, or empty for no restriction)');
		// A pattern list reports a failed URL again, and a URL no pattern matches.
		equal(syncConfigIssues(yaml([
			"federation.remote" => "ftp://x",
			"federation.allowed-remote-patterns" => "ftp://*"
		]), host).length, 2);
		equal(syncConfigIssues(yaml([
			"federation.remote" => "dolthub://org/repo",
			"federation.allowed-remote-patterns" => "dolthub://org/*"
		]), host).join("|"), "");
		equal(syncConfigIssues(yaml([
			"federation.remote" => "dolthub://org/repo",
			"federation.allowed-remote-patterns" => "dolthub://other/*"
		]), host).join("|"),
			'federation.remote: remote URL "dolthub://org/repo" does not match any allowed pattern');
		final schemes = "dolthub, https, http, ssh, git, git+ssh, git+https, git+http, git+file, s3, aws, gs, az, oci, file";
		equal(remoteUrlProblem("git@github.com:org/repo.git", host), null);
		equal(remoteUrlProblem("a\tb", host), "remote URL contains control character at position 1 (0x09)");
		equal(remoteUrlProblem("é\x7f", host), "remote URL contains control character at position 2 (0x7f)");
		equal(remoteUrlProblem("-oProxy", host), "remote URL must not start with a dash");
		equal(remoteUrlProblem("@host:path", host), 'remote URL has no scheme (expected one of: ${schemes})');
		equal(remoteUrlProblem("git@:path", host), 'remote URL has no scheme (expected one of: ${schemes})');
		equal(remoteUrlProblem("ftp://x", host), 'remote URL scheme "ftp" is not allowed (expected one of: ${schemes})');
		equal(remoteUrlProblem("https://bad", host), "remote URL is malformed: parse failed");
		equal(remoteUrlProblem("dolthub://org", host), "dolthub:// URL must have org/repo format (e.g., dolthub://myorg/myrepo)");
		equal(remoteUrlProblem("dolthub://org/repo", host), null);
		equal(remoteUrlProblem("git+ssh:///path", host), "git+ssh:// URL must include a hostname");
		equal(remoteUrlProblem("s3:///path", host), "s3:// URL must include a bucket name");
		equal(remoteUrlProblem("az:///c", host), "az:// URL must include a storage account hostname");
		equal(remoteUrlProblem("oci:///c", host), "oci:// URL must include a namespace or bucket host");
		equal(remoteUrlProblem("file://", host), null);
	}

	static function validateRenderContracts():Void {
		equal(validationIssues(["a\n\nb"], ["c"]).join("|"), "a||b|c");
		equal(renderValidationText([]), "✓ All sync-related configuration is valid\n");
		equal(renderValidationText(["a", "", "b"]),
			"Configuration validation found issues:\n  • a\n  • b\n\nRun 'bd config set <key> <value>' to fix configuration issues.\n");
		equal(renderValidationJson([]), '{\n  "issues": [],\n  "schema_version": 1,\n  "valid": true\n}\n');
		equal(renderValidationJson(["x"]), '{\n  "issues": [\n    "x"\n  ],\n  "schema_version": 1,\n  "valid": false\n}\n');
	}

	static function driftHookContracts():Void {
		equal(hookVersion("#!/bin/sh\n# bd-shim v1\n").version, "v1");
		equal(hookVersion("#!/bin/sh\n# --- BEGIN BEADS INTEGRATION v0.56.1 ---\r\n").version, "0.56.1");
		equal(hookVersion("# bd-hooks-version: 0.9.0\n").isShim, false);
		equal(hookVersion("echo\n# bd (beads)").isBdHook, true);
		equal(hookVersion("echo hi\n").isBdHook, false);
		// The first marker decides; a line bufio.Scanner cannot hold before it fails the read.
		equal(hookVersion("# bd-hooks-version: 1\n# bd-shim v2\n").version, "1");
		final long = [for (_ in 0...65536) "x"].join("");
		equal(hookVersion(long + "\n# bd-shim v1\n"), null);
		equal(hookVersion("# bd-shim v1\n" + long).version, "v1");
		equal(hookVersion(long.substr(1)) != null, true);
		final statuses = [
			hookStatus("pre-commit", null, "1.2.1"),
			hookStatus("post-merge", "# bd (beads)\n", "1.2.1"),
			hookStatus("pre-push", "# bd-hooks-version: 0.1\n", "1.2.1"),
			hookStatus("post-checkout", "# bd-hooks-version: 1.2.1\n", "1.2.1"),
			hookStatus("prepare-commit-msg", "# bd-shim old\n", "1.2.1")
		];
		equal(renderItems(hooksDriftItems(statuses, "1.2.1")),
			"hooks.missing/drift/Git hooks not installed: pre-commit/installed/missing|" +
			"hooks.outdated/drift/Git hooks outdated: post-merge (have , want 1.2.1), pre-push (have 0.1, want 1.2.1)/v1.2.1/outdated");
		equal(renderItems(hooksDriftItems([hookStatus("pre-commit", "", "1.2.1")], "1.2.1")), "hooks/ok/Git hooks installed and current//");
		equal(isFalsyBool(" OFF "), true);
		equal(isFalsyBool("F"), true);
		equal(isFalsyBool("no"), false);
		equal(testDatabaseRefusal("beads_test_x", "127.0.0.1:0", false, goQuote),
			'refusing to connect test database "beads_test_x" to server 127.0.0.1:0: set BEADS_TEST_SERVER=1 on a dedicated test server, or use test helpers in internal/storage/dolt/testserver');
		equal(testDatabaseRefusal("beads_test_x", "127.0.0.1:0", true, goQuote), null);
		equal(testDatabaseRefusal("test", "127.0.0.1:0", false, goQuote), null);
	}

	static function driftRenderContracts():Void {
		final failure = unreachableServerMessage("127.0.0.1:0", "dial tcp 127.0.0.1:0: connect: connection refused", false);
		final items = [
			hooksDriftItems([hookStatus("pre-commit", null, "1.2.1")], "1.2.1")[0],
			remoteOpenFailureItem(failure),
			serverDriftItem(true),
			plainItem("server", DriftOk, "No shared server configured or running")
		];
		equal(hasDrift(items), true);
		equal(hasDrift(items.slice(1)), false);
		equal(renderDriftText(items),
			"  ✗ hooks.missing: Git hooks not installed: pre-commit\n      expected: installed\n      actual:   missing\n"
			+ "  – remote: Cannot open Dolt store: Dolt server unreachable at 127.0.0.1:0: dial tcp 127.0.0.1:0: connect: connection refused\n\n"
			+ "The Dolt server may not be running. Try:\n  bd dolt start\n"
			+ "  ℹ server: Dolt server is running but dolt.shared-server is not enabled in config\n"
			+ "  ✓ server: No shared server configured or running\n");
		equal(unreachableServerMessage("a", "e", true),
			"Dolt server unreachable at a: e\n\nDolt server auto-start is disabled (dolt.auto-start: false).\nStart the server manually:\n  bd dolt start");
		equal(renderDriftJson([items[0], items[2]]),
			'[\n  {\n    "check": "hooks.missing",\n    "status": "drift",\n    "message": "Git hooks not installed: pre-commit",\n' +
			'    "expected": "installed",\n    "actual": "missing"\n  },\n  {\n    "check": "server",\n    "status": "info",\n' +
			'    "message": "Dolt server is running but dolt.shared-server is not enabled in config"\n  }\n]\n');
	}

	static function renderItems(items:Array<DriftItem>):String {
		return [
			for (item in items)
				'${item.check}/${switch item.status {
					case DriftOk: "ok";
					case DriftDetected: "drift";
					case DriftInfo: "info";
					case DriftSkipped: "skipped";
				}}/${item.message}/${item.expected}/${item.actual}'
		].join("|");
	}

	/** A config.yaml with string keys; a list value is its comma-separated text. */
	static function yaml(values:Map<String, String>):ValidationYaml {
		return {
			isSet: key -> values.exists(key),
			getString: key -> values.exists(key) ? values.get(key) : "",
			getStringSlice: key -> values.exists(key) ? values.get(key).split(",") : []
		};
	}

	/** Paths not listed are missing; `~` expands to /fixture-home; "https://bad" does not parse; patterns match by prefix before `*`. */
	static function fakeHost(paths:Map<String, PathStat>):ValidationHost {
		return {
			stat: path -> paths.exists(path) ? paths.get(path) : StatMissing,
			expandHome: path -> StringTools.startsWith(path, "~") ? "/fixture-home" + path.substr(1) : path,
			quote: goQuote,
			parseUrl: raw -> raw == "https://bad" ? UrlMalformed("parse failed") : parseFakeUrl(raw),
			matchPattern: (pattern, name) -> StringTools.endsWith(pattern, "*")
				&& StringTools.startsWith(name, pattern.substr(0, pattern.length - 1))};
	}

	static function parseFakeUrl(raw:String):ParsedUrl {
		final rest = raw.substr(raw.indexOf("://") + 3);
		final slash = rest.indexOf("/");
		return slash < 0 ? UrlParts(rest, "") : UrlParts(rest.substr(0, slash), rest.substr(slash));
	}

	/** Go's `%q` for ASCII text without escapes. */
	static function goQuote(value:String):String {
		return '"${value}"';
	}

	static function entry(key:String, value:String, source:String):ConfigShowEntry {
		return {key: key, value: value, source: source};
	}

	static function render(entries:Null<Array<ConfigShowEntry>>):String {
		return entries == null ? "<null>" : [for (row in entries) '${row.key}=${row.value}(${row.source})'].join("|");
	}

	static function facts(name:String, environmentValue:String, source:ConfigSource, value:String):ConfigKeyFacts {
		return {
			environmentName: name,
			environmentValue: environmentValue,
			source: source,
			value: value
		};
	}

	static function quote(value:String):String {
		return '<${value}>';
	}

	static function permissionContracts():Void {
		final path = "/w/.beads";
		final warning = mode -> 'Warning: /w/.beads has permissions ${mode} (recommended: 0700). Run: chmod 700 /w/.beads\n';
		// Only the owner's bits print nothing, whatever they are.
		equal(beadsDirPermissionWarning(path, "-rwx------"), null);
		equal(beadsDirPermissionWarning(path, "----------"), null);
		equal(beadsDirPermissionWarning(path, "-r--------"), null);
		// Any group or other bit warns, an execute bit too, with four octal digits.
		equal(beadsDirPermissionWarning(path, "-rwxr-xr-x"), warning("0755"));
		equal(beadsDirPermissionWarning(path, "-rwxr-x---"), warning("0750"));
		equal(beadsDirPermissionWarning(path, "-rwxrwx---"), warning("0770"));
		equal(beadsDirPermissionWarning(path, "-rwx--x--x"), warning("0711"));
		equal(beadsDirPermissionWarning(path, "-rwx-----x"), warning("0701"));
		equal(beadsDirPermissionWarning(path, "-rwxrwxrwx"), warning("0777"));
		equal(beadsDirPermissionWarning(path, "----r-----"), warning("0040"));
		equal(beadsDirPermissionWarning(path, "-------r--"), warning("0004"));
		// The directory prints as upstream names it.
		equal(beadsDirPermissionWarning(".", "-rwxr-xr-x"), "Warning: . has permissions 0755 (recommended: 0700). Run: chmod 700 .\n");
	}

	static function equal<T>(actual:T, expected:T, ?pos:haxe.PosInfos):Void {
		if (actual != expected)
			throw '${pos.fileName}:${pos.lineNumber}: expected <${expected}>, got <${actual}>';
	}
}
