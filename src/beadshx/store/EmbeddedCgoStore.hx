package beadshx.store;

import beadshx.relation.DependencyRead;
import beadshx.relation.DependencyRead.DependencyFinishResult;
import beadshx.relation.DependencyRead.DependencyReadPlan;

/** Installs the Haxe-authored embedded Dolt implementation in CGO builds. */
@:goBuildConstraint("cgo")
@:keep
@:goNative
final class EmbeddedCgoStore implements EmbeddedStorePort {
	static final installed:Bool = EmbeddedStoreAccess.install(new EmbeddedCgoStore());

	public function new() {}

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

	public function issueDetails(beadsDir:String, id:String):Null<StoreResult<IssueDetailsLookup>> {
		return switch new EmbeddedScalarIssueDetailsReader(beadsDir).read(id) {
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
