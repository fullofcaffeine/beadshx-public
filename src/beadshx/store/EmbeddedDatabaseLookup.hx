package beadshx.store;

import beadshx.config.ConfigShow.readMetadataFields;
import beadshx.store.JsonValue.GoJsonStruct;
import beadshx.store.JsonValue.decodeGoStruct;
import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Upstream configfile.DefaultDoltDatabase. */
final DEFAULT_EMBEDDED_DATABASE = "beads";

/** The one-field struct that upstream beads.ResolveRedirect decodes from a redirecting workspace's metadata.json. */
private final REDIRECT_SOURCE:GoJsonStruct = {
	packageName: "beads",
	name: "redirectSource",
	fields: [{tag: "dolt_database", kind: GoStringField}]
};

/**
	Upstream configfile GetDoltDatabase over one workspace's own metadata.json:
	`serverDatabaseVariable` (BEADS_DOLT_SERVER_DATABASE) when it is not empty,
	then dolt_database as json.Unmarshal decodes it (a case-folded key matches
	and the last duplicate wins), then `beads`. The native read-only facade
	takes the same name.
**/
function configuredEmbeddedDatabase(beadsDir:String, serverDatabaseVariable:String):String {
	if (serverDatabaseVariable != "")
		return serverDatabaseVariable;
	final recorded = switch readMetadataFields(beadsDir) {
		case MetadataFields(fields): fields.get("dolt_database");
		// The command stops before a store opens when metadata.json does not load.
		case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: null;
	};
	return recorded == null || recorded == "" ? DEFAULT_EMBEDDED_DATABASE : recorded;
}

/**
	Upstream beads.ResolveRedirect's SourceDatabase: the dolt_database of a
	redirecting workspace's metadata.json, which upstream's pre-run keeps across
	the redirect when BEADS_DOLT_SERVER_DATABASE is unset. It is empty when the
	file cannot be read or json.Unmarshal fails.
**/
function redirectSourceDatabase(sourceDir:String):String {
	var raw = "";
	try {
		raw = File.getContent(Path.join([sourceDir, "metadata.json"]));
	} catch (_:haxe.Exception) {
		return "";
	}
	return switch decodeGoStruct(raw, REDIRECT_SOURCE) {
		case GoJsonDecoded(fields): fields.exists("dolt_database") ? fields.get("dolt_database") : "";
		case GoJsonFailed(_) | GoJsonUnsupported: "";
	};
}

/**
	Upstream embeddeddolt's validIdentifier, `^[a-zA-Z_][a-zA-Z0-9_]*$`.
	Upstream refuses any other database name before it creates a database.
**/
function isEmbeddedDatabaseIdentifier(name:String):Bool {
	final bytes = Bytes.ofString(name);
	if (bytes.length == 0)
		return false;
	for (index in 0...bytes.length) {
		final code = bytes.get(index);
		final letter = (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || code == "_".code;
		final digit = code >= "0".code && code <= "9".code;
		if (!letter && (index == 0 || !digit))
			return false;
	}
	return true;
}

/**
	Whether the embedded Dolt engine of one workspace finds the database `name`
	without creating it. Dolt loads each directory in `.beads/embeddeddolt`
	that holds a `.dolt` repository as a database with the directory's name,
	and finds a database by its lower-case name, so `TEST` finds `test`.
	`name` must be an embedded database identifier, which is ASCII.
**/
function embeddedDatabaseExists(beadsDir:String, name:String):Bool {
	final dataDir = Path.join([beadsDir, "embeddeddolt"]);
	var entries:Array<String> = [];
	try {
		entries = FileSystem.readDirectory(dataDir);
	} catch (_:haxe.Exception) {
		return false;
	}
	final wanted = name.toLowerCase();
	for (entry in entries) {
		final repository = Path.join([dataDir, entry, ".dolt"]);
		if (entry.toLowerCase() == wanted && FileSystem.exists(repository) && FileSystem.isDirectory(repository))
			return true;
	}
	return false;
}
