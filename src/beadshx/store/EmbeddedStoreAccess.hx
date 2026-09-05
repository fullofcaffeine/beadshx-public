package beadshx.store;

import beadshx.relation.DependencyRead.DependencyReadPlan;

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

	public static function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>> {
		return implementation.issueSummary(beadsDir, databaseName, id);
	}

	public static function issueDetails(beadsDir:String, id:String):Null<StoreResult<IssueDetailsLookup>> {
		return implementation.issueDetails(beadsDir, id);
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

	public function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult> {
		return null;
	}

	public function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>> {
		return null;
	}

	public function issueDetails(beadsDir:String, id:String):Null<StoreResult<IssueDetailsLookup>> {
		return null;
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>> {
		return null;
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>> {
		return null;
	}
}
