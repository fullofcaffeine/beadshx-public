package beadshx.store;

/** Behavior-oriented read-only store boundary for the first command family. */
interface ReadonlyStorePort extends IssueQueryPort {
	/**
		`serverStore`: upstream opens a SQL server for the workspace, even when it holds an
		embeddeddolt directory. The query session of such a workspace never reads that directory.
	**/
	function openIssueQuery(beadsDir:String, serverStore:Bool, databaseName:String, proxiedServer:Bool, global:Bool):StoreResult<IssueQueryPort>;

	function validate(beadsDir:String, global:Bool):StoreResult<Bool>;
	function info(beadsDir:String, includeSchema:Bool, global:Bool):StoreResult<InfoSnapshot>;

	/**
		The timings of `bd ping`. `embeddedStore`: upstream opens the
		workspace's embedded store (no SQL server, not proxied), which an
		embedded workspace then pings with authored Haxe.
	**/
	function ping(beadsDir:String, databaseName:String, embeddedStore:Bool, global:Bool):StoreResult<PingOutcome>;

	function status(beadsDir:String, skipBlocked:Bool, assignee:String, global:Bool):StoreResult<StatusSnapshot>;
	function lastTouchedId(beadsDir:String):String;

	/**
		The `TaskSnapshot` artifact of an embedded workspace, read in one read
		transaction. The caller refuses other workspaces before it asks.
	**/
	function taskSnapshot(beadsDir:String, databaseName:String):StoreResult<String>;

	/**
		Upstream checks the schema when its pre-run opens the store, before the
		command body. Embedded reads here check in the first read of the command;
		this runs that check for a command that has not read yet. A refusal
		throws `SchemaSkewAbort`. A store that does not open is left to the
		command's own read to report.
	**/
	function checkSchema(beadsDir:String, databaseName:String):Void;

	/**
		Upstream's remote-migrate gate for the embedded database of `beadsDir`
		at `currentVersion`, behind the binary, as the command's schema check
		recorded it or, when no check ran it, from a session of its own. A store
		that does not open migrates without the gate.
	**/
	function remoteMigrateGate(beadsDir:String, databaseName:String, currentVersion:Int):RemoteMigrateGate.RemoteGateOutcome;
}
