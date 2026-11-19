package beadshx.config;

/** `bd config get` and `bd config list` have the same embedded-only Haxe SQL route as `bd dep cycles`. */
final CONFIG_ROUTE_UNAVAILABLE = "config is not available yet for server-mode or proxied workspaces in this build";

/** One row of the database config table. */
typedef ConfigSetting = {
	final key:String;
	final value:String;
}

/** Where upstream config.GetValueSource says a value came from. */
enum ConfigSource {
	DefaultSource;
	ConfigFileSource;
	EnvironmentSource;
}

/** Upstream's ConfigSource strings, which `bd config get backup.enabled --json` prints. */
function configSourceName(source:ConfigSource):String {
	return switch source {
		case DefaultSource: "default";
		case ConfigFileSource: "config_file";
		case EnvironmentSource: "env_var";
	};
}

/**
	Upstream config.IsYamlOnlyKey: startup settings and secrets that live in
	config.yaml rather than the database, by exact key or by namespace.
**/
function isYamlOnlyKey(key:String):Bool {
	switch key {
		case "no-db" | "json" | "events-journal" | "events-journal-retain-days" | "events-journal-retain-rows" | "events-journal-auto-prune" | "db" |
			"actor" | "identity" | "node_id" | "git.author" | "git.no-gpg-sign" | "no-push" | "no-git-ops" | "agent.profile" | "sync.remote" |
			"sync.git-remote" | "sync.require_confirmation_on_mass_delete" | "routing.mode" | "routing.default" | "routing.maintainer" |
			"routing.contributor" | "create.require-description" | "prime.max-memories" | "prime.max-memory-chars" | "validation.on-create" |
			"validation.on-close" | "validation.on-sync" | "hierarchy.max-depth" | "backup.enabled" | "backup.interval" | "backup.git-push" |
			"backup.git-repo" | "import.auto" | "import.path" | "dolt.shared-server" | "dolt.max-conns" | "dolt.pool-read-timeout" |
			"dolt.pool-write-timeout" | "dolt.debug" | "github.token" | "linear.api_key" | "linear.oauth_client_id" | "linear.oauth_client_secret" |
			"jira.api_token" | "gitlab.token" | "ado.pat":
			return true;
		case _:
	}
	for (prefix in [
		"routing.",
		"sync.",
		"git.",
		"directory.",
		"repos.",
		"external_projects.",
		"validation.",
		"hierarchy.",
		"ai.",
		"backup.",
		"export.",
		"dolt.",
		"federation.",
		"metrics.",
		"list.",
		"audit.",
		"storage-class."
	])
		if (StringTools.startsWith(key, prefix))
			return true;
	return false;
}

/** Upstream config.IsUserGlobalKey: per-machine keys read from the user config.yaml alone. */
function isUserGlobalKey(key:String):Bool {
	return key == "node_id" || StringTools.startsWith(key, "metrics.");
}

/**
	Upstream workapi.KeyIsOnTheKVPlane: `bd kv` and `bd remember` rows share the
	config table, and the settings reads answer them as absent.
**/
function isKvPlaneKey(key:String):Bool {
	return StringTools.startsWith(key, "kv.");
}

/**
	The variables upstream config.EnvVarName and GetValueSource try for a key, in
	order: BD_ and then the legacy BEADS_ prefix, with dots and dashes as
	underscores, upper-cased like Go's strings.ToUpper.
**/
function environmentNames(key:String):Array<String> {
	final suffix = StringTools.replace(StringTools.replace(key, "-", "_"), ".", "_").toUpperCase();
	return ["BD_" + suffix, "BEADS_" + suffix];
}
