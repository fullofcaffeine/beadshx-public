package beadshx.config;

import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.config.ConfigKeys.isConfigContainerKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.JsonValue.GoJsonField;
import beadshx.store.JsonValue.GoJsonFieldKind;
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

/** What upstream configfile.Load gives `bd config show` for one .beads directory. */
enum WorkspaceMetadataRead {
	/** The metadata.json rows; none when the file does not exist. */
	MetadataRows(entries:Array<ConfigShowEntry>);

	/** metadata.json cannot be read or does not decode, and upstream refuses to open the store. */
	MetadataUndecodable;

	/** Only a legacy config.json exists, which upstream rewrites as metadata.json. */
	MetadataLegacyOnly;
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

/** Every upstream configfile.Config field, which json.Unmarshal type-checks. */
private final METADATA_FIELDS:Array<GoJsonField> = [
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
];

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
	final decoded = decodeGoStruct(raw, METADATA_FIELDS);
	return decoded == null ? null : listedMetadataEntries(decoded);
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

/** What upstream configfile.Load decodes from one .beads directory, by JSON tag. */
enum WorkspaceMetadataFields {
	/** No metadata.json and no legacy config.json. */
	MetadataAbsent;

	/** The decoded fields, as decodeGoStruct gives them. */
	MetadataFields(fields:Map<String, String>);

	/** metadata.json cannot be read or does not decode, and upstream refuses to open the store. */
	MetadataFieldsUndecodable;

	/** Only a legacy config.json exists, which upstream rewrites as metadata.json. */
	MetadataFieldsLegacyOnly;
}

/** Upstream configfile.Load for one .beads directory, without its legacy config.json migration. */
function readMetadataFields(beadsDir:String):WorkspaceMetadataFields {
	final path = Path.join([beadsDir, "metadata.json"]);
	if (!FileSystem.exists(path))
		return FileSystem.exists(Path.join([beadsDir, "config.json"])) ? MetadataFieldsLegacyOnly : MetadataAbsent;
	if (FileSystem.isDirectory(path))
		return MetadataFieldsUndecodable;
	final raw = try File.getContent(path) catch (_:haxe.Exception) null;
	if (raw == null)
		return MetadataFieldsUndecodable;
	final decoded = decodeGoStruct(raw, METADATA_FIELDS);
	return decoded == null ? MetadataFieldsUndecodable : MetadataFields(decoded);
}

/** The `bd config show` rows of one .beads directory's metadata.json. */
function readWorkspaceMetadata(beadsDir:String):WorkspaceMetadataRead {
	return switch readMetadataFields(beadsDir) {
		case MetadataAbsent: MetadataRows([]);
		case MetadataFields(fields): MetadataRows(listedMetadataEntries(fields));
		case MetadataFieldsUndecodable: MetadataUndecodable;
		case MetadataFieldsLegacyOnly: MetadataLegacyOnly;
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
