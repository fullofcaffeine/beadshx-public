package beadshx.relation;

import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.store.JsonInteger;

/** What the `bd graph --open` filter reads of one issue. */
typedef OpenGraphIssue = {
	final id:String;
	final status:String;
	final priority:JsonInteger;
}

/** The root and the dependency rows that `bd graph --open` keeps; the kept issues are the open ones. */
typedef OpenGraph = {
	final rootId:String;
	final edges:Array<GraphEdge>;
}

/** Upstream isOpenStatus: `--open` keeps these statuses and leaves out every other one. */
function isOpenGraphStatus(status:String):Bool {
	return status == "open" || status == "in_progress" || status == "blocked";
}

/**
	Upstream filterSubgraphOpen without the issue list; null when no issue is open.

	The rows that join two open issues stay in load order, with only the first
	`blocks` row from one issue to another. Then each open issue, in the given
	order, walks the `blocks` rows breadth first through issues that are not
	open and stops at the open ones it reaches. Each open issue reached that way
	gets a new `blocks` row from the walk's start, unless one is already kept.
	Upstream adds these rows in Go map order, so only the order of two or more
	rows into one issue can differ from upstream. The root stays when it is open;
	otherwise the first open issue with the lowest priority number replaces it.
**/
function filterOpenGraph(rootId:String, issues:Array<OpenGraphIssue>, edges:Array<GraphEdge>):Null<OpenGraph> {
	final open = new Map<String, Bool>();
	var fallbackRoot:Null<OpenGraphIssue> = null;
	for (issue in issues)
		if (isOpenGraphStatus(issue.status)) {
			open.set(issue.id, true);
			if (fallbackRoot == null || issue.priority.compare(fallbackRoot.priority) < 0)
				fallbackRoot = issue;
		}
	if (fallbackRoot == null)
		return null;
	final blocked = new Map<String, Array<String>>();
	for (edge in edges)
		if (edge.type == "blocks") {
			final targets = blocked.get(edge.dependsOnId);
			if (targets == null)
				blocked.set(edge.dependsOnId, [edge.issueId]);
			else
				targets.push(edge.issueId);
		}
	final kept = new Array<GraphEdge>();
	final keptBlocks = new Map<String, Bool>();
	function keep(edge:GraphEdge):Void {
		if (edge.type == "blocks") {
			// The length prefix keeps two different ID pairs from making one key.
			final key = '${edge.dependsOnId.length}:${edge.dependsOnId}${edge.issueId}';
			if (keptBlocks.exists(key))
				return;
			keptBlocks.set(key, true);
		}
		kept.push(edge);
	}
	for (edge in edges)
		if (open.exists(edge.issueId) && open.exists(edge.dependsOnId))
			keep(edge);
	for (issue in issues) {
		if (!open.exists(issue.id))
			continue;
		final visited = new Map<String, Bool>();
		visited.set(issue.id, true);
		final queue = [issue.id];
		var next = 0;
		while (next < queue.length) {
			final targets = blocked.get(queue[next++]);
			if (targets != null)
				for (target in targets) {
					if (visited.exists(target))
						continue;
					visited.set(target, true);
					if (open.exists(target))
						keep({issueId: target, dependsOnId: issue.id, type: "blocks"});
					else
						queue.push(target);
				}
		}
	}
	return {rootId: open.exists(rootId) ? rootId : fallbackRoot.id, edges: kept};
}
