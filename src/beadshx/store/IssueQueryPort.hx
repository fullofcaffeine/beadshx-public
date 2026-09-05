package beadshx.store;

import beadshx.query.QueryTimePort;

/** Command-scoped issue queries with an explicit native-resource lifetime. */
interface IssueQueryPort extends QueryTimePort {
	function issueQuery(beadsDir:String, request:QueryStorageRequest, global:Bool):QueryRowResult;
	function issueCount(beadsDir:String, request:CountRequest, group:CountGroup, global:Bool):StoreResult<CountResult>;
	function issueReady(beadsDir:String, request:ReadyRequest, global:Bool):ReadyLoadResult;
	function issueSearch(beadsDir:String, query:String, request:IssueListRequest, global:Bool):IssueListResult;
	function issueStale(beadsDir:String, request:StaleRequest, global:Bool):StoreResult<Array<StaleIssue>>;
	function issueOrphanCandidates(beadsDir:String, request:IssueListRequest, global:Bool):StoreResult<OrphanCandidateScan>;
	function issueList(beadsDir:String, request:IssueListRequest, effectiveLimit:Int, global:Bool):IssueListResult;
	function dependencyEdges(beadsDir:String, databaseName:String, ids:Array<String>, dependencyTypes:Array<String>, global:Bool):DependencyEdgeResult;
	function issueSummary(beadsDir:String, databaseName:String, id:String, global:Bool):StoreResult<IssueLookup>;
	function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest, global:Bool):StoreResult<IssueDetailsLookup>;
	function issueDependents(beadsDir:String, id:String, global:Bool):StoreResult<Array<IssueDependency>>;
	function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:IssueStatus, global:Bool):StoreResult<String>;
	function searchIssueIds(beadsDir:String, databaseName:String, query:String, global:Bool):StoreResult<Array<String>>;
	function close():StoreResult<Bool>;
}
