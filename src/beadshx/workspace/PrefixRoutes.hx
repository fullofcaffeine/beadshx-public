package beadshx.workspace;

import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.workspace.RoutePaths.sameDirectory;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.JsonValue.GoJsonStruct;
import beadshx.store.JsonValue.decodeGoStruct;
import haxe.io.Bytes;
import haxe.io.Path;
import sys.io.File;

/** One rule of a workspace's routes.jsonl, as upstream prefixRoute decodes it (cmd/bd/routed.go:136-140). */
typedef PrefixRoute = {
	/** An issue ID prefix with its hyphen, such as `hr-`. */
	final prefix:String;

	/** The directory of the routed workspace, relative to the parent of the workspace that holds routes.jsonl. */
	final path:String;
}

private final PREFIX_ROUTE:GoJsonStruct = {
	packageName: "main",
	name: "prefixRoute",
	fields: [{tag: "prefix", kind: GoStringField}, {tag: "path", kind: GoStringField}]
};

/** readDoltDatabase's anonymous struct; its decode error text is never shown. */
private final DOLT_DATABASE:GoJsonStruct = {
	packageName: "main",
	name: "metadata",
	fields: [{tag: "dolt_database", kind: GoStringField}]
};

/** bufio.Scanner's default limit: a line of this many bytes or more stops the scan with ErrTooLong. */
private final MAX_SCAN_TOKEN_SIZE = 64 * 1024;

/**
	Upstream extractBeadPrefix (cmd/bd/routed.go:258-268): the ID up to and with
	its first hyphen, or "" when the ID has no hyphen or starts with one.
**/
function beadPrefix(id:String):String {
	final hyphen = id.indexOf("-");
	return hyphen <= 0 ? "" : id.substr(0, hyphen + 1);
}

/**
	Upstream loadPrefixRoutes (cmd/bd/routed.go:270-296) for `beadsDir`.

	Why: upstream reads these rules each time a lookup misses in its own database.
	What: the rules in file order. A line that is blank after Go's TrimSpace, a
	comment line, a line that json.Unmarshal rejects, and a rule without a prefix
	or a path are skipped. A file that cannot be read gives no rules, and so does
	a line too long for bufio.Scanner, because upstream then takes the scan error.
	How: the file splits at line feeds, and each line drops one final carriage
	return, as bufio.ScanLines does.
**/
function loadPrefixRoutes(beadsDir:String):Array<PrefixRoute> {
	final raw = try File.getContent(Path.join([beadsDir, "routes.jsonl"])) catch (_:haxe.Exception) return [];
	final lines = raw.split("\n");
	if (StringTools.endsWith(raw, "\n"))
		lines.pop();
	final routes = new Array<PrefixRoute>();
	for (line in lines) {
		if (Bytes.ofString(line).length >= MAX_SCAN_TOKEN_SIZE)
			return [];
		final text = goTrimSpace(StringTools.endsWith(line, "\r") ? line.substr(0, line.length - 1) : line);
		if (text == "" || StringTools.startsWith(text, "#"))
			continue;
		switch decodeGoStruct(text, PREFIX_ROUTE) {
			case GoJsonDecoded(fields):
				final prefix = fields.get("prefix");
				final path = fields.get("path");
				if (prefix != null && prefix != "" && path != null && path != "")
					routes.push({prefix: prefix, path: path});
			case GoJsonFailed(_) | GoJsonUnsupported:
		}
	}
	return routes;
}

/**
	Upstream readDoltDatabase (cmd/bd/routed.go:298-312): the `dolt_database` of
	`beadsDir`'s metadata.json, or "" when the file cannot be read or decoded.
**/
function routedDoltDatabase(beadsDir:String):String {
	final raw = try File.getContent(Path.join([beadsDir, "metadata.json"])) catch (_:haxe.Exception) return "";
	return switch decodeGoStruct(raw, DOLT_DATABASE) {
		case GoJsonDecoded(fields):
			final database = fields.get("dolt_database");
			database == null ? "" : database;
		case GoJsonFailed(_) | GoJsonUnsupported: "";
	};
}

/**
	Whether upstream's prefix routing (resolveViaPrefixRoutingWithAccess,
	cmd/bd/routed.go:162-246) would open another store for `id`, after the
	lookup missed in the store of `beadsDir`.

	The first rule of `beadsDir`'s routes.jsonl for the ID's prefix names the
	routed workspace, relative to the parent of `beadsDir`. Upstream opens
	that workspace's `.beads`, after FollowRedirect (`follow`, with its
	warnings), when its metadata.json names a dolt_database. A rule for "."
	opens nothing. A rule whose `.beads` is `beadsDir` again (see
	sameDirectory) opens the same store, so the lookup misses again there.
	Without a rule that opens a store, upstream goes on to auto-routing.
**/
function prefixRouteLeaves(beadsDir:String, id:String, follow:String->String):Bool {
	final prefix = beadPrefix(id);
	if (prefix == "")
		return false;
	for (route in loadPrefixRoutes(beadsDir))
		if (route.prefix == prefix) {
			if (route.path == ".")
				return false;
			final routed = follow(FilepathPkg.join(FilepathPkg.dir(beadsDir), route.path, ".beads"));
			return routedDoltDatabase(routed) != "" && !sameDirectory(routed, beadsDir);
		}
	return false;
}
