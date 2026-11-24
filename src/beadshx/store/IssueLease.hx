package beadshx.store;

/**
	The claim lease of one issue row.

	Upstream reads it from the node-local `leases` table that every full issue
	read joins (internal/storage/sqlbuild/sqlbuild.go:67-90); an issue without a
	live claim has no lease row. Each value is "" when it is NULL, and the two
	times are RFC 3339 with nanoseconds, as Go's JSON encoding prints them.
**/
typedef IssueLease = {
	final leaseExpiresAt:String;
	final heartbeatAt:String;
	final leaseGrantedNode:String;
}
