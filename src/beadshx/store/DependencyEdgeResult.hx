package beadshx.store;

import beadshx.relation.DependencyAnchor;

/** Typed result of one batch raw-edge read. */
enum DependencyEdgeResult {
	DependencyEdges(anchors:Array<DependencyAnchor>);
	DependencyEdgeFailure(message:String);
}
