package beadshx.relation;

/** Which edges a dependency tree walk follows from its root. */
enum TreeDirection {
	/** What the root depends on. */
	TreeDown;

	/** What depends on the root. */
	TreeUp;

	/** Both walks, with the dependents first and the root once. */
	TreeBoth;
}

/** A validated `bd dep tree` walk: an exact root ID and a depth of at least one. */
typedef DependencyTreeRequest = {
	final rootId:String;
	final direction:TreeDirection;
	final maxDepth:Int;

	/** Keep only nodes with this status and their ancestors; empty keeps every node. */
	final status:String;
}

/**
	One node of a flattened dependency tree, like upstream types.TreeNode.

	`depth` is 0 for the root. `parentId` names the node the walk came from, and
	`edgeFromParent` is the dependency type of that edge; both are empty for the root.
**/
typedef TreeNode<T> = {
	final id:String;
	final status:String;
	final issue:T;
	final depth:Int;
	final parentId:String;
	final edgeFromParent:String;
}

/** The two halves of a `both` walk, before they are merged. */
typedef BidirectionalTree<T> = {
	final down:Array<TreeNode<T>>;
	final up:Array<TreeNode<T>>;
}

/** Reads the `--direction` vocabulary; any other value is not a direction. */
function parseTreeDirection(value:String):Null<TreeDirection> {
	return switch value {
		case "down": TreeDown;
		case "up": TreeUp;
		case "both": TreeBoth;
		case _: null;
	};
}

/**
	Keeps every node with `status` and the ancestor chain of each one, in walk order.

	This is a port of upstream issueops.PruneTreeByStatus. Keeping the ancestors keeps
	the answer a tree. A prune that matches nothing returns nothing, root included.
**/
function pruneTreeByStatus<T>(nodes:Array<TreeNode<T>>, status:String):Array<TreeNode<T>> {
	if (nodes.length == 0)
		return nodes;
	final keep = new Map<String, Bool>();
	final parentOf = new Map<String, String>();
	for (node in nodes)
		if (node.parentId != "" && node.parentId != node.id)
			parentOf.set(node.id, node.parentId);
	for (node in nodes) {
		if (node.status != status || keep.exists(node.id))
			continue;
		keep.set(node.id, true);
		// Stop on a repeat so that a parent chain that loops back cannot spin here.
		var current = node.id;
		while (true) {
			final parent = parentOf.get(current);
			if (parent == null || parent == current || keep.exists(parent))
				break;
			keep.set(parent, true);
			current = parent;
		}
	}
	return [for (node in nodes) if (keep.exists(node.id)) node];
}

/**
	Joins an up walk and a down walk into the one list a `both` walk answers with.

	This is a port of upstream issueops.MergeBidirectionalTree: every up node except
	the root, then the whole down tree, which starts with the root. Nothing else is
	removed, so a node on both sides appears twice, with a different parent in each.
**/
function mergeBidirectionalTree<T>(downTree:Array<TreeNode<T>>, upTree:Array<TreeNode<T>>, rootId:String):Array<TreeNode<T>> {
	final merged = [for (node in upTree) if (node.id != rootId) node];
	for (node in downTree)
		merged.push(node);
	return merged;
}

/**
	Prunes each half of a `both` walk by status, like upstream pruneBidirectionalByStatus.

	Each half is pruned on its own, because one ID can have a different parent in each
	half. The merge takes the root from the down half only, so when only the up half has
	survivors, the down half gets its root back.
**/
function pruneBidirectionalByStatus<T>(downTree:Array<TreeNode<T>>, upTree:Array<TreeNode<T>>, rootId:String, status:String):BidirectionalTree<T> {
	final down = pruneTreeByStatus(downTree, status);
	final up = pruneTreeByStatus(upTree, status);
	if (up.length == 0)
		return {down: down, up: up};
	for (node in down)
		if (node.id == rootId)
			return {down: down, up: up};
	for (node in downTree)
		if (node.id == rootId)
			return {down: [node].concat(down), up: up};
	return {down: down, up: up};
}
