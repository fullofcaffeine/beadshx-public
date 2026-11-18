package beadshx.cli;

import haxe.io.Bytes;
import beadshx.cli.GraphDrawing.DagNode;
import beadshx.cli.GraphDrawing.buildDagGutterGrid;
import beadshx.cli.GraphDrawing.collectGutterEdges;
import beadshx.cli.GraphDrawing.computeDagNodeWidth;
import beadshx.cli.GraphDrawing.dagNodeLine;
import beadshx.cli.GraphDrawing.expandTabs;
import beadshx.cli.GraphDrawing.padRight;
import beadshx.cli.GraphDrawing.renderCompactGraph;
import beadshx.cli.GraphDrawing.repeat;
import beadshx.cli.GraphDrawing.truncateTitle;
import beadshx.cli.StatusIcon.statusIcon;
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

/**
	Upstream renderGraph, the `--box` view, with colors off.

	Every box is as wide as the longest title cut to 30 characters, measured in
	UTF-8 bytes as upstream's len does, so a multibyte title widens every box; a
	box then shows that many characters of each title and cuts a longer ID. The
	counts leave out `blocks` rows whose blocker is the root. Upstream renders the
	ID and every title but an open one through an empty lipgloss style, which
	turns a tab into four spaces.
**/
function renderGraphBox(subgraph:GraphSubgraph, layout:GraphLayout):String {
	final issues = issuesById(subgraph);
	var nodeCount = 0;
	var maxTitleLength = 0;
	for (layer in layout.layers)
		for (id in layer) {
			nodeCount++;
			final length = Bytes.ofString(truncateTitle(issues.get(id).title, 30)).length;
			if (length > maxTitleLength)
				maxTitleLength = length;
		}
	final width = maxTitleLength + 4;
	final blocks = new Map<String, Int>();
	final needs = new Map<String, Int>();
	var blockingRows = 0;
	for (edge in subgraph.edges)
		if (edge.type == "blocks") {
			blockingRows++;
			if (edge.dependsOnId != subgraph.root.id) {
				blocks.set(edge.dependsOnId, countOf(blocks, edge.dependsOnId) + 1);
				needs.set(edge.issueId, countOf(needs, edge.issueId) + 1);
			}
		}
	final rendered = new StringBuf();
	rendered.add('\n📊 Dependency graph for ${subgraph.root.id}:\n\n');
	rendered.add("  Status: ○ open  ◐ in_progress  ● blocked  ✓ closed\n\n");
	for (index in 0...layout.layers.length) {
		rendered.add(index == 0 ? "  Layer 0 (ready)\n" : '  Layer ${index}\n');
		for (id in layout.layers[index])
			rendered.add(renderNodeBox(issues.get(id), width, countOf(blocks, id), countOf(needs, id)));
		if (index < layout.layers.length - 1)
			rendered.add("      │\n      ▼\n");
		rendered.add("\n");
	}
	if (blockingRows > 0)
		rendered.add('  Dependencies: ${blockingRows} blocking relationships\n');
	rendered.add('  Total: ${nodeCount} issues across ${layout.layers.length} layers\n\n');
	return rendered.toString();
}

/**
	Upstream renderGraphVisual, the default view, with colors off.

	Each layer is a column of node boxes, one five-line band per row, and the
	six-column gutter right of each layer but the last routes the `blocks` rows
	that reach a later layer (see collectGutterEdges and buildDagGutterGrid). Every
	box has the width computeDagNodeWidth gives. Each drawn line loses its trailing
	spaces, but the layer header line keeps them. The summary counts every `blocks`
	row.
**/
function renderGraphVisual(subgraph:GraphSubgraph, layout:GraphLayout):String {
	final nodeHeight = 4;
	final bandHeight = nodeHeight + 1;
	final gutterWidth = 6;
	final issues = issuesById(subgraph);
	final layerCount = layout.layers.length;
	final nodes:Array<DagNode> = [for (layer in layout.layers) for (id in layer) issues.get(id)];
	final nodeWidth = computeDagNodeWidth(nodes);
	var maxRows = 0;
	for (layer in layout.layers)
		if (layer.length > maxRows)
			maxRows = layer.length;
	final totalLines = maxRows * bandHeight - 1;
	final gutters = [
		for (edges in collectGutterEdges(layout, subgraph.edges))
			buildDagGutterGrid(edges, gutterWidth, totalLines, bandHeight)
	];
	final rendered = new StringBuf();
	rendered.add('\n📊 Dependency graph for ${subgraph.root.id}:\n\n');
	rendered.add("  Status: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n\n");
	rendered.add("  ");
	for (index in 0...layerCount) {
		rendered.add(padRight(index == 0 ? "LAYER 0 (ready)" : 'LAYER ${index}', nodeWidth + 2));
		if (index < layerCount - 1)
			rendered.add(repeat(" ", gutterWidth));
	}
	rendered.add("\n\n");
	for (y in 0...totalLines) {
		final row = Std.int(y / bandHeight);
		final subLine = y % bandHeight;
		final line = new StringBuf();
		line.add("  ");
		for (index in 0...layerCount) {
			final layer = layout.layers[index];
			final hasNodeLine = subLine < nodeHeight && row < layer.length;
			line.add(hasNodeLine ? dagNodeLine(issues.get(layer[row]), nodeWidth, subLine) : repeat(" ", nodeWidth + 2));
			if (index < layerCount - 1) {
				final gutter:Array<String> = gutters[index];
				line.add(gutter[y]);
			}
		}
		rendered.add(trimTrailingSpaces(line.toString()) + "\n");
	}
	rendered.add("\n");
	var blockingRows = 0;
	for (edge in subgraph.edges)
		if (edge.type == "blocks")
			blockingRows++;
	if (blockingRows > 0)
		rendered.add('  Dependencies: ${blockingRows} blocking relationships\n');
	rendered.add('  Total: ${nodes.length} issues across ${layerCount} layers\n\n');
	return rendered.toString();
}

/** Upstream renderGraphCompact for one loaded subgraph; see renderCompactGraph. */
function renderGraphCompact(subgraph:GraphSubgraph, layout:GraphLayout):String {
	final nodes = new Map<String, DagNode>();
	for (issue in subgraph.issues)
		nodes.set(issue.id, issue);
	return renderCompactGraph(subgraph.root.id, nodes, layout, subgraph.edges);
}

/** Upstream renderNodeBoxWithDeps; the counts line appears only when a count is not zero. */
private function renderNodeBox(issue:RelatedIssue, width:Int, blocksCount:Int, needsCount:Int):String {
	final paddedTitle = padRight(truncateTitle(issue.title, width - 4), width - 4);
	final title = issue.status == "open" ? paddedTitle : expandTabs(paddedTitle);
	final rule = repeat("─", width);
	final lines = [
		'  ┌${rule}┐',
		'  │ ${statusIcon(issue.status)} ${title} │',
		'  │ ${expandTabs(padRight(issue.id, width - 2))} │'
	];
	final counts = new Array<String>();
	if (blocksCount > 0)
		counts.push('blocks:${blocksCount}');
	if (needsCount > 0)
		counts.push('needs:${needsCount}');
	if (counts.length > 0) {
		final info = counts.join(" ");
		lines.push('  │ ${info}${repeat(" ", width - 2 - info.length)} │');
	}
	lines.push('  └${rule}┘');
	return lines.join("\n") + "\n";
}

/** Go strings.TrimRight(value, " "): only spaces go, not other whitespace. A space is one UTF-8 byte. */
private function trimTrailingSpaces(value:String):String {
	final bytes = Bytes.ofString(value);
	var end = bytes.length;
	while (end > 0 && bytes.get(end - 1) == " ".code)
		end--;
	return bytes.getString(0, end);
}

private function countOf(counts:Map<String, Int>, id:String):Int {
	final count = counts.get(id);
	return count == null ? 0 : count;
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
