package beadshx.cli;

import beadshx.store.IssueLease;

/**
	Upstream's show `Lease:` line (cmd/bd/show_format.go:129-148).

	Why: a claimed issue holds a lease that expires unless its owner sends
	heartbeats, and show names both times relative to now. What: for an
	in-progress issue with a lease expiry, `Lease: expires <until>`, then
	` (heartbeat <ago>)` when the lease has a heartbeat, then
	` — granted by replica <node>` when this node has a `node_id` and the lease
	names another node. How: `measure` gives the seconds from now to an RFC 3339
	instant, positive in the future, or null when the instant does not parse.
	`localNode` reads this node's `node_id`, only for a lease that names its
	node. The line is plain text: like upstream, show mutes all of it.
**/
function leaseLine(status:String, lease:IssueLease, localNode:() -> String, measure:String->Null<Float>):Null<String> {
	if (status != "in_progress" || lease.leaseExpiresAt == "")
		return null;
	final untilExpiry = measure(lease.leaseExpiresAt);
	if (untilExpiry == null)
		return null;
	var line = 'Lease: expires ${formatTimeUntil(untilExpiry)}';
	if (lease.heartbeatAt != "") {
		final untilHeartbeat = measure(lease.heartbeatAt);
		// Go's Time.Format("2006-01-02") prints the date in the time's own offset, which RFC 3339 starts with.
		if (untilHeartbeat != null)
			line += ' (heartbeat ${formatTimeAgo(-untilHeartbeat, lease.heartbeatAt.substr(0, 10))})';
	}
	if (lease.leaseGrantedNode != "") {
		final local = localNode();
		if (local != "" && lease.leaseGrantedNode != local)
			line += ' — granted by replica ${lease.leaseGrantedNode}';
	}
	return line;
}

/** Upstream formatTimeUntil (cmd/bd/wisp.go:579-606) for an instant `seconds` from now. */
function formatTimeUntil(seconds:Float):String {
	if (seconds <= 0)
		return "expired";
	if (seconds < 60)
		return "in <1 min";
	if (seconds < 3600) {
		final minutes = Std.int(seconds / 60);
		return minutes == 1 ? "in 1 min" : 'in ${minutes} mins';
	}
	if (seconds < 86400) {
		final hours = Std.int(seconds / 3600);
		return hours == 1 ? "in 1 hour" : 'in ${hours} hours';
	}
	final days = Std.int(seconds / 86400);
	return days == 1 ? "in 1 day" : 'in ${days} days';
}

/**
	Upstream formatTimeAgo (cmd/bd/wisp.go:547-574) for an instant `seconds`
	ago. Less than a minute ago, also a time in the future, is "just now"; a
	week or more ago prints `date`.
**/
function formatTimeAgo(seconds:Float, date:String):String {
	if (seconds < 60)
		return "just now";
	if (seconds < 3600) {
		final minutes = Std.int(seconds / 60);
		return minutes == 1 ? "1 min ago" : '${minutes} mins ago';
	}
	if (seconds < 86400) {
		final hours = Std.int(seconds / 3600);
		return hours == 1 ? "1 hour ago" : '${hours} hours ago';
	}
	if (seconds < 7 * 86400) {
		final days = Std.int(seconds / 86400);
		return days == 1 ? "1 day ago" : '${days} days ago';
	}
	return date;
}
