package beadshx.store;

import beadshx.relation.RelatedIssue;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelationRead.finishRelationRead;

/**
	Preserve full neighbor records while server query sessions still use the old facade.

	This is removal-tracked M08 scaffolding, not final storage or performance
	evidence: it hydrates each distinct neighbor through the existing session.
	Replace it with SqlRelationReader when the server connection lifetime is
	Haxe-owned. Embedded reads already use that set-based SQL implementation.
**/
function readTransitionalRelations(query:IssueQueryPort, beadsDir:String, plan:RelationReadPlan, global:Bool):StoreResult<Array<RelatedIssue>> {
	final request:IssueDetailsRequest = {includeDependents: false, includeComments: false, briefDependencies: false};
	final neighbors = switch plan.direction {
		case Incoming:
			switch query.issueDependents(beadsDir, plan.anchor, global) {
				case Failure(message): return Failure(message);
				case Success(rows): rows;
			}
		case Outgoing:
			switch query.issueDetails(beadsDir, plan.anchor, request, global) {
				case Failure(message): return Failure(message);
				case Success(DetailsMissing): return Failure('not found: issue ${plan.anchor}');
				case Success(DetailsFound(details)): details.dependencies;
			}
	};
	final hydrated = new Map<String, IssueDetailsLookup>();
	final result = new Array<RelatedIssue>();
	for (neighbor in neighbors) {
		if (!hydrated.exists(neighbor.id))
			switch query.issueDetails(beadsDir, neighbor.id, request, global) {
				case Failure(message):
					return Failure(message);
				case Success(details):
					hydrated.set(neighbor.id, details);
			}
		switch hydrated.get(neighbor.id) {
			case null:
				return Failure('missing hydrated relation result for ${neighbor.id}');
			case DetailsMissing:
			case DetailsFound(details):
				result.push(relatedIssue(details, details.labels, details.longFields, neighbor.dependencyType));
		}
	}
	return Success(finishRelationRead(plan, result));
}
