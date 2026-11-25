package beadshx.ready;

import beadshx.relation.DependencyCycle.walkBlockingCycles;
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
	set, and upstream's blocked list and cycles. Haxe owns the explanation,
	blocker hydration, parent selection, and the stand-in lists where no
	Haxe-owned SQL reads them; no native facade owns this public command
	behavior.
**/
final class ReadyExplain {
	/**
		Ports upstream types.BuildReadyExplanation (internal/types/types.go:1718-1810).
		`blocked` is upstream's GetBlockedIssues list and `cycles` its DetectCycles
		list, both kept in their order. The candidates, every issue and wisp, give
		each blocker its title, status and priority; a blocker without a record
		keeps only its ID, as upstream's.
	**/
	public static function build(readyIssues:Array<IssueListItem>, candidates:Array<IssueListItem>, blocked:Array<BlockedEntry>,
			cycles:Array<Array<String>>):ReadyExplanation {
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

		return {ready: ready, blocked: blockedItems, cycles: cycles};
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

	/**
		The cycles where no Haxe-owned SQL reads the blocking graph yet (server-mode and
		proxied workspaces), walked as upstream DetectCyclesInTx walks them (see
		walkBlockingCycles). The graph holds the candidates' own `blocks` and
		`conditional-blocks` edges in the candidates' order, and like upstream each
		cycle leaves out a member without a record. An edge from an ID without a
		record is not among the candidates' edges, so a cycle through such an ID is
		missing here.
	**/
	public static function cyclesFromEdges(candidates:Array<IssueListItem>):Array<Array<String>> {
		final known = new Map<String, Bool>();
		final graph = new Map<String, Array<String>>();
		for (issue in candidates) {
			known.set(issue.id, true);
			for (dependency in issue.dependencies)
				if (dependency.dependencyType == "blocks" || dependency.dependencyType == "conditional-blocks") {
					var targets = graph.get(dependency.issueId);
					if (targets == null) {
						targets = [];
						graph.set(dependency.issueId, targets);
					}
					targets.push(dependency.dependsOnId);
				}
		}
		final cycles = new Array<Array<String>>();
		for (path in walkBlockingCycles(graph)) {
			final members = [for (id in path) if (known.exists(id)) id];
			if (members.length > 0)
				cycles.push(members);
		}
		return cycles;
	}
}
