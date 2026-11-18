package beadshx.relation;

import beadshx.relation.DependencyRead.compareUtf8;

/** One member of a dependency cycle: its ID and, when the database has one, its record. */
typedef CycleMember<T> = {
	final id:String;
	final issue:Null<T>;
}

/** One dependency cycle in canonical order. It is partial when a member has no record. */
typedef DependencyCycle<T> = {
	final members:Array<CycleMember<T>>;
	final partial:Bool;
}

/**
	Lists every dependency cycle of a blocking graph in upstream's canonical order.

	This is a direct port of upstream issueops.CanonicalCyclePaths, so `bd dep cycles`
	prints the same cycles in the same order. Roots and neighbors are visited in byte
	order, duplicate edges count once, and each cycle found by the depth-first walk
	starts at its lowest ID. The cycles are then sorted element by element.
	`graph` maps an issue ID to the IDs it depends on.
**/
function canonicalCyclePaths(graph:Map<String, Array<String>>):Array<Array<String>> {
	final adjacency = new Map<String, Array<String>>();
	final roots = new Array<String>();
	for (node => neighbors in graph) {
		roots.push(node);
		final sorted = neighbors.copy();
		sorted.sort(compareUtf8);
		final unique = new Array<String>();
		for (neighbor in sorted)
			if (unique.length == 0 || unique[unique.length - 1] != neighbor)
				unique.push(neighbor);
		adjacency.set(node, unique);
	}
	roots.sort(compareUtf8);

	final cycles = new Array<Array<String>>();
	final visited = new Map<String, Bool>();
	final onPath = new Map<String, Bool>();
	final path = new Array<String>();
	function walk(node:String):Void {
		visited.set(node, true);
		onPath.set(node, true);
		path.push(node);
		final neighbors = adjacency.get(node);
		if (neighbors != null)
			for (neighbor in neighbors) {
				if (!visited.exists(neighbor)) {
					walk(neighbor);
				} else if (onPath.get(neighbor) == true) {
					final start = path.indexOf(neighbor);
					if (start >= 0)
						cycles.push(rotateToLowest(path.slice(start)));
				}
			}
		path.pop();
		onPath.set(node, false);
	}
	for (root in roots)
		if (!visited.exists(root))
			walk(root);
	cycles.sort(compareIdLists);
	return cycles;
}

/**
	Turns canonical cycle paths into cycles with member records, like upstream BuildCycles.

	`hydrate` returns a member's record, or null when the database has none; each ID
	is looked up once. A cycle with any member without a record is marked partial.
**/
function buildCycles<T>(paths:Array<Array<String>>, hydrate:String->Null<T>):Array<DependencyCycle<T>> {
	final looked = new Map<String, Bool>();
	final records = new Map<String, T>();
	final cycles = new Array<DependencyCycle<T>>();
	for (path in paths) {
		final members = new Array<CycleMember<T>>();
		var partial = false;
		for (id in path) {
			if (!looked.exists(id)) {
				looked.set(id, true);
				final record = hydrate(id);
				if (record != null)
					records.set(id, record);
			}
			final record = records.get(id);
			if (record == null)
				partial = true;
			members.push({id: id, issue: record});
		}
		cycles.push({members: members, partial: partial});
	}
	return cycles;
}

private function rotateToLowest(path:Array<String>):Array<String> {
	var lowest = 0;
	for (index in 0...path.length)
		if (compareUtf8(path[index], path[lowest]) < 0)
			lowest = index;
	return path.slice(lowest).concat(path.slice(0, lowest));
}

private function compareIdLists(left:Array<String>, right:Array<String>):Int {
	final shared = left.length < right.length ? left.length : right.length;
	for (index in 0...shared) {
		final order = compareUtf8(left[index], right[index]);
		if (order != 0)
			return order;
	}
	return left.length == right.length ? 0 : (left.length < right.length ? -1 : 1);
}
