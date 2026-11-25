package beadshx.ready;

import beadshx.relation.RelatedIssue;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.store.IssueListItem;

/** One issue on upstream's blocked list and the IDs of its blockers, in upstream's order. */
typedef BlockedEntry = {
	final issue:RelatedIssue;
	final blockedBy:Array<String>;
}

/**
	Builds `ready --explain` policy from copied storage facts.

	The storage boundary supplies issue rows, dependency edges, the exact ready
	set and upstream's blocked list. Haxe owns the explanation, blocker
	hydration, parent selection, and cycle walk; no native facade owns this
	public command behavior.
**/
final class ReadyExplain {
	/**
		Ports upstream types.BuildReadyExplanation (internal/types/types.go:1718-1810).
		`blocked` is upstream's GetBlockedIssues list, kept in its order. The
		candidates, every issue and wisp, give each blocker its title, status and
		priority; a blocker without a record keeps only its ID, as upstream's.
	**/
	public static function build(readyIssues:Array<IssueListItem>, candidates:Array<IssueListItem>, blocked:Array<BlockedEntry>):ReadyExplanation {
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

		final blockedItems = new Array<BlockedExplainItem>();
		for (entry in blocked) {
			final blockers = new Array<ReadyBlockerInfo>();
			for (id in entry.blockedBy) {
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
			blockedItems.push({issue: entry.issue, blockedBy: blockers, blockedByCount: entry.blockedBy.length});
		}

		return {ready: ready, blocked: blockedItems, cycles: detectCycles(candidates)};
	}

	/**
		The blocked list where no Haxe-owned SQL reads the stored `is_blocked` flag yet
		(server-mode and proxied workspaces): each candidate with an open blocker, in
		the candidates' order, named by its blocking annotations. It differs from
		upstream's list when a stored flag disagrees with the blocking edges.
	**/
	public static function blockedFromEdges(candidates:Array<IssueListItem>):Array<BlockedEntry> {
		return [
			for (issue in candidates)
				if (issue.blockedBy.length > 0) {issue: relatedIssue(issue, issue.labels, issue.longFields, ""), blockedBy: issue.blockedBy}
		];
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
