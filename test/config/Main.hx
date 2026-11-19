import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.cli.ConfigView.renderBackupEnabledJson;
import beadshx.cli.ConfigView.renderBackupEnabledText;
import beadshx.cli.ConfigView.renderConfigGetJson;
import beadshx.cli.ConfigView.renderConfigGetText;
import beadshx.cli.ConfigView.renderConfigListJson;
import beadshx.cli.ConfigView.renderConfigListText;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.config.ConfigKeys.configSourceName;
import beadshx.config.ConfigKeys.environmentNames;
import beadshx.config.ConfigKeys.isKvPlaneKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.config.ConfigKeys.isYamlOnlyKey;

/**
	Pins `bd config get` and `bd config list` key routing and rendering against
	upstream config.IsYamlOnlyKey, IsUserGlobalKey, EnvVarName and
	showConfigYAMLOverrides, by hand. Viper's layering is native; parity covers
	the real runs.
**/
class Main {
	static function main():Void {
		keyContracts();
		getContracts();
		listContracts();
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
