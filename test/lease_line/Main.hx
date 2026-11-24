import beadshx.cli.LeaseLine.formatTimeAgo;
import beadshx.cli.LeaseLine.formatTimeUntil;
import beadshx.cli.LeaseLine.leaseLine;
import beadshx.store.IssueLease;

/**
	Pins upstream's show `Lease:` line (cmd/bd/show_format.go:129-148) and its
	relative times, formatTimeUntil and formatTimeAgo (cmd/bd/wisp.go:547-606),
	by hand. A fixed measure stands in for the clock; parity covers the real
	runs, with leases that the fixture writes far from these bucket edges.
**/
class Main {
	static function main():Void {
		untilContracts();
		agoContracts();
		lineContracts();
		Sys.println("lease line Haxe contracts: PASS");
	}

	static function untilContracts():Void {
		equal(formatTimeUntil(0), "expired");
		equal(formatTimeUntil(-90), "expired");
		equal(formatTimeUntil(0.5), "in <1 min");
		equal(formatTimeUntil(59.9), "in <1 min");
		equal(formatTimeUntil(60), "in 1 min");
		equal(formatTimeUntil(119.9), "in 1 min");
		equal(formatTimeUntil(120), "in 2 mins");
		equal(formatTimeUntil(3599.9), "in 59 mins");
		equal(formatTimeUntil(3600), "in 1 hour");
		equal(formatTimeUntil(7199.9), "in 1 hour");
		equal(formatTimeUntil(7200), "in 2 hours");
		equal(formatTimeUntil(86399.9), "in 23 hours");
		equal(formatTimeUntil(86400), "in 1 day");
		equal(formatTimeUntil(172800), "in 2 days");
		equal(formatTimeUntil(30 * 86400 + 5), "in 30 days");
	}

	static function agoContracts():Void {
		// A heartbeat in the future counts as now.
		equal(formatTimeAgo(-3600, "2026-01-01"), "just now");
		equal(formatTimeAgo(0, "2026-01-01"), "just now");
		equal(formatTimeAgo(59.9, "2026-01-01"), "just now");
		equal(formatTimeAgo(60, "2026-01-01"), "1 min ago");
		equal(formatTimeAgo(150, "2026-01-01"), "2 mins ago");
		equal(formatTimeAgo(3600, "2026-01-01"), "1 hour ago");
		equal(formatTimeAgo(5400, "2026-01-01"), "1 hour ago");
		equal(formatTimeAgo(7200, "2026-01-01"), "2 hours ago");
		equal(formatTimeAgo(86400, "2026-01-01"), "1 day ago");
		equal(formatTimeAgo(7 * 86400 - 1, "2026-01-01"), "6 days ago");
		// After a week, the date of the heartbeat.
		equal(formatTimeAgo(7 * 86400, "2026-01-01"), "2026-01-01");
	}

	static function lineContracts():Void {
		final expiry = "2026-11-25T03:00:00Z";
		final heartbeat = "2026-11-20T01:30:00.5Z";
		final measured = new Map<String, Float>();
		measured.set(expiry, 3 * 3600 + 1800);
		measured.set(heartbeat, -(2 * 86400 + 600));
		final measure = (instant:String) -> measured.get(instant);
		final full = lease(expiry, heartbeat, "");
		final none = () -> "";
		final nodeA = () -> "node-a";
		equal(leaseLine("in_progress", full, none, measure), "Lease: expires in 3 hours (heartbeat 2 days ago)");
		// Only an in-progress issue with an expiry has the line.
		equal(leaseLine("open", full, none, measure), null);
		equal(leaseLine("in_progress", lease("", heartbeat, ""), none, measure), null);
		equal(leaseLine("in_progress", lease(expiry, "", ""), none, measure), "Lease: expires in 3 hours");
		// The granting replica counts only when this node has a name and the lease names another one.
		equal(leaseLine("in_progress", lease(expiry, "", "node-b"), none, measure), "Lease: expires in 3 hours");
		equal(leaseLine("in_progress", lease(expiry, "", ""), nodeA, measure), "Lease: expires in 3 hours");
		equal(leaseLine("in_progress", lease(expiry, "", "node-a"), nodeA, measure), "Lease: expires in 3 hours");
		equal(leaseLine("in_progress", lease(expiry, heartbeat, "node-b"), nodeA, measure),
			"Lease: expires in 3 hours (heartbeat 2 days ago) — granted by replica node-b");
		// The date after a week is the date in the heartbeat's own offset.
		final old = "2026-01-01T23:30:00-05:00";
		measured.set(old, -(30 * 86400));
		equal(leaseLine("in_progress", lease(expiry, old, ""), none, measure), "Lease: expires in 3 hours (heartbeat 2026-01-01)");
		// A time that does not parse prints no lease line, or no heartbeat part.
		equal(leaseLine("in_progress", lease("bogus", heartbeat, ""), none, measure), null);
		equal(leaseLine("in_progress", lease(expiry, "bogus", ""), none, measure), "Lease: expires in 3 hours");
	}

	static function lease(expiresAt:String, heartbeatAt:String, grantedNode:String):IssueLease {
		return {leaseExpiresAt: expiresAt, heartbeatAt: heartbeatAt, leaseGrantedNode: grantedNode};
	}

	static function equal<T>(actual:T, expected:T, ?pos:haxe.PosInfos):Void {
		if (actual != expected)
			throw '${pos.fileName}:${pos.lineNumber}: expected ${expected}, got ${actual}';
	}
}
