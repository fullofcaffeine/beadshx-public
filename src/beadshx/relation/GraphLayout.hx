package beadshx.relation;

import beadshx.relation.DependencyRead.compareUtf8;

/** One dependency row of a loaded graph: `issueId` depends on `dependsOnId` through `type`. */
typedef GraphEdge = {
	final issueId:String;
	final dependsOnId:String;
	final type:String;
}

/** Where one issue sits in a graph layout, like upstream GraphNode without its issue. */
typedef GraphNodePlacement = {
	final layer:Int;
	final position:Int;

	/** The IDs the node depends on through `blocks` edges, in edge order; empty for upstream's nil slice. */
	final dependsOn:Array<String>;
}

/** Upstream GraphLayout without the root ID. */
typedef GraphLayout = {
	/** The node IDs of each layer in byte order; an empty layer is upstream's nil slice. */
	final layers:Array<Array<String>>;

	final maxLayer:Int;
	final nodes:Map<String, GraphNodePlacement>;
}

/**
	Places each issue of a graph in a layer, like upstream computeLayout.

	A node with no `blocks` dependency is in layer 0, and any other node is one layer
	after its deepest dependency. A node that depends on a cycle, or on an ID outside
	`issueIds`, stays unplaced and then goes to layer 0. Then each child of a
	`parent-child` edge moves up to its parent's layer until nothing changes (GH#1748);
	this does not move the child's dependents. Upstream does both passes over a Go
	map, but neither result depends on the visit order, so this port visits the
	issues in the given order. Each layer is sorted in byte order, and a node's
	position is its index in its layer.
**/
function computeGraphLayout(issueIds:Array<String>, edges:Array<GraphEdge>):GraphLayout {
	final dependsOn = new Map<String, Array<String>>();
	final parentOf = new Map<String, String>();
	final children = new Array<String>();
	for (edge in edges) {
		if (edge.type == "blocks") {
			var targets = dependsOn.get(edge.issueId);
			if (targets == null) {
				targets = [];
				dependsOn.set(edge.issueId, targets);
			}
			targets.push(edge.dependsOnId);
		} else if (edge.type == "parent-child") {
			// Like a Go map assignment, the last parent edge of a child wins.
			if (!parentOf.exists(edge.issueId))
				children.push(edge.issueId);
			parentOf.set(edge.issueId, edge.dependsOnId);
		}
	}
	final ids = new Array<String>();
	final seen = new Map<String, Bool>();
	for (id in issueIds)
		if (!seen.exists(id)) {
			seen.set(id, true);
			ids.push(id);
		}
	final layerOf = new Map<String, Int>();
	var changed = true;
	while (changed) {
		changed = false;
		for (id in ids) {
			if (layerOf.exists(id))
				continue;
			final targets = dependsOn.get(id);
			var deepest = -1;
			var placed = true;
			if (targets != null)
				for (target in targets) {
					if (!layerOf.exists(target)) {
						placed = false;
						break;
					}
					final targetLayer:Int = layerOf.get(target);
					if (targetLayer > deepest)
						deepest = targetLayer;
				}
			if (placed) {
				layerOf.set(id, deepest + 1);
				changed = true;
			}
		}
	}
	for (id in ids)
		if (!layerOf.exists(id))
			layerOf.set(id, 0);
	changed = true;
	while (changed) {
		changed = false;
		for (child in children) {
			final parent = parentOf.get(child);
			if (parent == null || !layerOf.exists(child) || !layerOf.exists(parent))
				continue;
			final parentLayer:Int = layerOf.get(parent);
			final childLayer:Int = layerOf.get(child);
			if (childLayer < parentLayer) {
				layerOf.set(child, parentLayer);
				changed = true;
			}
		}
	}
	var maxLayer = 0;
	for (id in ids) {
		final layer:Int = layerOf.get(id);
		if (layer > maxLayer)
			maxLayer = layer;
	}
	final layers = [for (_ in 0...maxLayer + 1) new Array<String>()];
	for (id in ids) {
		final layer:Int = layerOf.get(id);
		final members:Array<String> = layers[layer];
		members.push(id);
	}
	final nodes = new Map<String, GraphNodePlacement>();
	for (layer in layers) {
		layer.sort(compareUtf8);
		for (position in 0...layer.length) {
			final targets = dependsOn.get(layer[position]);
			nodes.set(layer[position], {layer: layerOf.get(layer[position]), position: position, dependsOn: targets == null ? [] : targets});
		}
	}
	return {layers: layers, maxLayer: maxLayer, nodes: nodes};
}
