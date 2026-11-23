package beadshx.store;

/** Behavior-oriented read-only store boundary for the first command family. */
interface ReadonlyStorePort extends IssueQueryPort {
	/** `serverStore`: upstream opens a SQL server for the workspace, even when it holds an embeddeddolt directory. */
	function openIssueQuery(beadsDir:String, serverStore:Bool, databaseName:String, proxiedServer:Bool, global:Bool):StoreResult<IssueQueryPort>;

	function validate(beadsDir:String, global:Bool):StoreResult<Bool>;
	function info(beadsDir:String, includeSchema:Bool, global:Bool):StoreResult<InfoSnapshot>;
	function ping(beadsDir:String, global:Bool):StoreResult<PingSnapshot>;
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
}
