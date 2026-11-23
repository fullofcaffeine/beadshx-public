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
	The database that upstream's pre-run opens in one workspace's embedded store.
	Without metadata.json or a legacy config.json it takes `beads` and does not
	read BEADS_DOLT_SERVER_DATABASE. Otherwise it is configfile GetDoltDatabase
	over the workspace's own metadata.json: `serverDatabaseVariable`
	(BEADS_DOLT_SERVER_DATABASE) when it is not empty, then dolt_database as
	json.Unmarshal decodes it (a case-folded key matches and the last duplicate
	wins), then `beads`. The native read-only facade takes the same name, except
	that it reads the variable also without metadata.json.
**/
function configuredEmbeddedDatabase(beadsDir:String, serverDatabaseVariable:String):String {
	final recorded = switch readMetadataFields(beadsDir) {
		case MetadataAbsent: return DEFAULT_EMBEDDED_DATABASE;
		case MetadataFields(fields): fields.get("dolt_database");
		// The command stops before a store opens when metadata.json does not load.
		case MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: null;
	};
	if (serverDatabaseVariable != "")
		return serverDatabaseVariable;
	return recorded == null || recorded == "" ? DEFAULT_EMBEDDED_DATABASE : recorded;
}

/**
	The warning that upstream's pre-run prints on stderr, in every output mode,
	before it opens the embedded store of a workspace without metadata.json or
	a legacy config.json. `beadsDir` is the directory as upstream names it.
**/
function missingConfigurationWarning(beadsDir:String):String {
	return 'warning: no beads configuration found in ${beadsDir}; using default database name "${DEFAULT_EMBEDDED_DATABASE}"\n';
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
	that holds a `.dolt` repository, and no in-progress marker, as a database
	named after the directory (`DoltDirectoryName`). It finds a
	database by its lower-case name, so `TEST` finds `test`. `name` must be an
	embedded database identifier, which is ASCII.
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
		if (DoltDirectoryName.databaseName(entry).toLowerCase() == wanted
			&& FileSystem.exists(repository)
			&& FileSystem.isDirectory(repository)
			&& !FileSystem.exists(Path.join([dataDir, entry, DOLT_IN_PROGRESS_MARKER])))
			return true;
	}
	return false;
}

/** Dolt dbfactory's marker file in a database directory that a create has not finished; Dolt skips such a directory. */
private final DOLT_IN_PROGRESS_MARKER = ".dolt_safe_to_ignore";

/**
	What a missing database's own path in the store holds. Upstream's plain
	open runs `CREATE DATABASE IF NOT EXISTS`, and Dolt then checks the path
	named like the database before it creates anything.
**/
enum MissingDatabaseEntry {
	/** Nothing, or a path that os.Stat cannot read: Dolt would create the database. */
	EntryAbsent;

	/** A directory that is no database: Dolt takes the name as used, and upstream's `USE` then fails. */
	EntryDirectory;

	/** A file: Dolt refuses to create the database. */
	EntryFile;

	/** A directory that a Dolt create left unfinished, which Dolt reports in words this build does not model. */
	EntryIncomplete;
}

/** Dolt's check of `<store>/<name>` (database_provider.go checkDatabaseNameAvailableLocked), for a database the store lacks. */
function missingDatabaseEntry(beadsDir:String, name:String):MissingDatabaseEntry {
	final path = Path.join([beadsDir, "embeddeddolt", name]);
	if (!FileSystem.exists(path))
		return EntryAbsent;
	if (!FileSystem.isDirectory(path))
		return EntryFile;
	final repository = Path.join([path, ".dolt"]);
	final started = FileSystem.exists(repository) && FileSystem.isDirectory(repository);
	if (FileSystem.exists(Path.join([path, DOLT_IN_PROGRESS_MARKER]))
		|| (started && !FileSystem.exists(Path.join([repository, "repo_state.json"]))))
		return EntryIncomplete;
	return EntryDirectory;
}
