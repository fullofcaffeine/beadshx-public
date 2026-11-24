package beadshx.workspace;

import beadshx.store.CustomConfig.goTrimSpace;

/**
	The advisory holder record that an exclusive gate holder writes beside
	the gate file (upstream workspacegate.Info, internal/workspacegate/gate.go:225),
	as decoded: each field as upstream prints it.
**/
typedef GateHolder = {
	/** The `pid` member in decimal; "0" when it is absent. */
	final pid:String;

	final hostname:String;
	final reason:String;

	/** `started_at` in UTC as RFC 3339, or "" for Go's zero time. */
	final startedAt:String;
}

/** The name of the gate file beside a guarded directory with base name `base` (upstream gateFileName, gate.go:152). */
function gateFileName(base:String):String {
	return base + ".gate.lock";
}

/**
	The gate paths in the order upstream's AcquireAll takes them
	(internal/workspacegate/gate.go:514): one path for each comparison key,
	the last spelling of a key kept, sorted by key. The key is the path, in
	lower case where the file system ignores case (`foldsCase`, upstream
	gateKey on macOS and Windows).
**/
function orderGatePaths(paths:Array<String>, foldsCase:Bool):Array<String> {
	final byKey = new Map<String, String>();
	final keys = new Array<String>();
	for (path in paths) {
		final key = foldsCase ? path.toLowerCase() : path;
		if (!byKey.exists(key))
			keys.push(key);
		byKey.set(key, path);
	}
	keys.sort((left, right) -> left < right ? -1 : left == right ? 0 : 1);
	return [for (key in keys) byKey.get(key)];
}

/**
	Upstream Gate.busyDetail for a shared try (gate.go:257): who holds the
	gate, from the holder record. `stale` says that the record names this
	host and a process that has ended.
**/
function sharedHolderDetail(holder:Null<GateHolder>, stale:Bool):String {
	if (holder == null)
		return "another bd process (no holder info recorded)";
	if (stale)
		return 'other bd processes (a stale exclusive-holder record from dead pid ${holder.pid} was ignored)';
	var detail = 'pid ${holder.pid}';
	if (holder.hostname != "")
		detail += ' on ${holder.hostname}';
	if (holder.reason != "")
		detail += ' (${holder.reason})';
	if (holder.startedAt != "")
		detail += ' since ${holder.startedAt}';
	return detail;
}

/** Upstream's error for a shared try that an exclusive holder blocks (gate.go:423). */
function busyGateError(path:String, detail:String):String {
	return 'workspacegate: ${path} (shared mode) held by ${detail}: workspace gate busy';
}

/** Upstream's refusal of a command while a maintenance operation holds a gate (cmd/bd/workspace_gate.go:213). */
function maintenanceRefusal(error:String):String {
	return 'a maintenance operation is running on this workspace; retry when it completes: ${error}';
}

/** Upstream's warning when it cannot plan the gates and reads without them (cmd/bd/workspace_gate.go:190). */
function gateUnavailableWarning(error:String):String {
	return 'warning: workspace gate unavailable, continuing ungated: ${error}\n';
}

/** Upstream's warning when a gate fails to open or lock for another reason than a holder (cmd/bd/workspace_gate.go:219). */
function gateAcquisitionWarning(error:String):String {
	return 'warning: workspace gate acquisition failed, continuing ungated: ${error}\n';
}

/** Upstream's error for a gate file that does not open (gate.go:392); `error` is the open error's text. */
function gateOpenError(path:String, error:String):String {
	return 'workspacegate: open gate ${path}: open ${path}: ${error}';
}

/** Upstream's error for a lock call that fails for another reason than a holder (gate.go:412). */
function gateLockError(path:String, error:String):String {
	return 'workspacegate: lock ${path}: ${error}';
}

/**
	Whether a Go `FileMode.String` text names a symbolic link. Go prints one
	letter for each type bit, `L` for ModeSymlink, and then the nine
	permission letters.
**/
function modeTextIsSymlink(mode:String):Bool {
	return mode.length > 9 && mode.substr(0, mode.length - 9).indexOf("L") >= 0;
}

/** Upstream doltserver isRemoteServerHost (internal/doltserver/physical_root.go:168). */
function isRemoteServerHost(host:String):Bool {
	return switch goTrimSpace(host).toLowerCase() {
		case "" | "localhost" | "127.0.0.1" | "::1" | "[::1]": false;
		case _: true;
	};
}

/** Upstream configfile GetBackend (internal/configfile/configfile.go:297): this binary registers no other backend. */
function isDoltBackend(backend:String):Bool {
	return switch backend {
		case "postgres" | "mysql" | "sqlite": false;
		case _: true;
	};
}
