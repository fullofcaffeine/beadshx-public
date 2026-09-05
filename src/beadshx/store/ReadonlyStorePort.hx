package beadshx.store;

/** Behavior-oriented read-only store boundary for the first command family. */
interface ReadonlyStorePort extends IssueQueryPort {
	function openIssueQuery(beadsDir:String, databaseName:String, proxiedServer:Bool, global:Bool):StoreResult<IssueQueryPort>;
	function validate(beadsDir:String, global:Bool):StoreResult<Bool>;
	function info(beadsDir:String, includeSchema:Bool, global:Bool):StoreResult<InfoSnapshot>;
	function ping(beadsDir:String, global:Bool):StoreResult<PingSnapshot>;
	function status(beadsDir:String, skipBlocked:Bool, assignee:String, global:Bool):StoreResult<StatusSnapshot>;
	function lastTouchedId(beadsDir:String):String;
}
