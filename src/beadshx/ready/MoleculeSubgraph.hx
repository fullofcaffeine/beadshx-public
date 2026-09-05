package beadshx.ready;

/**
	Reconstructs upstream molecule membership from copied issue facts.

	Explicit parent-child edges take precedence. Hierarchical IDs are a fallback
	only when an issue has not been explicitly reparented. Traversal stays in
	authored Haxe; storage supplies rows but does not own molecule policy.
**/
final class MoleculeSubgraph {
	public static function collectIds(rootId:String, nodes:Array<MoleculeNode>):Array<String> {
		final result = [rootId];
		final visited = new Map<String, Bool>();
		visited.set(rootId, true);
		collectChildren(rootId, nodes, result, visited);
		return result;
	}

	static function collectChildren(parentId:String, nodes:Array<MoleculeNode>, result:Array<String>, visited:Map<String, Bool>):Void {
		for (node in nodes)
			if (!visited.exists(node.id) && node.parents.indexOf(parentId) >= 0)
				addNode(node, nodes, result, visited);

		for (node in nodes) {
			if (visited.exists(node.id) || directHierarchicalParent(node.id) != parentId)
				continue;
			var reparented = false;
			for (explicitParent in node.parents)
				if (explicitParent != parentId) {
					reparented = true;
					break;
				}
			if (!reparented)
				addNode(node, nodes, result, visited);
		}
	}

	static function addNode(node:MoleculeNode, nodes:Array<MoleculeNode>, result:Array<String>, visited:Map<String, Bool>):Void {
		if (visited.exists(node.id))
			return;
		visited.set(node.id, true);
		result.push(node.id);
		collectChildren(node.id, nodes, result, visited);
	}

	static function directHierarchicalParent(id:String):String {
		final separator = id.lastIndexOf(".");
		return separator < 0 ? "" : id.substr(0, separator);
	}
}
