package beadshx.store;

import beadshx.query.QueryTimePort;

/** Command-scoped issue queries with an explicit native-resource lifetime. */
interface IssueQueryPort extends QueryTimePort {
	function relatedIssues(beadsDir:String, databaseName:String, plan:beadshx.relation.RelationRead.RelationReadPlan,
		global:Bool):StoreResult<Array<beadshx.relation.RelatedIssue>>;
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

	/** Blocked issues, as `bd blocked` reports them; an empty `parentId` means no parent filter. */
	function blockedIssues(beadsDir:String, databaseName:String, parentId:String, global:Bool):StoreResult<Array<SqlBlockedReader.BlockedIssue>>;

	/** Every dependency cycle, as `bd dep cycles` reports it. */
	function dependencyCycles(beadsDir:String, databaseName:String,
		global:Bool):StoreResult<Array<beadshx.relation.DependencyCycle<beadshx.relation.RelatedIssue>>>;

	/** The flattened dependency tree of an exact root ID, as `bd dep tree` walks it. */
	function dependencyTree(beadsDir:String, databaseName:String, request:beadshx.relation.DependencyTree.DependencyTreeRequest,
		global:Bool):StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<beadshx.relation.RelatedIssue>>>;

	/** The cycles `bd graph check` reports, as member ID lists; an empty list means a clean graph. */
	function graphCycles(beadsDir:String, databaseName:String, global:Bool):StoreResult<Array<Array<String>>>;

	/** The connected subgraph of an exact root ID, as `bd graph <id>` loads it. */
	function graphSubgraph(beadsDir:String, databaseName:String, rootId:String, global:Bool):StoreResult<SqlGraphReader.GraphSubgraph>;

	/** The open issues and the rows between them, as `bd graph --all` loads them; a positive `maxRows` caps each status. */
	function graphAll(beadsDir:String, databaseName:String, maxRows:Int, global:Bool):StoreResult<SqlGraphReader.AllGraphLoad>;

	function close():StoreResult<Bool>;
}
