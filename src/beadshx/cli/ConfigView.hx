package beadshx.cli;

import beadshx.cli.CatalogViews.CatalogField;
import beadshx.cli.CatalogViews.CatalogJson;
import beadshx.cli.CatalogViews.field;
import beadshx.cli.CatalogViews.renderCatalogJson;
import beadshx.config.ConfigKeys.ConfigSetting;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.config.ConfigKeys.configSourceName;
import beadshx.config.ConfigKeys.isYamlOnlyKey;
import beadshx.relation.DependencyRead.compareUtf8;

/** What upstream's `bd config list` override notes read for one key. */
typedef ConfigKeyFacts = {
	/** The first of the key's BD_ and BEADS_ variables that is set, or "". */
	final environmentName:String;

	final environmentValue:String;
	final source:ConfigSource;

	/** The layered value, as Viper's GetString gives it. */
	final value:String;
}

/** Upstream configGetCmd text: the value, or the key and where it is not set. A null location is the database. */
function renderConfigGetText(key:String, value:String, location:Null<String>):String {
	if (value != "")
		return value + "\n";
	return location == null ? '${key} (not set)\n' : '${key} (not set in ${location})\n';
}

/** Upstream configGetCmd JSON: a Go map, so the keys print sorted, with schema_version added. */
function renderConfigGetJson(key:String, value:String, location:Null<String>):String {
	final fields = [field("key", JsonText(key))];
	if (location != null)
		fields.push(field("location", JsonText(location)));
	fields.push(field("schema_version", JsonNumber("1")));
	fields.push(field("value", JsonText(value)));
	return renderCatalogJson(JsonObject(fields));
}

/** Upstream runConfigGetBackupEnabled: the effective value and where it came from. */
function renderBackupEnabledText(effective:Bool, description:String):String {
	return '${effective ? "true" : "false"} (${description})\n';
}

function renderBackupEnabledJson(effective:Bool, source:ConfigSource):String {
	final value = JsonNumber(effective ? "true" : "false");
	return renderCatalogJson(JsonObject([
		field("effective", value),
		field("key", JsonText("backup.enabled")),
		field("schema_version", JsonNumber("1")),
		field("source", JsonText(configSourceName(source))),
		field("value", value)
	]));
}

/** Upstream configListCmd JSON: the stored map with schema_version added, all keys in byte order. */
function renderConfigListJson(settings:Array<ConfigSetting>):String {
	final fields:Array<CatalogField> = [
		for (setting in settings)
			if (setting.key != "schema_version") field(setting.key, JsonText(setting.value))
	];
	fields.push(field("schema_version", JsonNumber("1")));
	fields.sort((left, right) -> compareUtf8(left.key, right.key));
	return renderCatalogJson(JsonObject(fields));
}

/**
	Upstream configListCmd text and showConfigYAMLOverrides. The stored settings
	print in byte order; then config.yaml values for YAML-only keys the database
	does not hold, and every environment variable that overrides a stored or
	known key. `allKeys` is Viper's AllKeys; `quote` is Go's `%q`.
**/
function renderConfigListText(settings:Array<ConfigSetting>, allKeys:Array<String>, facts:String->ConfigKeyFacts, quote:String->String):String {
	if (settings.length == 0)
		return "No configuration set\n";
	final sorted = settings.copy();
	sorted.sort((left, right) -> compareUtf8(left.key, right.key));
	final rendered = new StringBuf();
	rendered.add("\nConfiguration:\n");
	final stored = new Map<String, Bool>();
	final environmentNotes = new Array<String>();
	for (setting in sorted) {
		rendered.add('  ${setting.key} = ${setting.value}\n');
		stored.set(setting.key, true);
		final known = facts(setting.key);
		if (known.environmentName != "" && known.environmentValue != setting.value)
			environmentNotes.push('  ${setting.key}: DB has ${quote(setting.value)}, but env ${known.environmentName}=${quote(known.environmentValue)} takes precedence');
	}
	final keys = allKeys.copy();
	keys.sort(compareUtf8);
	final yamlValues = new Array<String>();
	for (key in keys) {
		if (stored.exists(key))
			continue;
		final known = facts(key);
		if (isYamlOnlyKey(key) && known.source == ConfigFileSource && known.value != "")
			yamlValues.push('  ${key} = ${known.value}');
		if (known.environmentName != "" && known.source == EnvironmentSource)
			environmentNotes.push('  ${key}: env ${known.environmentName}=${quote(known.environmentValue)} overrides config');
	}
	if (yamlValues.length > 0)
		rendered.add("\nAlso set in config.yaml (not shown above):\n" + yamlValues.join("\n") + "\n");
	if (environmentNotes.length > 0) {
		environmentNotes.sort(compareUtf8);
		rendered.add("\n⚠ Environment variable overrides detected:\n" + environmentNotes.join("\n") + "\n");
	}
	rendered.add("\nTip: Run 'bd config show' for all effective config with provenance.\n");
	return rendered.toString();
}

/** Upstream `bd config --help`, which bare `bd config` and an unknown subcommand also print. */
function configHelp(globalFlags:String):String {
	return [
		"Manage configuration settings for external integrations and preferences.",
		"",
		"Configuration is stored per-project in the beads database and is version-control-friendly.",
		"",
		"Common namespaces:",
		"  - export.*          Auto-export settings (stored in config.yaml)",
		"  - import.*          JSONL import settings (stored in config.yaml)",
		"  - jira.*            Jira integration settings",
		"  - linear.*          Linear integration settings",
		"  - github.*          GitHub integration settings",
		"  - gitlab.*          GitLab integration settings",
		"  - ado.*             Azure DevOps integration settings",
		"  - notion.*          Notion integration settings",
		"  - custom.*          Custom integration settings",
		"  - status.*          Issue status configuration",
		"  - claim.*           Claim arbitration settings (pool-aware claiming)",
		"  - doctor.suppress.* Suppress specific bd doctor warnings (GH#1095)",
		"",
		"Auto-Export (config.yaml):",
		"  Optional JSONL export to .beads/issues.jsonl after write commands (throttled).",
		"  Useful for viewers (bv), interchange, and issue-level migration; not a backup.",
		"  It is not cross-machine sync; use bd dolt push/pull with a Dolt remote.",
		"  Disabled by default. Enable only for integrations that need fresh JSONL.",
		"  Auto-staging is separate and disabled by default.",
		"",
		"  Keys:",
		"    export.auto       Enable/disable auto-export (default: false)",
		"    export.path       Output filename relative to .beads/ (default: issues.jsonl)",
		"    export.interval   Minimum time between exports (default: 60s)",
		"    export.git-add    Auto-stage the export file (default: false)",
		"",
		"Auto-Import (config.yaml):",
		"  Reads .beads/issues.jsonl by default when a JSONL import path is implied.",
		"  Use a relative filename/path so the import stays within the project .beads/",
		"  directory and remains portable across machines.",
		"",
		"  Keys:",
		"    import.path       Input filename relative to .beads/ (default: issues.jsonl)",
		"",
		"Custom Status States:",
		"  You can define custom status states for multi-step pipelines using the",
		"  status.custom config key. Statuses should be comma-separated.",
		"",
		"  Example:",
		"    bd config set status.custom \"awaiting_review,awaiting_testing,awaiting_docs\"",
		"",
		"  This enables issues to use statuses like 'awaiting_review' in addition to",
		"  the built-in statuses (open, in_progress, blocked, deferred, closed).",
		"",
		"Claim Pools:",
		"  A dispatcher can pre-assign issues to a pool pseudo-assignee (e.g.",
		"  \"fable-crew\") and let any actor take them with --claim. List the pool",
		"  aliases in the claim.pools config key, comma-separated:",
		"",
		"    bd config set claim.pools \"fable-crew,night-crew\"",
		"",
		"  Issues assigned to a real actor (or to an alias not in the list) keep",
		"  their anti-steal protection. Pool takes carry the normal lease; note",
		"  that if a taker's lease expires, bd reclaim returns the issue to the",
		"  unassigned pool, not to the pool alias it was dispatched to.",
		"",
		"Suppressing Doctor Warnings:",
		"  Suppress specific bd doctor warnings by check name slug:",
		"    bd config set doctor.suppress.pending-migrations true",
		"    bd config set doctor.suppress.git-hooks true",
		"  Check names are converted to slugs: \"Git Hooks\" → \"git-hooks\".",
		"  Only warnings are suppressed (errors and passing checks always show).",
		"  To unsuppress: bd config unset doctor.suppress.<slug>",
		"",
		"Examples:",
		"  bd config set export.auto true                       # Enable auto-export for viewer integrations",
		"  bd config set export.path \"beads.jsonl\"              # Custom export filename",
		"  bd config set import.path \"beads.jsonl\"              # Custom import filename",
		"  bd config set export.git-add true                    # Also stage the export file",
		"  bd config set jira.url \"https://company.atlassian.net\"",
		"  bd config set jira.project \"PROJ\"",
		"  bd config set status.custom \"awaiting_review,awaiting_testing\"",
		"  bd config set claim.pools \"fable-crew,night-crew\"    # Pool aliases claimable by any actor",
		"  bd config set doctor.suppress.pending-migrations true",
		"  bd config set dolt.debug true                        # Enable Dolt sql-server debug mode (loglevel=debug, --prof cpu)",
		"  bd config set dolt.local-only true                   # Skip wiring a Dolt sync remote during bd init",
		"  bd config get export.auto",
		"  bd config list",
		"  bd config unset jira.url",
		"",
		"Usage:",
		"  bd config [command]",
		"",
		"Available Commands:",
		"  apply       Reconcile system state to match configuration",
		"  drift       Detect config-vs-reality inconsistencies",
		"  get         Get a configuration value",
		"  list        List all configuration",
		"  set         Set a configuration value",
		"  set-many    Set multiple configuration values in one operation",
		"  show        Show all effective configuration with provenance",
		"  unset       Delete a configuration value",
		"  validate    Validate sync-related configuration",
		"",
		"Flags:",
		"  -h, --help   help for config",
		""
	].join("\n") + "\n" + globalFlags + "\nUse \"bd config [command] --help\" for more information about a command.\n";
}

/** Upstream help for `bd config get` and `bd config list`, which declare no flags of their own. */
function configSubcommandHelp(short:String, usage:String, name:String, globalFlags:String):String {
	return '${short}\n\nUsage:\n  bd config ${usage} [flags]\n\nFlags:\n  -h, --help   help for ${name}\n\n' + globalFlags;
}
