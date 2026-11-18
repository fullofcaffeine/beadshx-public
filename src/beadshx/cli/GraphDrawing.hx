package beadshx.cli;

import haxe.io.Bytes;
import beadshx.cli.StatusIcon.statusIcon;
import beadshx.relation.GraphLayout;
import beadshx.store.JsonInteger;

// The text pieces that upstream's human `bd graph` views draw with, with colors off.
// They need no loaded subgraph, so the graph contracts can pin them directly.

/** What the default view shows of one issue. */
typedef DagNode = {
	final id:String;
	final title:String;
	final status:String;
	final priority:JsonInteger;
}

/** A `blocks` row routed through one gutter, from a row of its left layer to a row of its right one. */
typedef DagEdge = {
	final sourceRow:Int;
	final targetRow:Int;
}

/**
	Upstream computeDAGNodeWidth: the inner width of every node box.

	A box fits the title cut to 22 characters (counted in runes) after its icon,
	and the ID (counted in UTF-8 bytes, as upstream's len does) with its priority.
	It has one more space on each side and is at least 18 wide.
**/
function computeDagNodeWidth(nodes:Array<DagNode>):Int {
	var widest = 0;
	for (node in nodes) {
		var content = truncateTitle(node.title, 22).length + 3;
		final idWidth = Bytes.ofString(node.id).length + 4;
		if (idWidth > content)
			content = idWidth;
		if (content > widest)
			widest = content;
	}
	return widest + 2 < 18 ? 18 : widest + 2;
}

/**
	Upstream dagNodeLine: line `lineIndex` of one node box, `nodeWidth + 2` characters wide.

	The ID line, and the title of an issue that is not open, go through an empty
	lipgloss style, which turns a tab into four spaces after the padding.
**/
function dagNodeLine(node:DagNode, nodeWidth:Int, lineIndex:Int):String {
	return switch lineIndex {
		case 0: "┌" + repeat("─", nodeWidth) + "┐";
		case 1:
			final title = padRight(truncateTitle(node.title, nodeWidth - 4), nodeWidth - 4);
			'│ ${statusIcon(node.status)} ${node.status == "open" ? title : expandTabs(title)} │';
		case 2: "│ " + expandTabs(padRight('${node.id} P${node.priority}', nodeWidth - 2)) + " │";
		case 3: "└" + repeat("─", nodeWidth) + "┘";
		case _: repeat(" ", nodeWidth + 2);
	};
}

/**
	Upstream collectGutterEdges: the edges of each gutter, gutter `g` being the one
	right of layer `g`.

	Each `blocks` row, in load order, whose blocked issue sits in a later layer than
	its blocker crosses every gutter between them. It leaves the blocker's row in
	the first gutter and runs at the blocked issue's row in the others. A gutter
	keeps the first of several edges with the same two rows.
**/
function collectGutterEdges(layout:GraphLayout, edges:Array<GraphEdge>):Array<Array<DagEdge>> {
	final gutterCount = layout.layers.length - 1;
	final gutters = [for (_ in 0...gutterCount) new Array<DagEdge>()];
	final seen = [for (_ in 0...gutterCount) new Map<String, Bool>()];
	for (edge in edges) {
		if (edge.type != "blocks")
			continue;
		final source = layout.nodes.get(edge.dependsOnId);
		final target = layout.nodes.get(edge.issueId);
		if (source == null || target == null || target.layer <= source.layer)
			continue;
		for (gutter in source.layer...target.layer) {
			final sourceRow = gutter == source.layer ? source.position : target.position;
			final key = '${sourceRow}:${target.position}';
			// Typed locals: haxe.go reads a nested array element as an untyped value.
			final seenRows:Map<String, Bool> = seen[gutter];
			final gutterRows:Array<DagEdge> = gutters[gutter];
			if (!seenRows.exists(key)) {
				seenRows.set(key, true);
				gutterRows.push({sourceRow: sourceRow, targetRow: target.position});
			}
		}
	}
	return gutters;
}

/**
	Upstream buildDAGGutterGrid: the `totalLines` lines of one gutter.

	An edge runs on the title line of its rows. One that keeps its row is a straight
	arrow. One that changes rows gets its own channel column, spread evenly over
	columns 1 to `gutterWidth - 2` (the middle one when it is alone), and turns
	there. Drawing merges each cell with what earlier edges left (see dagMergeRune);
	only the arrowhead in the last column overwrites.
**/
function buildDagGutterGrid(edges:Array<DagEdge>, gutterWidth:Int, totalLines:Int, bandHeight:Int):Array<String> {
	final grid = [for (_ in 0...totalLines) [for (_ in 0...gutterWidth) " "]];
	final vertical = [
		for (index in 0...edges.length)
			if (edges[index].sourceRow != edges[index].targetRow) index
	];
	final channels = [for (_ in edges) 0];
	// Typed locals: haxe.go reads a nested array element as an untyped value.
	for (order in 0...vertical.length) {
		final edgeIndex:Int = vertical[order];
		channels[edgeIndex] = vertical.length == 1 ? Std.int(gutterWidth / 2) : 1 + Std.int(order * (gutterWidth - 3) / (vertical.length - 1));
	}
	function draw(y:Int, x:Int, incoming:String):Void {
		final cells:Array<String> = grid[y];
		cells[x] = dagMergeRune(cells[x], incoming);
	}
	for (index in 0...edges.length) {
		final sourceY = edges[index].sourceRow * bandHeight + 1;
		final targetY = edges[index].targetRow * bandHeight + 1;
		if (sourceY >= totalLines || targetY >= totalLines)
			continue;
		if (sourceY == targetY) {
			for (x in 0...gutterWidth - 1)
				draw(sourceY, x, "─");
		} else {
			final channel = channels[index];
			final down = sourceY < targetY;
			for (x in 0...channel)
				draw(sourceY, x, "─");
			draw(sourceY, channel, down ? "╮" : "╯");
			for (y in (down ? sourceY : targetY) + 1...(down ? targetY : sourceY))
				draw(y, channel, "│");
			draw(targetY, channel, down ? "╰" : "╭");
			for (x in channel + 1...gutterWidth - 1)
				draw(targetY, x, "─");
		}
		final arrowCells:Array<String> = grid[targetY];
		arrowCells[gutterWidth - 1] = "▶";
	}
	return [for (line in grid) line.join("")];
}

/** Upstream dagMergeRune: the cell where `incoming` is drawn over `existing`. */
function dagMergeRune(existing:String, incoming:String):String {
	if (existing == " ")
		return incoming;
	if ((existing == "│" && incoming == "─") || (existing == "─" && incoming == "│"))
		return "┼";
	if (incoming == "▶")
		return "▶";
	if (existing == "─" && incoming == "─")
		return "─";
	if (existing == "│" && incoming == "│")
		return "│";
	if (existing == "│" && (incoming == "╮" || incoming == "╯"))
		return "┤";
	if (existing == "│" && (incoming == "╰" || incoming == "╭"))
		return "├";
	if (existing == "─" && (incoming == "╮" || incoming == "╭"))
		return "┬";
	if (existing == "─" && (incoming == "╰" || incoming == "╯"))
		return "┴";
	return incoming;
}

/** Upstream truncateTitle: at most `maxLength` characters, the last one an ellipsis when cut. */
function truncateTitle(title:String, maxLength:Int):String {
	return title.length <= maxLength ? title : title.substr(0, maxLength - 1) + "…";
}

/** Upstream padRight: cuts to `width` characters or pads with spaces to it. */
function padRight(value:String, width:Int):String {
	return value.length >= width ? value.substr(0, width) : value + repeat(" ", width - value.length);
}

/** What an empty lipgloss v2 style does to text when colors are off. */
function expandTabs(value:String):String {
	return StringTools.replace(value, "\t", "    ");
}

/** `value` repeated `count` times; nothing when `count` is not positive. */
function repeat(value:String, count:Int):String {
	final repeated = new StringBuf();
	for (_ in 0...count)
		repeated.add(value);
	return repeated.toString();
}
