package beadshx.workspace;

import beadshx.config.ConfigProbes;
import beadshx.config.ConfigShow.readMetadataFields;
import beadshx.config.LayeredConfig;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.config.LayeredConfig.goQuote;
import beadshx.nativeextern.errors.Errors;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.syscall.SyscallPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.JsonValue.GoJsonFieldKind;
import beadshx.store.JsonValue.GoJsonStruct;
import beadshx.store.JsonValue.decodeGoStruct;
import beadshx.workspace.GateLocks;
import beadshx.workspace.WorkspaceGateRules.GateHolder;
import beadshx.workspace.WorkspaceGateRules.busyGateError;
import beadshx.workspace.WorkspaceGateRules.gateAcquisitionWarning;
import beadshx.workspace.WorkspaceGateRules.gateFileName;
import beadshx.workspace.WorkspaceGateRules.gateLockError;
import beadshx.workspace.WorkspaceGateRules.gateOpenError;
import beadshx.workspace.WorkspaceGateRules.gateUnavailableWarning;
import beadshx.workspace.WorkspaceGateRules.isDoltBackend;
import beadshx.workspace.WorkspaceGateRules.isRemoteServerHost;
import beadshx.workspace.WorkspaceGateRules.maintenanceRefusal;
import beadshx.workspace.WorkspaceGateRules.modeTextIsSymlink;
import beadshx.workspace.WorkspaceGateRules.orderGatePaths;
import beadshx.workspace.WorkspaceGateRules.sharedHolderDetail;
import sys.FileSystem;
import sys.io.File;

/** What taking upstream's shared workspace gates found for one command. */
enum WorkspaceGateOutcome {
	/** Each gate whose file exists is held shared until the process ends, or there is nothing to gate. */
	GatesHeld;

	/** Upstream reads without the gates: its warning line for stderr, which --quiet drops. */
	GatesUngated(warning:String);

	/** An exclusive holder, a maintenance operation, has a gate: upstream's error message. */
	GatesBusy(message:String);
}

/** The gate files that one command takes, or why upstream cannot plan them. */
private enum GatePlan {
	GatePaths(paths:Array<String>);
	GatePlanFailed(error:String);
}

/** One gate file path, or upstream's error for the directory it guards. */
private enum GatePath {
	GateFile(path:String);
	GatePathFailed(error:String);
}

/** The physical database roots that upstream gates, or its resolver error. */
private enum PhysicalRoots {
	Roots(roots:Array<String>);
	RootsFailed(error:String);
}

/** A path that upstream resolves, or its error. */
private enum ResolvedPath {
	PathResolved(path:String);
	PathFailed(error:String);
}

/**
	Upstream's workspace gate for the commands that open a store, in the
	read-only profile.

	Why: upstream's root pre-run (cmd/bd/main.go:1332) takes the workspace
	gate and the gates of the physical database roots in shared mode before
	it opens the store (cmd/bd/workspace_gate.go:174). A maintenance
	operation (bd init, bd migrate, bd backup restore) holds them exclusively,
	so upstream refuses to read while it runs.

	What: the same gate files, in the same order, each tried once without a
	wait, with upstream's error and warnings. A gate file that exists is
	opened read-only and locked shared. A missing gate file is one difference:
	upstream creates it (internal/workspacegate/gate.go:390, O_CREATE), and
	this build writes nothing, so it takes no lock on that file.

	How: a port of buildWorkspaceGateSet, doltserver.ResolvePhysicalRoots and
	workspacegate's forDir and AcquireAll. The platform lock comes from
	GateLockAccess. Held locks stay held until the process ends, as upstream
	holds them until the store closes at the end of the command.
**/
@:goNative
final class WorkspaceGate {
	/** The JSON fields of upstream's holder record (workspacegate.Info). */
	static final HOLDER_INFO:GoJsonStruct = {
		packageName: "workspacegate",
		name: "Info",
		fields: [
			{tag: "pid", kind: GoIntField},
			{tag: "hostname", kind: GoStringField},
			{tag: "reason", kind: GoStringField},
			// time.Time decodes a JSON string; the RFC 3339 parse follows.
			{tag: "started_at", kind: GoStringField}
		]
	};

	/**
		The JSON fields of upstream's proxied-server client record
		(configfile.ProxiedServerClientInfo) that decode as strings or ints.
		Its `idle_timeout` duration and `external` object are not read.
	**/
	static final PROXIED_CLIENT_INFO:GoJsonStruct = {
		packageName: "configfile",
		name: "ProxiedServerClientInfo",
		fields: [
			{tag: "root_path", kind: GoStringField},
			{tag: "config_path", kind: GoStringField},
			{tag: "log_path", kind: GoStringField},
			{tag: "port", kind: GoIntField}
		]
	};

	/** Go's time.RFC3339 layout. */
	static inline final RFC3339 = "2006-01-02T15:04:05Z07:00";

	/**
		Upstream acquireCommandWorkspaceGates in shared mode
		(cmd/bd/workspace_gate.go:174) for the `.beads` directory `beadsDir`
		that the command binds, with `config` loaded for that workspace.
		Without the directory there is nothing to gate.
	**/
	public static function takeShared(beadsDir:String, config:LayeredConfig):WorkspaceGateOutcome {
		if (OsPkg.stat(beadsDir).value2 != null)
			return GatesHeld;
		final paths = switch gatePlan(beadsDir, config) {
			case GatePaths(paths): paths;
			case GatePlanFailed(error): return GatesUngated(gateUnavailableWarning(error));
		};
		final held = new Array<GateLock>();
		final system = Sys.systemName();
		for (path in orderGatePaths(paths, system == "Mac" || system == "Windows")) {
			final attempt = switch ConfigProbes.statPath(path) {
				// Upstream opens the file for writing, which fails for a directory.
				case StatDirectory: GateLockOpenFailed(SyscallPkg.eisdir.text());
				case StatNotDirectory | StatMissing | StatFailed(_): GateLockAccess.tryShared(path);
			};
			switch attempt {
				case GateLockHeld(lock):
					held.push(lock);
				case GateLockFileMissing | GateLockUnsupported:
				case GateLockBusy:
					releaseAll(held);
					return GatesBusy(maintenanceRefusal(busyGateError(path, holderDetail(path))));
				case GateLockOpenFailed(error):
					releaseAll(held);
					return GatesUngated(gateAcquisitionWarning(gateOpenError(path, error)));
				case GateLockFailed(error):
					releaseAll(held);
					return GatesUngated(gateAcquisitionWarning(gateLockError(path, error)));
			}
		}
		return GatesHeld;
	}

	/** AcquireAll releases the gates it took, in reverse order, when a later one fails. */
	static function releaseAll(held:Array<GateLock>):Void {
		var index = held.length;
		while (index > 0)
			held[--index].release();
	}

	/**
		Upstream buildWorkspaceGateSet (cmd/bd/workspace_gate.go:146): the
		workspace gate, then the gate of each physical root whose parent
		directory exists.
	**/
	static function gatePlan(beadsDir:String, config:LayeredConfig):GatePlan {
		final absolute = FilepathPkg.abs(beadsDir);
		final absoluteError = absolute.value2;
		if (absoluteError != null)
			return GatePlanFailed('resolving beads dir ${beadsDir}: ${absoluteError.message}');
		final workspaceDirectory = FilepathPkg.clean(absolute.value1);
		final roots = switch physicalRoots(workspaceDirectory, config) {
			case Roots(roots): roots;
			case RootsFailed(error): return GatePlanFailed(error);
		};
		final paths = new Array<String>();
		switch gateFor(workspaceDirectory) {
			case GateFile(path):
				paths.push(path);
			case GatePathFailed(error):
				return GatePlanFailed(error);
		}
		for (root in roots) {
			if (OsPkg.stat(FilepathPkg.dir(root)).value2 != null)
				continue;
			switch gateFor(root) {
				case GateFile(path):
					paths.push(path);
				case GatePathFailed(error):
					return GatePlanFailed(error);
			}
		}
		return GatePaths(paths);
	}

	/**
		Upstream workspacegate forDir (internal/workspacegate/gate.go:162): the
		gate file beside `directory`, in its parent with symbolic links
		resolved. A guarded directory that is a symbolic link is refused.
	**/
	static function gateFor(directory:String):GatePath {
		final absolute = FilepathPkg.abs(directory);
		final absoluteError = absolute.value2;
		if (absoluteError != null)
			return GatePathFailed('workspacegate: resolving ${directory}: ${absoluteError.message}');
		final guarded = FilepathPkg.clean(absolute.value1);
		final link = OsPkg.lstat(guarded);
		final linkInformation = link.value1;
		if (link.value2 == null && linkInformation != null && modeTextIsSymlink(linkInformation.mode().toString()))
			return GatePathFailed('workspacegate: ${guarded} is a symlink; gate the physical directory it points to');
		final split = FilepathPkg.split(guarded);
		final parent = split.value1;
		final base = split.value2;
		switch base {
			case "" | "." | "..":
				return GatePathFailed('workspacegate: cannot gate ${goQuote(directory)}: the guarded path must be a named directory');
			case _:
		}
		final canonical = FilepathPkg.evalSymlinks(FilepathPkg.clean(parent));
		final canonicalError = canonical.value2;
		if (canonicalError != null)
			return GatePathFailed('workspacegate: gate parent ${parent} must exist: ${canonicalError.message}');
		return GateFile(FilepathPkg.join(canonical.value1, gateFileName(base)));
	}

	/**
		Upstream doltserver.ResolvePhysicalRoots (internal/doltserver/physical_root.go:247)
		for the absolute `.beads` directory `beadsDir`: the data directory of
		the store that the command opens. It reads metadata.json only when it
		exists, so a legacy config.json counts as no metadata.
	**/
	static function physicalRoots(beadsDir:String, config:LayeredConfig):PhysicalRoots {
		var metadata:Null<Map<String, String>> = null;
		if (ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "metadata.json")))
			switch readMetadataFields(beadsDir) {
				case MetadataFields(fields):
					metadata = fields;
				case MetadataFieldsUndecodable(error):
					return RootsFailed('loading config for gate resolution: ${error}');
				// The command already stopped for a file that the typed parser cannot read.
				case MetadataFieldsUnsupported | MetadataAbsent | MetadataFieldsLegacyOnly:
					metadata = new Map<String, String>();
			}
		final fields = metadata == null ? new Map<String, String>() : metadata;
		final dolt = metadata != null && isDoltBackend(field(fields, "backend"));
		final doltMode = field(fields, "dolt_mode");
		if (dolt && doltMode.toLowerCase() == "proxied-server")
			return switch proxiedServerRoot(beadsDir, config) {
				case PathResolved(root): rootList(root);
				case PathFailed(error): RootsFailed('resolving proxied-server root: ${error}');
			};
		if (config.sharedServerMode())
			return switch sharedDoltPath() {
				case PathResolved(root): rootList(root);
				case PathFailed(error): RootsFailed('resolving shared-server root: ${error}');
			};
		if (dolt && config.doltServerMode(doltMode, field(fields, "dolt_server_host")))
			return isRemoteServerHost(doltServerHost(fields, config)) ? Roots([]) : rootList(ConfigProbes.doltDirectory(beadsDir, fields));
		final embedded = FilepathPkg.join(beadsDir, "embeddeddolt");
		if (metadata != null)
			return rootList(embedded);
		// No metadata.json: the open path's discovery, which defaults to the embedded root.
		return switch [
			ConfigProbes.statPath(embedded),
			ConfigProbes.statPath(FilepathPkg.join(beadsDir, "dolt"))
		] {
			case [StatDirectory, _]: rootList(embedded);
			case [_, StatDirectory]: rootList(FilepathPkg.join(beadsDir, "dolt"));
			case _: rootList(embedded);
		};
	}

	/** Upstream's addRoot: the root as an absolute, cleaned path. */
	static function rootList(root:String):PhysicalRoots {
		final absolute = FilepathPkg.abs(root);
		final absoluteError = absolute.value2;
		if (absoluteError != null)
			return RootsFailed('resolving physical root ${root}: ${absoluteError.message}');
		return Roots([FilepathPkg.clean(absolute.value1)]);
	}

	/** Upstream configfile GetDoltServerHost: BEADS_DOLT_SERVER_HOST, dolt_server_host, the dolt.host setting, then 127.0.0.1. */
	static function doltServerHost(fields:Map<String, String>, config:LayeredConfig):String {
		for (host in [
			environmentValue("BEADS_DOLT_SERVER_HOST"),
			field(fields, "dolt_server_host"),
			config.getString("dolt.host")
		])
			if (host != "")
				return host;
		return "127.0.0.1";
	}

	/**
		Upstream ResolveProxiedServerRootPath (internal/doltserver/physical_root.go:113):
		BEADS_PROXIED_SERVER_ROOT_PATH, then the root_path of
		.beads/proxied_server_client_info.json, then DoltDirPath. A relative
		path is joined to `beadsDir`.
	**/
	static function proxiedServerRoot(beadsDir:String, config:LayeredConfig):ResolvedPath {
		final variable = environmentValue("BEADS_PROXIED_SERVER_ROOT_PATH");
		if (variable != "")
			return PathResolved(FilepathPkg.isAbs(variable) ? variable : FilepathPkg.join(beadsDir, variable));
		final name = "proxied_server_client_info.json";
		final sidecar = FilepathPkg.join(beadsDir, name);
		if (FileSystem.exists(sidecar)) {
			var raw = "";
			try {
				raw = File.getContent(sidecar);
			} catch (error:haxe.Exception) {
				return PathFailed('reading ${name}: ${error.message}');
			}
			switch decodeGoStruct(raw, PROXIED_CLIENT_INFO) {
				case GoJsonDecoded(fields):
					final root = field(fields, "root_path");
					if (root != "")
						return PathResolved(FilepathPkg.isAbs(root) ? root : FilepathPkg.join(beadsDir, root));
				case GoJsonFailed(message):
					return PathFailed('parsing ${name}: ${message}');
				case GoJsonUnsupported:
			}
		}
		if (config.sharedServerMode())
			switch sharedDoltPath() {
				case PathResolved(root):
					return PathResolved(root);
				// Upstream falls through to the workspace's own directory.
				case PathFailed(_):
			}
		return PathResolved(projectDoltDirPath(beadsDir));
	}

	/**
		Upstream projectDoltDirPath (internal/doltserver/physical_root.go:61):
		BEADS_DOLT_DATA_DIR, then the data directory of a metadata.json that
		loads, then `.beads/dolt`.
	**/
	static function projectDoltDirPath(beadsDir:String):String {
		final variable = environmentValue("BEADS_DOLT_DATA_DIR");
		if (variable != "")
			return FilepathPkg.isAbs(variable) ? variable : FilepathPkg.join(beadsDir, variable);
		if (ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "metadata.json")))
			switch readMetadataFields(beadsDir) {
				case MetadataFields(fields):
					return ConfigProbes.doltDirectory(beadsDir, fields);
				case MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataAbsent | MetadataFieldsLegacyOnly:
			}
		return FilepathPkg.join(beadsDir, "dolt");
	}

	/** Upstream SharedDoltPath: BEADS_SHARED_SERVER_DIR, or ~/.beads/shared-server, then `dolt`, with no directory created. */
	static function sharedDoltPath():ResolvedPath {
		final variable = environmentValue("BEADS_SHARED_SERVER_DIR");
		if (variable != "")
			return PathResolved(FilepathPkg.join(variable, "dolt"));
		final home = OsPkg.userHomeDir();
		final homeError = home.value2;
		if (homeError != null)
			return PathFailed('cannot determine home directory: ${homeError.message}');
		return PathResolved(FilepathPkg.join(home.value1, ".beads", "shared-server", "dolt"));
	}

	/**
		Upstream Gate.busyDetail for a shared try (internal/workspacegate/gate.go:257):
		the holder record beside the gate file, unless it names this host and
		a process that has ended.
	**/
	static function holderDetail(gatePath:String):String {
		final holder = readHolder(gatePath + ".info");
		if (holder == null)
			return sharedHolderDetail(null, false);
		final host = OsPkg.hostname();
		final hostname = host.value2 == null ? host.value1 : "";
		return sharedHolderDetail(holder, hostname == holder.hostname && !processAlive(holder.pid));
	}

	/** Upstream Gate.readInfo: the record, or null when it does not read or json.Unmarshal fails. */
	static function readHolder(path:String):Null<GateHolder> {
		final raw:Null<String> = try File.getContent(path) catch (_:haxe.Exception) null;
		if (raw == null)
			return null;
		final fields = switch decodeGoStruct(raw, HOLDER_INFO) {
			case GoJsonDecoded(fields): fields;
			case GoJsonFailed(_) | GoJsonUnsupported: return null;
		};
		var startedAt = "";
		final started = fields.get("started_at");
		if (started != null) {
			final parsed = TimePkg.parse(RFC3339, started);
			if (parsed.value2 != null)
				return null;
			final utc = parsed.value1.utc();
			if (!utc.isZero())
				startedAt = utc.format(RFC3339);
		}
		final pid = fields.get("pid");
		return {
			pid: pid == null ? "0" : pid,
			hostname: field(fields, "hostname"),
			reason: field(fields, "reason"),
			startedAt: startedAt
		};
	}

	/**
		Upstream pidAlive (internal/workspacegate/gate.go:300): signal 0 reaches
		the process. An ended process or `ESRCH` means it is gone; any other
		error, such as `EPERM`, counts as alive.
	**/
	static function processAlive(pidText:String):Bool {
		final pid = StrconvPkg.atoi(pidText);
		if (pid.value2 != null || pid.value1 <= 0)
			return false;
		final found = OsPkg.findProcess(pid.value1);
		final process = found.value1;
		if (found.value2 != null || process == null)
			return false;
		final error = process.signal(SyscallPkg.signal(0));
		if (error == null)
			return true;
		return !(Errors.matches(error, OsPkg.errProcessDone) || Errors.matches(error, SyscallPkg.esrch));
	}

	static function field(fields:Map<String, String>, tag:String):String {
		final value = fields.get(tag);
		return value == null ? "" : value;
	}
}
