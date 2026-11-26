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

	/** Every issue that depends on `id`, with its whole record, as `show --refs` and `--children` read them. */
	function issueDependents(beadsDir:String, id:String):Null<StoreResult<Array<RelatedIssue>>>;

	function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>>;
	function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>>;

	/** Upstream `SearchIssues` with an issue type and a status: the IDs it finds. */
	function typedIssueIds(beadsDir:String, databaseName:String, issueType:String, status:String):Null<StoreResult<Array<String>>>;

	/** Search's check of a `--status` selector: success when it applies, or upstream's refusal. */
	function searchStatusCheck(beadsDir:String, databaseName:String, status:String, layers:SqlIssueFilter.IssueListConfigLayers):Null<StoreResult<Bool>>;

	function issueComments(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueComment>>>;
	function issueHistory(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueHistory.IssueHistoryEntry>>>;
	function issueEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):Null<StoreResult<Array<IssueHistory.IssueEvent>>>;
	function eventsJournal(beadsDir:String, databaseName:String, since:haxe.Int64, limit:haxe.Int64):Null<StoreResult<EventsJournal.EventsJournalRead>>;
	function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>>;
	function staleIssues(beadsDir:String, databaseName:String, request:StaleRequest):Null<StoreResult<Array<StaleIssue>>>;
	function issueList(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int,
		layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult>;
	function issueReady(beadsDir:String, databaseName:String, request:ReadyRequest, query:ReadyQuery):Null<ReadyLoadResult>;

	/** Opens and closes the store `count` times (EmbeddedSession.openForStoreCall); without embedded access it does nothing. */
	function openForStoreCalls(beadsDir:String, databaseName:String, count:Int):Void;

	/** The total, and the buckets of a grouping, that `bd count` prints. */
	function issueCount(beadsDir:String, databaseName:String, request:CountRequest, group:CountGroup,
		layers:SqlIssueFilter.IssueListConfigLayers):Null<StoreResult<CountResult>>;

	/** The issues that `bd search` and `label list-all` read, in display order. */
	function issueSearch(beadsDir:String, databaseName:String, query:String, request:IssueListRequest,
		layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult>;

	/** Every issue and wisp, the candidates that `bd query` filters and pages. */
	function queryCandidates(beadsDir:String, databaseName:String):Null<StoreResult<Array<IssueListItem>>>;

	/** The timings of `bd ping`, after it opened the store and counted the issues. */
	function ping(beadsDir:String, databaseName:String):Null<StoreResult<PingOutcome>>;

	function dependencyCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.relation.DependencyCycle<RelatedIssue>>>>;
	function dependencyTree(beadsDir:String, databaseName:String,
		request:beadshx.relation.DependencyTree.DependencyTreeRequest):Null<StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<RelatedIssue>>>>;
	function graphCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<Array<String>>>>;
	function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphLoad>>;
	function graphIssues(beadsDir:String, databaseName:String, ids:Array<String>):Null<StoreResult<Array<RelatedIssue>>>;
	function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>>;
	function customTypes(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomTypes>>;
	function customStatuses(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomStatuses>>;
	function configValue(beadsDir:String, databaseName:String, key:String):Null<StoreResult<String>>;
	function configSettings(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.config.ConfigKeys.ConfigSetting>>>;
	function issueTotal(beadsDir:String, databaseName:String):Null<StoreResult<Int>>;

	/** The whole `TaskSnapshot` artifact, read in one read transaction. */
	function taskSnapshot(beadsDir:String, databaseName:String):Null<StoreResult<String>>;

	/** Opens and closes one session for its schema check (`ReadonlyStorePort.checkSchema`); without embedded access it does nothing. */
	function checkSchema(beadsDir:String, databaseName:String):Void;

	/** Opens one session without the schema check and runs upstream's remote-migrate gate (`ReadonlyStorePort.remoteMigrateGate`). */
	function remoteMigrateGate(beadsDir:String, databaseName:String, currentVersion:Int):Null<RemoteMigrateGate.RemoteGateOutcome>;
}
