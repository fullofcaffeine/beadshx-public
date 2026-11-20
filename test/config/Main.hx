import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.cli.ConfigView.renderBackupEnabledJson;
import beadshx.cli.ConfigView.renderBackupEnabledText;
import beadshx.cli.ConfigView.renderConfigGetJson;
import beadshx.cli.ConfigView.renderConfigGetText;
import beadshx.cli.ConfigView.renderConfigListJson;
import beadshx.cli.ConfigView.renderConfigListText;
import beadshx.cli.ConfigView.renderConfigShowJson;
import beadshx.cli.ConfigView.renderConfigShowText;
import beadshx.config.ConfigShow.ConfigShowEntry;
import beadshx.config.ConfigShow.filterConfigShowEntries;
import beadshx.config.ConfigShow.layeredEntries;
import beadshx.config.ConfigShow.metadataEntries;
import beadshx.config.ConfigShow.sortConfigShowEntries;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.config.ConfigKeys.configSourceName;
import beadshx.config.ConfigKeys.environmentNames;
import beadshx.config.ConfigKeys.isConfigContainerKey;
import beadshx.config.ConfigKeys.isKvPlaneKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.config.ConfigKeys.isYamlOnlyKey;

/**
	Pins `bd config get`, `bd config list` and `bd config show` key routing and
	rendering against upstream config.IsYamlOnlyKey, IsUserGlobalKey,
	EnvVarName, showConfigYAMLOverrides, collectViperEntries,
	collectMetadataEntries and printConfigEntries, by hand. Viper's layering is
	native; parity covers the real runs.
**/
class Main {
	static function main():Void {
		keyContracts();
		getContracts();
		listContracts();
		showLayeredContracts();
		showMetadataContracts();
		showRenderContracts();
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

	static function equal<T>(actual:T, expected:T, ?pos:haxe.PosInfos):Void {
		if (actual != expected)
			throw '${pos.fileName}:${pos.lineNumber}: expected <${expected}>, got <${actual}>';
	}
}
