package beadshx.store;

import beadshx.relation.DependencyRead;
import beadshx.relation.DependencyRead.DependencyFinishResult;
import beadshx.relation.DependencyRead.DependencyReadPlan;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelatedIssue;

/** Installs the Haxe-authored embedded Dolt implementation in CGO builds. */
@:goBuildConstraint("cgo")
@:keep
@:goNative
final class EmbeddedCgoStore implements EmbeddedStorePort {
	static final installed:Bool = EmbeddedStoreAccess.install(new EmbeddedCgoStore());

	public function new() {}

	public function relatedIssues(beadsDir:String, databaseName:String, plan:RelationReadPlan):Null<StoreResult<Array<RelatedIssue>>> {
		return EmbeddedRelationReader.read(beadsDir, databaseName, plan);
	}

	public function issueComments(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueComment>>> {
		return EmbeddedCommentReader.read(beadsDir, databaseName, issueId);
	}

	public function issueHistory(beadsDir:String, databaseName:String, issueId:String):Null<StoreResult<Array<IssueHistory.IssueHistoryEntry>>> {
		return EmbeddedHistoryReader.readHistory(beadsDir, databaseName, issueId);
	}

	public function eventsJournal(beadsDir:String, databaseName:String, since:haxe.Int64, limit:haxe.Int64):Null<StoreResult<EventsJournal.EventsJournalRead>> {
		return EmbeddedEventsJournalReader.read(beadsDir, databaseName, since, limit);
	}

	public function issueEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int):Null<StoreResult<Array<IssueHistory.IssueEvent>>> {
		return EmbeddedHistoryReader.readEvents(beadsDir, databaseName, issueId, limit);
	}

	public function blockedIssues(beadsDir:String, databaseName:String, parentId:String):Null<StoreResult<Array<SqlBlockedReader.BlockedIssue>>> {
		return EmbeddedBlockedReader.read(beadsDir, databaseName, parentId);
	}

	public function dependencyCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<beadshx.relation.DependencyCycle<RelatedIssue>>>> {
		return EmbeddedCycleReader.read(beadsDir, databaseName);
	}

	public function dependencyTree(beadsDir:String, databaseName:String,
			request:beadshx.relation.DependencyTree.DependencyTreeRequest):Null<StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<RelatedIssue>>>> {
		return EmbeddedTreeReader.read(beadsDir, databaseName, request);
	}

	public function graphCycles(beadsDir:String, databaseName:String):Null<StoreResult<Array<Array<String>>>> {
		return EmbeddedGraphReader.readCycles(beadsDir, databaseName);
	}

	public function graphSubgraph(beadsDir:String, databaseName:String, rootId:String):Null<StoreResult<SqlGraphReader.GraphSubgraph>> {
		return EmbeddedGraphReader.readSubgraph(beadsDir, databaseName, rootId);
	}

	public function graphAll(beadsDir:String, databaseName:String, maxRows:Int):Null<StoreResult<SqlGraphReader.AllGraphLoad>> {
		return EmbeddedGraphReader.readAll(beadsDir, databaseName, maxRows);
	}

	public function customTypes(beadsDir:String, databaseName:String):Null<StoreResult<Array<String>>> {
		return EmbeddedCustomConfigReader.readTypes(beadsDir, databaseName);
	}

	public function customStatuses(beadsDir:String, databaseName:String):Null<StoreResult<Array<CustomConfig.CustomStatus>>> {
		return EmbeddedCustomConfigReader.readStatuses(beadsDir, databaseName);
	}

	public function dependencyEdges(beadsDir:String, databaseName:String, plan:DependencyReadPlan):Null<DependencyEdgeResult> {
		return switch new EmbeddedDependencyReader(beadsDir, databaseName).read(plan.anchors) {
			case EmbeddedDependencyFailure(message): DependencyEdgeFailure(message);
			case EmbeddedDependencySnapshot(snapshot):
				switch DependencyRead.finish(plan, snapshot) {
					case DependencyFinishInvalid(message): DependencyEdgeFailure(message);
					case DependencyFinishReady(anchors): DependencyEdges(anchors);
				}
		};
	}

	public function issueSummary(beadsDir:String, databaseName:String, id:String):Null<StoreResult<IssueLookup>> {
		return switch new EmbeddedIssueSummaryReader(beadsDir, databaseName).read(id) {
			case EmbeddedIssueSummaryFailure(message): Failure(message);
			case EmbeddedIssueSummaryMissing: Success(IssueMissing);
			case EmbeddedIssueSummaryFound(summary): Success(IssueFound(summary));
		};
	}

	public function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest):Null<StoreResult<IssueDetailsLookup>> {
		return switch new EmbeddedScalarIssueDetailsReader(beadsDir).read(id, request) {
			case EmbeddedScalarDetailsFailure(message): Failure(message);
			case EmbeddedScalarDetailsMissing: Success(DetailsMissing);
			case EmbeddedScalarDetailsFound(details): Success(DetailsFound(details));
			case EmbeddedScalarDetailsRequireRelations: null;
		};
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:String):Null<StoreResult<String>> {
		return switch new EmbeddedAssignedIssueReader(beadsDir, databaseName).read(actor, status) {
			case EmbeddedAssignedIssueFailure(message): Failure(message);
			case EmbeddedAssignedIssueMissing: Success("");
			case EmbeddedAssignedIssueFound(id): Success(id);
		};
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String):Null<StoreResult<Array<String>>> {
		return switch new EmbeddedIssueIdSearch(beadsDir, databaseName).read(query) {
			case EmbeddedIssueIdSearchFailure(message): Failure(message);
			case EmbeddedIssueIds(ids): Success(ids);
		};
	}
}
