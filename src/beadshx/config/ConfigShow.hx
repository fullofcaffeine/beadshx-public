package beadshx.config;

import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.config.ConfigKeys.isConfigContainerKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.JsonValue.GoJsonDecode;
import beadshx.store.JsonValue.GoJsonFieldKind;
import beadshx.store.JsonValue.GoJsonStruct;
import beadshx.store.JsonValue.decodeGoStruct;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** One `bd config show` row: a key, its effective value and where the value came from. */
typedef ConfigShowEntry = {
	final key:String;
	final value:String;
	final source:String;
}

/**
	Upstream collectViperEntries: every layered key except the map containers,
	with its value and source label, leaving out unset defaults. `beadsActor` is
	BEADS_ACTOR ("" when unset), which outranks BD_ACTOR for the actor row as
	at runtime.

	User-global keys come from the user config.yaml alone, and upstream leaves
	them out when that file does not set them. The caller refuses when a user
	config.yaml exists, so every user-global key is left out here.
**/
function layeredEntries(keys:Array<String>, facts:String->ConfigKeyFacts, beadsActor:String):Array<ConfigShowEntry> {
	final entries = new Array<ConfigShowEntry>();
	final seen = new Map<String, Bool>();
	for (key in keys) {
		if (seen.exists(key) || isConfigContainerKey(key) || isUserGlobalKey(key))
			continue;
		seen.set(key, true);
		final known = facts(key);
		var value = known.value;
		var source = switch known.source {
			case EnvironmentSource: known.environmentName == "" ? "env" : 'env: ${known.environmentName}';
			case ConfigFileSource: "config.yaml";
			case DefaultSource: "default";
		};
		if (key == "actor" && beadsActor != "") {
			value = beadsActor;
			source = "env: BEADS_ACTOR";
		}
		if (known.source == DefaultSource && value == "")
			continue;
		entries.push({key: key, value: value, source: source});
	}
	return entries;
}

/** Upstream configfile.Config with every field, which json.Unmarshal type-checks. */
final METADATA_CONFIG:GoJsonStruct = {
	packageName: "configfile",
	name: "Config",
	fields: [
		{tag: "database", kind: GoStringField},
		{tag: "backend", kind: GoStringField},
		{tag: "deletions_retention_days", kind: GoIntField},
		{tag: "dolt_mode", kind: GoStringField},
		{tag: "dolt_server_host", kind: GoStringField},
		{tag: "dolt_server_port", kind: GoIntField},
		{tag: "dolt_server_socket", kind: GoStringField},
		{tag: "dolt_server_user", kind: GoStringField},
		{tag: "dolt_database", kind: GoStringField},
		{tag: "dolt_server_tls", kind: GoBoolField},
		{tag: "dolt_data_dir", kind: GoStringField},
		{tag: "dolt_remotesapi_port", kind: GoIntField},
		{tag: "dolt_team_server", kind: GoBoolField},
		{tag: "postgres_dsn", kind: GoStringField},
		{tag: "postgres_schema", kind: GoStringField},
		{tag: "mysql_dsn", kind: GoStringField},
		{tag: "mysql_database", kind: GoStringField},
		{tag: "sqlite_path", kind: GoStringField},
		{tag: "project_id", kind: GoStringField},
		{tag: "global_dolt_database", kind: GoStringField},
		{tag: "global_project_id", kind: GoStringField},
		{tag: "stale_closed_issues_days", kind: GoIntField},
		{tag: "last_bd_version", kind: GoStringField}
	]
};

/** The fields upstream collectMetadataEntries lists, in its order, each with its zero value. */
private final LISTED_METADATA:Array<{tag:String, zero:String}> = [
	{tag: "dolt_mode", zero: ""},
	{tag: "dolt_server_host", zero: ""},
	{tag: "dolt_server_port", zero: "0"},
	{tag: "dolt_server_user", zero: ""},
	{tag: "dolt_database", zero: ""},
	{tag: "dolt_server_tls", zero: "false"},
	{tag: "dolt_data_dir", zero: ""},
	{tag: "dolt_remotesapi_port", zero: "0"},
	{tag: "project_id", zero: ""},
	{tag: "deletions_retention_days", zero: "0"},
	{tag: "stale_closed_issues_days", zero: "0"}
];

/**
	Upstream collectMetadataEntries for metadata.json text: each listed field
	that is not its zero value, under source `metadata`. Null when the text does
	not decode into configfile.Config, which upstream reads with json.Unmarshal.
**/
function metadataEntries(raw:String):Null<Array<ConfigShowEntry>> {
	return switch decodeGoStruct(raw, METADATA_CONFIG) {
		case GoJsonDecoded(decoded): listedMetadataEntries(decoded);
		case GoJsonFailed(_) | GoJsonUnsupported: null;
	};
}

private function listedMetadataEntries(decoded:Map<String, String>):Array<ConfigShowEntry> {
	final entries = new Array<ConfigShowEntry>();
	for (field in LISTED_METADATA) {
		final value = decoded.get(field.tag);
		if (value != null && value != field.zero)
			entries.push({key: field.tag, value: value, source: "metadata"});
	}
	return entries;
}

/** What upstream configfile.LoadForDiscovery gives for one .beads directory, by JSON tag. */
enum WorkspaceMetadataFields {
	/** No metadata.json and no legacy config.json. */
	MetadataAbsent;

	/** The decoded fields, as decodeGoStruct gives them. */
	MetadataFields(fields:Map<String, String>);

	/**
		metadata.json, or the legacy config.json when there is no metadata.json,
		cannot be read or does not decode. `error` is LoadForDiscovery's error
		text, such as `parsing config: json: ...`. Upstream's pre-run then
		refuses every command that opens a store.
	**/
	MetadataFieldsUndecodable(error:String);

	/** The file is valid JSON for Go's scanner, but the typed parser rejects it, so its decoding is unknown. */
	MetadataFieldsUnsupported;

	/** Only a legacy config.json exists, and it decodes. Upstream's store open rewrites it as metadata.json. */
	MetadataFieldsLegacyOnly;
}

/**
	Upstream configfile.LoadForDiscovery for one .beads directory: metadata.json,
	or else a legacy config.json, read and decoded without the migration that
	configfile.Load does.
**/
function readMetadataFields(beadsDir:String):WorkspaceMetadataFields {
	final path = Path.join([beadsDir, "metadata.json"]);
	if (FileSystem.exists(path))
		return decodeMetadataFile(path, "reading config", false);
	final legacyPath = Path.join([beadsDir, "config.json"]);
	return FileSystem.exists(legacyPath) ? decodeMetadataFile(legacyPath, "reading legacy config", true) : MetadataAbsent;
}

/**
	The decoded fields of a legacy-only workspace's config.json (see
	MetadataFieldsLegacyOnly), which upstream's LoadForDiscovery reads as its
	config without the rewrite, for checks such as the legacy-workspace guard
	and the shared-server notice. Null when the workspace is not legacy-only,
	or when the file no longer reads or decodes.
**/
function readLegacyConfigFields(beadsDir:String):Null<Map<String, String>> {
	if (FileSystem.exists(Path.join([beadsDir, "metadata.json"])))
		return null;
	final raw = try File.getContent(Path.join([beadsDir, "config.json"])) catch (_:haxe.Exception) return null;
	return switch decodeGoStruct(raw, METADATA_CONFIG) {
		case GoJsonDecoded(fields): fields;
		case GoJsonFailed(_) | GoJsonUnsupported: null;
	};
}

/** One LoadForDiscovery read: a read error carries `readContext` and the os error text, a decode error `parsing config`. */
private function decodeMetadataFile(path:String, readContext:String, legacy:Bool):WorkspaceMetadataFields {
	var raw = "";
	try {
		raw = File.getContent(path);
	} catch (error:haxe.Exception) {
		return MetadataFieldsUndecodable('${readContext}: ${error.message}');
	}
	return switch decodeGoStruct(raw, METADATA_CONFIG) {
		case GoJsonDecoded(fields): legacy ? MetadataFieldsLegacyOnly : MetadataFields(fields);
		case GoJsonFailed(message): MetadataFieldsUndecodable('parsing config: ${message}');
		case GoJsonUnsupported: MetadataFieldsUnsupported;
	};
}

/**
	Upstream loadServerModeFromBeadsDir's warning, which the root pre-run prints
	when LoadForDiscovery fails for the selected .beads directory. It names
	metadata.json even when the error came from a legacy config.json.
**/
function metadataLoadWarning(beadsDir:String, error:String):String {
	return 'warning: load ${Path.join([beadsDir, "metadata.json"])}: ${error}; no storage database was opened or modified '
		+ "(storage mode unknown; data commands refuse to fall back to the embedded store)\n";
}

/**
	Upstream warnSharedServerEmbeddedMismatch's notice, which the
	selected-workspace setup prints once on stderr in shared-server mode when
	metadata.json pins dolt_mode embedded (see pinsEmbeddedMode).
**/
final SHARED_SERVER_EMBEDDED_NOTICE = "Notice: shared-server mode is enabled (BEADS_DOLT_SHARED_SERVER or dolt.shared-server in config.yaml) "
	+ "but .beads/metadata.json pins dolt_mode=\"embedded\". Using the shared server for this run.\n"
	+ "  To persist server mode: set dolt_mode to \"server\" in .beads/metadata.json and commit it.\n"
	+ "  To stay embedded: unset BEADS_DOLT_SHARED_SERVER (or remove dolt.shared-server from config.yaml).\n";

/** Whether decoded metadata.json fields pin dolt_mode embedded, as upstream compares it: trimmed and in lower case. */
function pinsEmbeddedMode(fields:Map<String, String>):Bool {
	final mode = fields.get("dolt_mode");
	return mode != null && goTrimSpace(mode).toLowerCase() == "embedded";
}

/** Upstream guardLegacyUpgradeWorkspace's error for a failed LoadForDiscovery, as HandleError prints it. */
function metadataLoadFailure(error:String):String {
	return 'Error: loading config: ${error}\n';
}

/**
	The `bd config show` rows of one .beads directory's metadata.json; none when
	it does not exist. The command application stops a workspace whose
	metadata.json does not load before any store command runs, so that case
	gives no rows here.
**/
function readWorkspaceMetadata(beadsDir:String):Array<ConfigShowEntry> {
	return switch readMetadataFields(beadsDir) {
		case MetadataFields(fields): listedMetadataEntries(fields);
		case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: [];
	};
}

/** Upstream's sort by key in byte order. Rows with one key keep the order given, which upstream leaves to chance. */
function sortConfigShowEntries(entries:Array<ConfigShowEntry>):Array<ConfigShowEntry> {
	final indexed = [for (index in 0...entries.length) {entry: entries[index], index: index}];
	indexed.sort((left, right) -> {
		final order = compareUtf8(left.entry.key, right.entry.key);
		return order != 0 ? order : left.index - right.index;
	});
	return [for (item in indexed) item.entry];
}

/** Upstream filterBySource: the rows whose source starts with `source`. */
function filterConfigShowEntries(entries:Array<ConfigShowEntry>, source:String):Array<ConfigShowEntry> {
	return [for (entry in entries) if (StringTools.startsWith(entry.source, source)) entry];
}
