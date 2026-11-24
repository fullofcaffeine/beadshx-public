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

/**
	Pins the pure rules of upstream's workspace gate (internal/workspacegate
	and cmd/bd/workspace_gate.go), by hand. The parity suite holds real
	locks; a stale holder record needs this host's name, which no fixture
	may carry, so it is covered here.
**/
class Main {
	static function main():Void {
		orderContracts();
		holderContracts();
		messageContracts();
		classificationContracts();
		Sys.println("workspace gate Haxe contracts: PASS");
	}

	static function orderContracts():Void {
		equal(gateFileName(".beads"), ".beads.gate.lock");
		equal(gateFileName("dolt"), "dolt.gate.lock");
		// `.` sorts before `/`, so the workspace gate comes before the gates inside .beads.
		equal(orderGatePaths(["/w/.beads/embeddeddolt.gate.lock", "/w/.beads.gate.lock"], false).join(","),
			"/w/.beads.gate.lock,/w/.beads/embeddeddolt.gate.lock");
		// Equal paths collapse to one gate.
		equal(orderGatePaths(["/w/.beads.gate.lock", "/w/.beads.gate.lock"], false).join(","), "/w/.beads.gate.lock");
		// Where the file system ignores case, spellings of one key collapse; the last one stays.
		equal(orderGatePaths(["/W/a.gate.lock", "/w/A.gate.lock", "/w/b.gate.lock"], true).join(","), "/w/A.gate.lock,/w/b.gate.lock");
		equal(orderGatePaths(["/W/a.gate.lock", "/w/A.gate.lock"], false).join(","), "/W/a.gate.lock,/w/A.gate.lock");
		equal(orderGatePaths([], true).length, 0);
	}

	static function holderContracts():Void {
		equal(sharedHolderDetail(null, false), "another bd process (no holder info recorded)");
		final full:GateHolder = {
			pid: "4242",
			hostname: "fixture-host",
			reason: "bd backup restore",
			startedAt: "2026-01-02T01:04:05Z"
		};
		equal(sharedHolderDetail(full, false), "pid 4242 on fixture-host (bd backup restore) since 2026-01-02T01:04:05Z");
		equal(sharedHolderDetail(full, true), "other bd processes (a stale exclusive-holder record from dead pid 4242 was ignored)");
		equal(sharedHolderDetail({
			pid: "0",
			hostname: "",
			reason: "",
			startedAt: ""
		}, false), "pid 0");
		equal(sharedHolderDetail({
			pid: "7",
			hostname: "",
			reason: "bd init",
			startedAt: ""
		}, false), "pid 7 (bd init)");
	}

	static function messageContracts():Void {
		final busy = busyGateError("/w/.beads.gate.lock", "another bd process (no holder info recorded)");
		equal(busy, "workspacegate: /w/.beads.gate.lock (shared mode) held by another bd process (no holder info recorded): workspace gate busy");
		equal(maintenanceRefusal(busy), "a maintenance operation is running on this workspace; retry when it completes: " + busy);
		equal(gateUnavailableWarning("workspacegate: /w/.beads is a symlink; gate the physical directory it points to"),
			"warning: workspace gate unavailable, continuing ungated: workspacegate: /w/.beads is a symlink; gate the physical directory it points to\n");
		equal(gateAcquisitionWarning(gateOpenError("/w/.beads.gate.lock", "is a directory")),
			"warning: workspace gate acquisition failed, continuing ungated: workspacegate: open gate /w/.beads.gate.lock: open /w/.beads.gate.lock: is a directory\n");
		equal(gateLockError("/w/.beads.gate.lock", "operation not supported"), "workspacegate: lock /w/.beads.gate.lock: operation not supported");
	}

	static function classificationContracts():Void {
		equal(modeTextIsSymlink("Lrwxr-xr-x"), true);
		equal(modeTextIsSymlink("drwx------"), false);
		equal(modeTextIsSymlink("-rw-------"), false);
		equal(modeTextIsSymlink("----------"), false);
		// Each type bit prints one letter before the nine permission letters.
		equal(modeTextIsSymlink("dL---------"), true);
		equal(modeTextIsSymlink("dL--------"), false);
		for (host in ["", "localhost", "127.0.0.1", "::1", "[::1]", " LocalHost "])
			equal(isRemoteServerHost(host), false);
		// Unlike configfile.IsLocalHostString, the gate resolver counts 0.0.0.0 as remote.
		for (host in ["0.0.0.0", "db.example.invalid", "10.0.0.2"])
			equal(isRemoteServerHost(host), true);
		for (backend in ["", "dolt", "Dolt", "unknown"])
			equal(isDoltBackend(backend), true);
		for (backend in ["postgres", "mysql", "sqlite"])
			equal(isDoltBackend(backend), false);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
