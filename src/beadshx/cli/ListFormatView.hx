package beadshx.cli;

import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.IssueListDependency;
import beadshx.store.IssueListItem;

/** One dependency edge of a page issue whose target is also on the page. */
private typedef VisibleEdge = {
	final issueId:String;
	final dependency:IssueListDependency;
}

/** The Graphviz color and line style that upstream gives one dependency type. */
private typedef EdgeStyle = {
	final color:String;
	final line:String;
}

/**
	The `digraph` preset of `list --format`.

	Why: upstream's outputFormattedList (cmd/bd/list_output.go:98-155) renders the
	preset template `{{.IssueID}} {{.DependsOnID}}`. Haxe owns this format and `dot`,
	so `list` prints the `--limit` hint after them, as after the other list views.
	What: one `<issue> <dependency>` line for each visible edge (see visibleEdges).
	How: the native list read supplies the page and each issue's raw edges. A Go
	template does not come here; see IssueListFormat.
**/
function renderListDigraph(items:Array<IssueListItem>):String {
	final rendered = new StringBuf();
	for (edge in visibleEdges(items))
		rendered.add('${edge.issueId} ${edge.dependency.dependsOnId}\n');
	return rendered.toString();
}

/**
	The `dot` format: upstream's outputDotFormat Graphviz document. A node shows the
	ID, type, priority, title and status, and is colored by status. An edge is
	labeled and colored by its dependency type. `quote` is Go's strconv.Quote, which
	upstream's `%q` applies to a string.
**/
function renderListDot(items:Array<IssueListItem>, quote:String->String):String {
	final rendered = new StringBuf();
	rendered.add("digraph dependencies {\n");
	rendered.add("  rankdir=TB;\n");
	rendered.add("  node [shape=box, style=rounded];\n\n");
	for (item in items) {
		final label = '${item.id}\n[${item.issueType} P${item.priority.wireValue()}]\n${item.title}\n(${item.status})';
		final fillColor = switch item.status {
			case "closed": "lightgray";
			case "in_progress": "lightyellow";
			case "blocked": "lightcoral";
			case _: "white";
		};
		final fontColor = item.status == "closed" ? "dimgray" : "black";
		rendered.add('  ${quote(item.id)} [label=${quote(label)}, style="rounded,filled", fillcolor=${quote(fillColor)}, fontcolor=${quote(fontColor)}];\n');
	}
	rendered.add("\n");
	for (edge in visibleEdges(items)) {
		final dependency = edge.dependency;
		final style = edgeStyle(dependency.dependencyType);
		rendered.add('  ${quote(edge.issueId)} -> ${quote(dependency.dependsOnId)} [label=${quote(dependency.dependencyType)}, color=${style.color}, style=${style.line}];\n');
	}
	rendered.add("}\n");
	return rendered.toString();
}

/** Upstream's edge colors: blocks, parent-child, discovered-from and related; black and solid otherwise. */
private function edgeStyle(dependencyType:String):EdgeStyle {
	return switch dependencyType {
		case "blocks": {color: "red", line: "bold"};
		case "parent-child": {color: "blue", line: "solid"};
		case "discovered-from": {color: "green", line: "dashed"};
		case "related": {color: "gray", line: "dashed"};
		case _: {color: "black", line: "solid"};
	};
}

/**
	The edges whose target is also on the page. Each page issue keeps its page
	position, and its edges follow in the order of orderedDependencies.
**/
private function visibleEdges(items:Array<IssueListItem>):Array<VisibleEdge> {
	final visible = new Map<String, Bool>();
	for (item in items)
		visible.set(item.id, true);
	final edges = new Array<VisibleEdge>();
	for (item in items)
		for (dependency in orderedDependencies(item.dependencies))
			if (visible.exists(dependency.dependsOnId))
				edges.push({issueId: item.id, dependency: dependency});
	return edges;
}

/**
	Upstream's SQL order for one issue's edges: target, type, then edge ID. The
	dependencies table compares them as bytes. Equal keys keep the read order.
**/
private function orderedDependencies(dependencies:Array<IssueListDependency>):Array<IssueListDependency> {
	final ordered = [
		for (index in 0...dependencies.length)
			{index: index, dependency: dependencies[index]}
	];
	ordered.sort((left, right) -> {
		var compared = compareUtf8(left.dependency.dependsOnId, right.dependency.dependsOnId);
		if (compared == 0)
			compared = compareUtf8(left.dependency.dependencyType, right.dependency.dependencyType);
		if (compared == 0)
			compared = compareUtf8(left.dependency.id, right.dependency.id);
		return compared != 0 ? compared : (left.index < right.index ? -1 : (left.index == right.index ? 0 : 1));
	});
	return [for (entry in ordered) entry.dependency];
}
