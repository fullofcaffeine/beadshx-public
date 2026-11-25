package beadshx.workspace;

import beadshx.config.LayeredConfig.goQuote;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.strings.StringsPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.workspace.WorkspaceGateRules.modeTextIsSymlink;
import haxe.Int64;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

/**
	Upstream guardLegacyUpgradeWorkspace (cmd/bd/legacy_upgrade_guard.go:24-69)
	after its LoadForDiscovery step, which Application.checkWorkspaceMetadata
	runs.

	Why: upstream's pre-run refuses pre-Dolt and legacy-Dolt workspaces, and
	workspaces with a removed or unknown backend, before it tracks a version,
	migrates metadata or opens a store. So it writes nothing there, and `where`
	and every command that opens a store stop with this error.

	What: `refusal` gives, for the `.beads` directory `beadsDir`, the error
	that upstream prints after `Error: ` in every output mode, or null when
	the command goes on. `metadata` holds the decoded fields of metadata.json,
	or null when the workspace has none (LoadForDiscovery's nil config).
	`sharedServer` tells whether shared-server mode is on in the config that
	upstream's setup reloaded for the directory. It is asked only for a local
	Dolt root.

	How: it only reads: os.Lstat, the entries of `.beads` and of
	`.beads/embeddeddolt`, the first 16 bytes of a SQLite file, and the bounded
	`.beads/.local_version` witness.
**/
@:goNative
final class LegacyUpgradeGuard {
	public static function refusal(beadsDir:String, metadata:Null<Map<String, String>>, sharedServer:() -> Bool):Null<String> {
		if (isHistoricalSqliteWorkspace(beadsDir, metadata))
			return refusalText("historical SQLite workspace");
		if (metadata != null) {
			final backendError = configuredBackendError(field(metadata, "backend"));
			if (backendError != null)
				return backendError;
		}
		final mode = metadata == null ? "" : field(metadata, "dolt_mode");
		final serverMode = StringsPkg.equalFold(mode, "server");
		if (hasEmbeddedRepository(beadsDir) && !serverMode)
			return null;
		final version = versionWitness(beadsDir);
		final legacyServer = version != null && legacyServerVersion(version);
		if (serverMode && legacyServer)
			return refusalText('legacy Dolt server workspace from bd ${version}');
		if (!isPlainDirectory(FilepathPkg.join(beadsDir, "dolt")))
			return null;
		if (serverMode)
			return version != null && currentVersionWitness(version) ? null : refusalText("legacy Dolt server workspace");
		if (mode != "" && !StringsPkg.equalFold(mode, "embedded"))
			return null;
		if (sharedServer() && !legacyServer)
			return null;
		return refusalText(version != null
			&& legacyVersionMinor(version) != null ? 'legacy Dolt workspace from bd ${version}' : "legacy Dolt workspace");
	}

	/** Upstream legacyUpgradeRefusalError's text. */
	static function refusalText(reason:String):String {
		return '${reason} detected; explicit migration is required before this bd version can open or modify the workspace. '
			+ "Preserve .beads unchanged and follow docs/getting-started/upgrading.md#cross-era-upgrades";
	}

	static function field(metadata:Map<String, String>, tag:String):String {
		final value = metadata.get(tag);
		return value == null ? "" : value;
	}

	/** Upstream configfile.RemovedSQLiteRationale. */
	static final REMOVED_SQLITE_RATIONALE = "the SQLite backend was rolled back to consolidate storage on a single engine and dialect "
		+ "and keep Beads simple and robust";

	/** Upstream configfile.RemovedBackendRationale, for PostgreSQL and MySQL. */
	static final REMOVED_BACKEND_RATIONALE = "direct support for general-purpose server databases was rolled back to keep Beads simple and resource-light";

	/**
		Upstream validateConfiguredBackend (cmd/bd/backend_support.go:10) for the
		raw `backend` of metadata.json: RemovedBackendError or UnknownBackendError
		(internal/configfile/backend_messages.go), or null for `dolt` and an unset
		backend. This build registers no other backend.
	**/
	static function configuredBackendError(backend:String):Null<String> {
		return switch backend {
			case "" | "dolt": null;
			case "postgres" | "mysql" | "sqlite":
				final rationale = backend == "sqlite" ? REMOVED_SQLITE_RATIONALE : REMOVED_BACKEND_RATIONALE;
				'storage backend ${goQuote(backend)} is no longer supported: ${rationale}; the configured ${backend} database was not opened or modified; ' +
				'export it with a bd version that supports ${backend}, then follow bd help init-safety to reinitialize with Dolt and import the exported data';
			case _:
				'storage backend ${goQuote(backend)} in metadata.json is not recognized or supported; no storage database was opened or modified; ' +
				'the supported backend is "dolt"; fix or restore metadata.json and retry';
		};
	}

	/** Upstream isHistoricalSQLiteWorkspace (legacy_upgrade_guard.go:73). */
	static function isHistoricalSqliteWorkspace(beadsDir:String, metadata:Null<Map<String, String>>):Bool {
		if (hasEmbeddedRepository(beadsDir))
			return false;
		return metadata != null ? configuredHistoricalSqlite(beadsDir, metadata) : discoveredHistoricalSqlite(beadsDir);
	}

	/**
		Upstream configuredHistoricalSQLiteWorkspace: metadata that names no Dolt
		setting and a SQLite backend or none, whose database (sqlite_path, else
		database, else `beads.db`) is a plain name of a non-empty regular file.
	**/
	static function configuredHistoricalSqlite(beadsDir:String, metadata:Map<String, String>):Bool {
		final backend = field(metadata, "backend");
		if (backend != "" && backend != "sqlite")
			return false;
		if (field(metadata, "dolt_mode") != "" || field(metadata, "dolt_database") != "")
			return false;
		var name = field(metadata, "sqlite_path");
		if (name == "")
			name = field(metadata, "database");
		if (name == "")
			name = "beads.db";
		return FilepathPkg.base(name) == name && isNonEmptyRegularFile(FilepathPkg.join(beadsDir, name));
	}

	/**
		Upstream discoveredHistoricalSQLiteWorkspace for a workspace without
		metadata.json: one non-empty regular `.db` file with a SQLite header, no
		symbolic link, and no entry beyond that file, its `-wal` and `-shm` files,
		`issues.jsonl` and an `embeddeddolt` directory.
	**/
	static function discoveredHistoricalSqlite(beadsDir:String):Bool {
		final entries = try FileSystem.readDirectory(beadsDir) catch (_:haxe.Exception) null;
		if (entries == null)
			return false;
		var database = "";
		for (name in entries) {
			final path = FilepathPkg.join(beadsDir, name);
			if (isSymbolicLink(path))
				return false;
			if (!StringTools.endsWith(name, ".db"))
				continue;
			if (!isNonEmptyRegularFile(path) || database != "")
				return false;
			database = name;
		}
		if (database == "" || !hasSqliteHeader(FilepathPkg.join(beadsDir, database)))
			return false;
		for (name in entries) {
			final path = FilepathPkg.join(beadsDir, name);
			if (name == "embeddeddolt" && isPlainDirectory(path))
				continue;
			if (name == database || name == "issues.jsonl" || name == database + "-wal" || name == database + "-shm") {
				if (!isRegularFile(path))
					return false;
				continue;
			}
			return false;
		}
		return true;
	}

	/** Upstream hasSQLiteHeader: a non-empty regular file whose first 16 bytes are `SQLite format 3` and a zero byte. */
	static function hasSqliteHeader(path:String):Bool {
		if (!isNonEmptyRegularFile(path))
			return false;
		final expected = Bytes.alloc(16);
		expected.blit(0, Bytes.ofString("SQLite format 3"), 0, 15);
		try {
			final input = File.read(path, true);
			final header = try input.read(16) catch (_:haxe.Exception) null;
			input.close();
			return header != null && header.compare(expected) == 0;
		} catch (_:haxe.Exception) {
			return false;
		}
	}

	/**
		Upstream embeddeddolt.HasRepository (internal/storage/embeddeddolt/detection.go:12):
		`.beads/embeddeddolt` is a directory, not a link, with a database directory
		whose `.dolt` directory has an entry.
	**/
	static function hasEmbeddedRepository(beadsDir:String):Bool {
		final root = FilepathPkg.join(beadsDir, "embeddeddolt");
		if (!isPlainDirectory(root))
			return false;
		final databases = try FileSystem.readDirectory(root) catch (_:haxe.Exception) null;
		if (databases == null)
			return false;
		for (database in databases) {
			final marker = FilepathPkg.join(root, database, ".dolt");
			if (!isPlainDirectory(FilepathPkg.join(root, database)) || !isPlainDirectory(marker))
				continue;
			final entries = try FileSystem.readDirectory(marker) catch (_:haxe.Exception) null;
			if (entries != null && entries.length > 0)
				return true;
		}
		return false;
	}

	/**
		Upstream legacyUpgradeVersionWitness: the trimmed text of
		`.beads/.local_version` when it is a regular file of 1 to 64 bytes that is
		not blank, or null.
	**/
	static function versionWitness(beadsDir:String):Null<String> {
		final path = FilepathPkg.join(beadsDir, ".local_version");
		final size = regularFileSize(path);
		if (size == null || size <= 0 || size > 64)
			return null;
		final data = try File.getBytes(path) catch (_:haxe.Exception) null;
		if (data == null || data.length != Int64.toInt(size))
			return null;
		final version = goTrimSpace(data.toString());
		return version == "" ? null : version;
	}

	/** Upstream legacyServerVersion: a 0.55 to 0.62 release. */
	static function legacyServerVersion(version:String):Bool {
		final minor = legacyVersionMinor(version);
		return minor != null && minor >= 55 && minor <= 62;
	}

	/** Upstream currentVersionWitness: three non-negative numbers, the first at least 1, after an optional `v`. */
	static function currentVersionWitness(version:String):Bool {
		final parts = versionParts(version);
		if (parts.length != 3)
			return false;
		final values = new Array<Int>();
		for (part in parts) {
			final parsed = StrconvPkg.atoi(part);
			if (parsed.value2 != null || parsed.value1 < 0)
				return false;
			values.push(parsed.value1);
		}
		return values[0] >= 1;
	}

	/** Upstream legacyVersionMinor: the minor number of a `0.<minor>.<patch>` version, after an optional `v`, or null. */
	static function legacyVersionMinor(version:String):Null<Int> {
		final parts = versionParts(version);
		if (parts.length != 3 || parts[0] != "0")
			return null;
		final minor = StrconvPkg.atoi(parts[1]);
		if (minor.value2 != null || StrconvPkg.atoi(parts[2]).value2 != null)
			return null;
		return minor.value1;
	}

	/** strings.Split of the version without one leading `v`, at each `.`. */
	static function versionParts(version:String):Array<String> {
		return (StringTools.startsWith(version, "v") ? version.substr(1) : version).split(".");
	}

	/** os.Lstat: a directory, which a symbolic link never is. */
	static function isPlainDirectory(path:String):Bool {
		final result = OsPkg.lstat(path);
		final information = result.value1;
		return result.value2 == null && information != null && information.isDir();
	}

	static function isSymbolicLink(path:String):Bool {
		final result = OsPkg.lstat(path);
		final information = result.value1;
		return result.value2 == null && information != null && modeTextIsSymlink(information.mode().toString());
	}

	/** os.Lstat: the size of a regular file, or null for anything else. */
	static function regularFileSize(path:String):Null<Int64> {
		final result = OsPkg.lstat(path);
		final information = result.value1;
		if (result.value2 != null || information == null || !information.mode().isRegular())
			return null;
		return Int64.parseString(StrconvPkg.formatInt(information.size(), 10));
	}

	static function isRegularFile(path:String):Bool {
		return regularFileSize(path) != null;
	}

	static function isNonEmptyRegularFile(path:String):Bool {
		final size = regularFileSize(path);
		return size != null && size > 0;
	}
}
