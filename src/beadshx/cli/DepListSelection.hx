package beadshx.cli;

import beadshx.relation.RelationRead.RelationDirection;

/** Pinned CLI result shape: batch edges and neighboring issues are different APIs. */
enum DepListSelection {
	BatchEdges;
	RelatedIssues(direction:RelationDirection);
}

/**
	Narrow the permissive upstream direction flag without silently validating it.

	Only explicit/default down selects batch edges. Unknown nonempty strings
	select outgoing neighbors, even for batches; up selects incoming neighbors.
	Use the number of requested IDs, before missing anchors are skipped.
**/
function selectDepList(direction:String, requestedCount:Int):DepListSelection {
	if (requestedCount > 1 && (direction == "" || direction == "down"))
		return BatchEdges;
	return RelatedIssues(direction == "up" ? Incoming : Outgoing);
}
