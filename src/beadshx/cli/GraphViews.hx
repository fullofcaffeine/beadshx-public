package beadshx.cli;

import beadshx.relation.GraphLayout;
import beadshx.relation.RelatedIssue;
import beadshx.store.SqlGraphReader.GraphSubgraph;

/** The fill and font colors of one DOT node. */
private typedef DotColors = {
	final fill:String;
	final font:String;
}

/**
	Upstream renderGraphDOT for one loaded subgraph.

	Each layer is an invisible cluster that keeps its nodes on one rank. Each
	`blocks` and `parent-child` row follows in load order, drawn from the blocker
	to the blocked issue; other rows are left out. Like upstream, a label escapes
	only its quotes, so a backslash or a newline in a title stays as it is.
**/
function renderGraphDot(subgraph:GraphSubgraph, layout:GraphLayout):String {
	final issues = issuesById(subgraph);
	final rendered = new StringBuf();
	rendered.add("digraph beads {\n  rankdir=LR;\n");
	rendered.add('  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11];\n');
	rendered.add('  edge [color="#666666"];\n\n');
	for (index in 0...layout.layers.length) {
		rendered.add('  subgraph cluster_layer_${index} {\n    style=invis;\n    rank=same;\n');
		for (id in layout.layers[index]) {
			final issue = issues.get(id);
			final label = '${plainStatusIcon(issue.status)} ${issue.id}\\nP${issue.priority} | ${truncateTitle(issue.title, 40)}';
			final escapedLabel = StringTools.replace(label, '"', '\\"');
			final colors = dotColors(issue.status);
			rendered.add('    "${dotId(id)}" [label="${escapedLabel}", fillcolor="${colors.fill}", fontcolor="${colors.font}"];\n');
		}
		rendered.add("  }\n");
	}
	rendered.add("\n");
	for (edge in subgraph.edges) {
		final style = switch edge.type {
			case "blocks": " [style=solid, arrowhead=normal]";
			case "parent-child": ' [style=dashed, arrowhead=empty, color="#999999"]';
			case _: "";
		};
		if (style != "" && layout.nodes.exists(edge.issueId) && layout.nodes.exists(edge.dependsOnId))
			rendered.add('  "${dotId(edge.dependsOnId)}" -> "${dotId(edge.issueId)}"${style};\n');
	}
	rendered.add("}\n");
	return rendered.toString();
}

/** Upstream truncateTitle: at most `maxLength` characters, the last one an ellipsis when cut. */
function truncateTitle(title:String, maxLength:Int):String {
	return title.length <= maxLength ? title : title.substr(0, maxLength - 1) + "…";
}

private function issuesById(subgraph:GraphSubgraph):Map<String, RelatedIssue> {
	final issues = new Map<String, RelatedIssue>();
	for (issue in subgraph.issues)
		issues.set(issue.id, issue);
	return issues;
}

/** Upstream statusPlainIcon: a status other than the four built-in ones shows as deferred. */
private function plainStatusIcon(status:String):String {
	return switch status {
		case "open": "○";
		case "in_progress": "◐";
		case "blocked": "●";
		case "closed": "✓";
		case _: "❄";
	};
}

/** The colors of upstream dotNodeAttrs; deferred, pinned, hooked and custom statuses share one pair. */
private function dotColors(status:String):DotColors {
	return switch status {
		case "open": {fill: "#e8f4fd", font: "#1a1a1a"};
		case "in_progress": {fill: "#fff3cd", font: "#664d03"};
		case "blocked": {fill: "#f8d7da", font: "#842029"};
		case "closed": {fill: "#d4edda", font: "#888888"};
		case _: {fill: "#e2e3e5", font: "#41464b"};
	};
}

/** Upstream dotEscapeID: escapes backslashes and quotes in a quoted node ID. */
private function dotId(id:String):String {
	return StringTools.replace(StringTools.replace(id, "\\", "\\\\"), '"', '\\"');
}
