package beadshx.store;

import beadshx.relation.DependencyRead.DependencyReadPlan;

/**
	Typed optional fast path for embedded Dolt reads.

	A null result means that the current Go file set does not provide embedded
	Dolt access, so the caller must continue through the ordinary storage route.
**/
interface EmbeddedStorePort {
	function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult>;
	function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>>;
	function issueDetails(beadsDir:String, id:String):Null<StoreResult<IssueDetailsLookup>>;
	function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>>;
	function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>>;
}
