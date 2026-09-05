package beadshx.ready;

import beadshx.store.IssueListItem;

/**
	Builds `ready --explain` policy from copied storage facts.

	The storage boundary supplies issue rows, dependency edges, and the exact
	ready set. Haxe owns the explanation, blocker hydration, parent selection,
	and cycle walk; no native facade owns this public command behavior.
**/
final class ReadyExplain {
	public static function build(readyIssues:Array<IssueListItem>, candidates:Array<IssueListItem>):ReadyExplanation {
		final byId = new Map<String, IssueListItem>();
		for (issue in candidates)
			byId.set(issue.id, issue);

		final ready = new Array<ReadyExplainItem>();
		for (issue in readyIssues) {
			var parent:Null<String> = null;
			final resolved = new Array<String>();
			for (dependency in issue.dependencies) {
				switch dependency.dependencyType {
					case "blocks" | "conditional-blocks" | "waits-for":
						resolved.push(dependency.dependsOnId);
					case "parent-child" if (parent == null):
						parent = dependency.dependsOnId;
					case _:
				}
			}
			final item:ReadyExplainItem = {
				issue: issue,
				reason: resolved.length == 0 ? "no blocking dependencies" : '${resolved.length} blocker(s) resolved',
				resolvedBlockers: resolved.length == 0 ? null : resolved,
				dependencyCount: issue.dependencyCount,
				dependentCount: issue.dependentCount,
				parent: parent
			};
			ready.push(item);
		}

		final blocked = new Array<BlockedExplainItem>();
		for (issue in candidates) {
			if (issue.blockedBy.length == 0)
				continue;
			final blockers = new Array<ReadyBlockerInfo>();
			for (id in issue.blockedBy) {
				final blocker = byId.get(id);
				blockers.push(blocker == null ? {
					id: id,
					title: "",
					status: "",
					priority: 0
				} : {
					id: id,
					title: blocker.title,
					status: blocker.status,
					priority: blocker.priority
					});
			}
			blocked.push({issue: issue, blockedBy: blockers, blockedByCount: issue.blockedBy.length});
		}

		return {ready: ready, blocked: blocked, cycles: detectCycles(candidates)};
	}

	static function detectCycles(issues:Array<IssueListItem>):Array<Array<String>> {
		final graph = new Map<String, Array<String>>();
		for (issue in issues)
			for (dependency in issue.dependencies)
				if (dependency.dependencyType == "blocks" || dependency.dependencyType == "conditional-blocks")
					addEdge(graph, dependency.issueId, dependency.dependsOnId);

		final nodes = [for (node in graph.keys()) node];
		nodes.sort(compareStrings);
		for (node in nodes) {
			final neighbors = graph.get(node);
			if (neighbors != null)
				neighbors.sort(compareStrings);
		}

		final visited = new Map<String, Bool>();
		final active = new Map<String, Bool>();
		final path = new Array<String>();
		final cycles = new Array<Array<String>>();
		function visit(node:String):Void {
			visited.set(node, true);
			active.set(node, true);
			path.push(node);
			final neighbors = graph.get(node);
			if (neighbors != null)
				for (neighbor in neighbors) {
					if (!visited.exists(neighbor)) {
						visit(neighbor);
					} else if (active.exists(neighbor)) {
						final start = path.indexOf(neighbor);
						if (start >= 0)
							cycles.push(path.slice(start));
					}
				}
			path.pop();
			active.remove(node);
		}
		for (node in nodes)
			if (!visited.exists(node))
				visit(node);
		cycles.sort(function(left, right) return compareStrings(left.join("\x00"), right.join("\x00")));
		return cycles;
	}

	static function addEdge(graph:Map<String, Array<String>>, source:String, target:String):Void {
		var targets = graph.get(source);
		if (targets == null) {
			targets = [];
			graph.set(source, targets);
		}
		if (targets.indexOf(target) < 0)
			targets.push(target);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}
}
