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

	public static function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>> {
		return implementation.blockedIssues(beadsDir, databaseName, parentId);
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

	public static function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphSubgraph>> {
		return implementation.graphSubgraph(beadsDir, databaseName, rootId);
	}

	public static function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>> {
		return implementation.graphAll(beadsDir, databaseName, maxRows);
	}

	public static function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>> {
		return implementation.issueDetails(beadsDir, id, request);
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

	public function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>> {
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

	public function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphSubgraph>> {
		return null;
	}

	public function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>> {
		return null;
	}

	public function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>> {
		return null;
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>> {
		return null;
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>> {
		return null;
	}
}
