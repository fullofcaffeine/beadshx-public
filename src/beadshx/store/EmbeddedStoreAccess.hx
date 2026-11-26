package beadshx.store;

import beadshx.relation.DependencyRead.DependencyReadPlan;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelatedIssue;

/**
	Owns platform selection for Haxe-authored embedded storage.

	The common generated file contains no Dolt-driver reference. A constrained
	Haxe module installs the implementation when its Go build constraint matches.
**/
final class EmbeddedStoreAccess {
	static var implementation:EmbeddedStorePort = new UnavailableEmbeddedStore();

	public static function install(value:EmbeddedStorePort):Bool {
		implementation = value;
		return true;
	}

	public static function checkSchema(beadsDir:String, databaseName:String):Void {
		implementation.checkSchema(beadsDir, databaseName);
	}

	public static function remoteMigrateGate(beadsDir:String, databaseName:String, currentVersion:Int):Null<RemoteMigrateGate.RemoteGateOutcome> {
		return implementation.remoteMigrateGate(beadsDir, databaseName, currentVersion);
	}

	public static function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult> {
		return implementation.dependencyEdges(beadsDir, databaseName, plan);
	}

	public static function relatedIssues(beadsDir:String, databaseName:String, plan:RelationReadPlan):Null<StoreResult<Array<RelatedIssue>>> {
		return implementation.relatedIssues(beadsDir, databaseName, plan);
	}

	public static function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>> {
		return implementation.issueSummary(beadsDir, databaseName, id);
	}

	public static function issueComments(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueComment>>> {
		return implementation.issueComments(beadsDir, databaseName, issueId);
	}

	public static function issueHistory(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueHistory.IssueHistoryEntry>>> {
		return implementation.issueHistory(beadsDir, databaseName, issueId);
	}

	public static function issueEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):Null<StoreResult<Array<IssueHistory.IssueEvent>>> {
		return implementation.issueEvents(beadsDir, databaseName, issueId, limit);
	}

	public static function eventsJournal(beadsDir:String, databaseName:String, since:haxe.Int64,
			limit:haxe.Int64):Null<StoreResult<EventsJournal.EventsJournalRead>> {
		return implementation.eventsJournal(beadsDir, databaseName, since, limit);
	}

	public static function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>> {
		return implementation.blockedIssues(beadsDir, databaseName, parentId);
	}

	public static function staleIssues(beadsDir:String, databaseName:String, request:StaleRequest):Null<StoreResult<Array<StaleIssue>>> {
		return implementation.staleIssues(beadsDir, databaseName, request);
	}

	public static function issueList(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult> {
		return implementation.issueList(beadsDir, databaseName, request, limit, layers);
	}

	public static function issueReady(beadsDir:String, databaseName:String, request:ReadyRequest, query:ReadyQuery):Null<ReadyLoadResult> {
		return implementation.issueReady(beadsDir, databaseName, request, query);
	}

	public static function openForStoreCalls(beadsDir:String, databaseName:String, count:Int):Void {
		implementation.openForStoreCalls(beadsDir, databaseName, count);
	}

	public static function issueCount(beadsDir:String, databaseName:String, request:CountRequest, group:CountGroup,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<StoreResult<CountResult>> {
		return implementation.issueCount(beadsDir, databaseName, request, group, layers);
	}

	public static function issueSearch(beadsDir:String, databaseName:String, query:String, request:IssueListRequest,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult> {
		return implementation.issueSearch(beadsDir, databaseName, query, request, layers);
	}

	public static function queryCandidates(beadsDir:String, databaseName:String):Null<StoreResult<Array<IssueListItem>>> {
		return implementation.queryCandidates(beadsDir, databaseName);
	}

	public static function ping(beadsDir:String, databaseName:String):Null<StoreResult<PingOutcome>> {
		return implementation.ping(beadsDir, databaseName);
	}

	public static function dependencyCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.relation.DependencyCycle<RelatedIssue>>>> {
		return implementation.dependencyCycles(beadsDir, databaseName);
	}

	public static function dependencyTree(beadsDir:String, databaseName:String,
			request:beadshx.relation.DependencyTree.DependencyTreeRequest):Null<StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<RelatedIssue>>>> {
		return implementation.dependencyTree(beadsDir, databaseName, request);
	}

	public static function graphCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<Array<String>>>> {
		return implementation.graphCycles(beadsDir, databaseName);
	}

	public static function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphLoad>> {
		return implementation.graphSubgraph(beadsDir, databaseName, rootId);
	}

	public static function graphIssues(beadsDir:String, databaseName:String, ids:Array<String>):Null<StoreResult<Array<RelatedIssue>>> {
		return implementation.graphIssues(beadsDir, databaseName, ids);
	}

	public static function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>> {
		return implementation.graphAll(beadsDir, databaseName, maxRows);
	}

	public static function customTypes(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomTypes>> {
		return implementation.customTypes(beadsDir, databaseName);
	}

	public static function customStatuses(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomStatuses>> {
		return implementation.customStatuses(beadsDir, databaseName);
	}

	public static function configValue(beadsDir:String, databaseName:String, key:String):Null<StoreResult<String>> {
		return implementation.configValue(beadsDir, databaseName, key);
	}

	public static function configSettings(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.config.ConfigKeys.ConfigSetting>>> {
		return implementation.configSettings(beadsDir, databaseName);
	}

	public static function issueTotal(beadsDir:String, databaseName:String):Null<StoreResult<Int>> {
		return implementation.issueTotal(beadsDir, databaseName);
	}

	public static function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>> {
		return implementation.issueDetails(beadsDir, id, request);
	}

	public static function issueDependents(beadsDir:String, id:String):Null<StoreResult<Array<RelatedIssue>>> {
		return implementation.issueDependents(beadsDir, id);
	}

	public static function taskSnapshot(beadsDir:String, databaseName:String):Null<StoreResult<String>> {
		return implementation.taskSnapshot(beadsDir, databaseName);
	}

	public static function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>> {
		return implementation.assignedIssueId(beadsDir, databaseName, actor, status);
	}

	public static function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>> {
		return implementation.searchIssueIds(beadsDir, databaseName, query);
	}
}

private final class UnavailableEmbeddedStore implements EmbeddedStorePort {
	public function new() {}

	public function checkSchema(beadsDir:String, databaseName:String):Void {}

	public function remoteMigrateGate(beadsDir:String, databaseName:String, currentVersion:Int):Null<RemoteMigrateGate.RemoteGateOutcome> {
		return null;
	}

	public function relatedIssues(beadsDir:String, databaseName:String, plan:RelationReadPlan):Null<StoreResult<Array<RelatedIssue>>> {
		return null;
	}

	public function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult> {
		return null;
	}

	public function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>> {
		return null;
	}

	public function issueComments(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueComment>>> {
		return null;
	}

	public function issueHistory(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueHistory.IssueHistoryEntry>>> {
		return null;
	}

	public function issueEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):Null<StoreResult<Array<IssueHistory.IssueEvent>>> {
		return null;
	}

	public function eventsJournal(beadsDir:String, databaseName:String, since:haxe.Int64, limit:haxe.Int64):Null<StoreResult<EventsJournal.EventsJournalRead>> {
		return null;
	}

	public function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>> {
		return null;
	}

	public function staleIssues(beadsDir:String, databaseName:String, request:StaleRequest):Null<StoreResult<Array<StaleIssue>>> {
		return null;
	}

	public function issueList(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult> {
		return null;
	}

	public function issueReady(beadsDir:String, databaseName:String, request:ReadyRequest, query:ReadyQuery):Null<ReadyLoadResult> {
		return null;
	}

	public function openForStoreCalls(beadsDir:String, databaseName:String, count:Int):Void {}

	public function issueCount(beadsDir:String, databaseName:String, request:CountRequest, group:CountGroup,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<StoreResult<CountResult>> {
		return null;
	}

	public function issueSearch(beadsDir:String, databaseName:String, query:String, request:IssueListRequest,
			layers:SqlIssueFilter.IssueListConfigLayers):Null<IssueListResult> {
		return null;
	}

	public function queryCandidates(beadsDir:String, databaseName:String):Null<StoreResult<Array<IssueListItem>>> {
		return null;
	}

	public function ping(beadsDir:String, databaseName:String):Null<StoreResult<PingOutcome>> {
		return null;
	}

	public function dependencyCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.relation.DependencyCycle<RelatedIssue>>>> {
		return null;
	}

	public function dependencyTree(beadsDir:String, databaseName:String,
			request:beadshx.relation.DependencyTree.DependencyTreeRequest):Null<StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<RelatedIssue>>>> {
		return null;
	}

	public function graphCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<Array<String>>>> {
		return null;
	}

	public function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphLoad>> {
		return null;
	}

	public function graphIssues(beadsDir:String, databaseName:String, ids:Array<String>):Null<StoreResult<Array<RelatedIssue>>> {
		return null;
	}

	public function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>> {
		return null;
	}

	public function customTypes(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomTypes>> {
		return null;
	}

	public function customStatuses(beadsDir:String, databaseName:String):Null<StoreResult<CustomConfig.DatabaseCustomStatuses>> {
		return null;
	}

	public function configValue(beadsDir:String, databaseName:String, key:String):Null<StoreResult<String>> {
		return null;
	}

	public function configSettings(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.config.ConfigKeys.ConfigSetting>>> {
		return null;
	}

	public function issueTotal(beadsDir:String, databaseName:String):Null<StoreResult<Int>> {
		return null;
	}

	public function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>> {
		return null;
	}

	public function issueDependents(beadsDir:String, id:String):Null<StoreResult<Array<RelatedIssue>>> {
		return null;
	}

	public function taskSnapshot(beadsDir:String, databaseName:String):Null<StoreResult<String>> {
		return null;
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>> {
		return null;
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>> {
		return null;
	}
}
