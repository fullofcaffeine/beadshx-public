package beadshx.store;

import beadshx.relation.DependencyRead.DependencyReadPlan;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelatedIssue;

/**
	Typed optional fast path for embedded Dolt reads.

	A null result means that the current Go file set does not provide embedded
	Dolt access, so the caller must continue through the ordinary storage route.
**/
interface EmbeddedStorePort {
	function relatedIssues(beadsDir:String, databaseName:String, plan:RelationReadPlan):Null<StoreResult<Array<RelatedIssue>>>;
	function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult>;
	function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>>;
	function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>>;
	function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>>;
	function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>>;
	function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>>;
	function dependencyCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.relation.DependencyCycle<RelatedIssue>>>>;
	function dependencyTree(beadsDir:String, databaseName:String,
		request:beadshx.relation.DependencyTree.DependencyTreeRequest):Null<StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<RelatedIssue>>>>;
}
