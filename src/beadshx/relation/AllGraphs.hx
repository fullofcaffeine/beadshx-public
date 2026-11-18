package beadshx.relation;

import beadshx.relation.GoSort.goSortSlice;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.store.JsonInteger;

/** What `bd graph --all` reads of one issue to group, order and root the graphs. */
typedef AllGraphIssue = {
	final id:String;
	final priority:JsonInteger;
	final issueType:String;
}

/** One connected group of issues, as upstream assembleAllSubgraphs builds it. */
typedef AllGraphGroup = {
	final rootId:String;

	/** The members in the order the breadth-first walk reached them. */
	final issueIds:Array<String>;

	/** The indexes of the group's rows in the given edges, in that order. */
	final edgeIndexes:Array<Int>;
}

/** A group while it is sorted: the members and the first one. */
private typedef Component = {
	final members:Array<String>;
	final first:AllGraphIssue;
}

/**
	Groups the issues of `bd graph --all` like upstream assembleAllSubgraphs.

	Every row joins its two issues both ways. Each issue that no earlier walk reached
	starts a breadth-first walk, in the given order, that visits the neighbors of each
	issue in row order. Upstream then orders the groups with Go's sort.Slice, larger
	groups first and then by the priority of each group's first member, so this port
	runs the same sort (see goSortSlice) to leave equal groups where upstream does. The
	root of a group is its first epic, or its first member when it has no epic; a later
	member of the same kind with a lower priority number replaces it. Every row must
	join two of the given issues.
**/
function groupAllGraphs(issues:Array<AllGraphIssue>, edges:Array<GraphEdge>):Array<AllGraphGroup> {
	final byId = new Map<String, AllGraphIssue>();
	for (issue in issues)
		byId.set(issue.id, issue);
	final neighbors = new Map<String, Array<String>>();
	function link(from:String, to:String):Void {
		final around = neighbors.get(from);
		if (around == null)
			neighbors.set(from, [to]);
		else
			around.push(to);
	}
	for (edge in edges) {
		link(edge.issueId, edge.dependsOnId);
		link(edge.dependsOnId, edge.issueId);
	}
	final visited = new Map<String, Bool>();
	final components = new Array<Component>();
	for (issue in issues) {
		if (visited.exists(issue.id))
			continue;
		visited.set(issue.id, true);
		final members = [issue.id];
		var next = 0;
		while (next < members.length) {
			final around = neighbors.get(members[next++]);
			if (around != null)
				for (neighbor in around)
					if (!visited.exists(neighbor)) {
						visited.set(neighbor, true);
						members.push(neighbor);
					}
		}
		components.push({members: members, first: issue});
	}
	goSortSlice(components, (left:Component, right:Component) -> {
		if (left.members.length != right.members.length)
			return left.members.length > right.members.length;
		return left.first.priority.compare(right.first.priority) < 0;
	});
	final groupOf = new Map<String, Int>();
	final groups = new Array<AllGraphGroup>();
	for (component in components) {
		var root = component.first;
		for (id in component.members) {
			groupOf.set(id, groups.length);
			final issue = byId.get(id);
			final epic = issue.issueType == "epic";
			final rootEpic = root.issueType == "epic";
			if ((epic && !rootEpic) || (epic == rootEpic && issue.priority.compare(root.priority) < 0))
				root = issue;
		}
		groups.push({rootId: root.id, issueIds: component.members, edgeIndexes: []});
	}
	// A row joins two members of one group, so it belongs to the group of its issue.
	for (index in 0...edges.length) {
		final groupIndex:Int = groupOf.get(edges[index].issueId);
		final group:AllGraphGroup = groups[groupIndex];
		group.edgeIndexes.push(index);
	}
	return groups;
}
