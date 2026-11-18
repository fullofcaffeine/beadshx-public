package beadshx.cli;

import haxe.io.Bytes;
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

/** Upstream padRight: cuts to `width` characters or pads with spaces to it. */
private function padRight(value:String, width:Int):String {
	return value.length >= width ? value.substr(0, width) : value + repeat(" ", width - value.length);
}

/** What an empty lipgloss v2 style does to text when colors are off. */
private function expandTabs(value:String):String {
	return StringTools.replace(value, "\t", "    ");
}

/** `value` repeated `count` times; nothing when `count` is not positive. */
private function repeat(value:String, count:Int):String {
	final repeated = new StringBuf();
	for (_ in 0...count)
		repeated.add(value);
	return repeated.toString();
}

private function countOf(counts:Map<String, Int>, id:String):Int {
	final count = counts.get(id);
	return count == null ? 0 : count;
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
