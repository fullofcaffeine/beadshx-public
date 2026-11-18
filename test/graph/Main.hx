import beadshx.relation.DependencyCycle.walkBlockingCycles;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.relation.GraphLayout.computeGraphLayout;
import beadshx.cli.GraphDrawing.DagEdge;
import beadshx.cli.GraphDrawing.DagNode;
import beadshx.cli.GraphDrawing.buildDagGutterGrid;
import beadshx.cli.GraphDrawing.collectGutterEdges;
import beadshx.cli.GraphDrawing.computeDagNodeWidth;
import beadshx.cli.GraphDrawing.dagMergeRune;
import beadshx.cli.GraphDrawing.dagNodeLine;
import beadshx.cli.GraphDrawing.compareCompactChildren;
import beadshx.cli.GraphDrawing.formatCompactNode;
import beadshx.cli.GraphDrawing.renderCompactGraph;
import beadshx.cli.GraphHtmlPage.graphHtmlPage;
import beadshx.relation.OpenGraph.OpenGraphIssue;
import beadshx.relation.OpenGraph.filterOpenGraph;

/**
	Pins the `bd graph check` cycle walk against upstream issueops.DetectCyclesInTx,
	the `bd graph <id>` layers against upstream computeLayout, and the pieces of the
	default view against upstream graph_visual.go.

	Upstream walks from the roots in Go map order, so with two or more members its
	output can differ between runs. These values follow the same walk from the roots
	in byte order, one of upstream's possible outcomes; the parity smoke covers only
	the cases that every root order prints the same way.
**/
class Main {
	static function main():Void {
		cycleContracts();
		layoutContracts();
		drawingContracts();
		compactContracts();
		openContracts();
		htmlContracts();
		Sys.println("graph Haxe contracts: PASS");
	}

	static function cycleContracts():Void {
		expectCycles(["b" => ["a"], "a" => ["b"]], "[a b]");
		expectCycles(["s" => ["s"]], "[s]");
		// No rotation: the cycle starts where the walk from root `a` met it.
		expectCycles(["a" => ["z"], "z" => ["y"], "y" => ["z"]], "[z y]");
		// Neighbors keep edge order, and each back edge on the path is a cycle.
		expectCycles(["x" => ["z", "y"], "y" => ["x"], "z" => ["x"], "q" => ["x"]], "[x z] [x y]");
		// A repeated edge is met twice while its target is still on the path.
		expectCycles(["c" => ["a", "a"], "a" => ["b"], "b" => ["c"]], "[a b c] [a b c]");
		// A target with no outgoing edges, such as an external reference, ends the walk.
		expectCycles(["a" => ["external:other:x"]], "");
		// Byte order puts upper case first.
		expectCycles(["a" => ["B"], "B" => ["a"]], "[B a]");
		expectCycles(new Map<String, Array<String>>(), "");
	}

	/**
		Each expected layout lists the layers, then each node in byte order as
		`id=layer/position` with its blocking dependencies in angle brackets.
		The values follow upstream computeLayout by hand; parity covers the real runs.
	**/
	static function layoutContracts():Void {
		expectLayout(["a"], [], "[a] | a=0/0");
		// The longest blocking path sets the layer; other edge types do not count.
		expectLayout(["d", "c", "b", "a"], [
			edge("d", "a", "blocks"),
			edge("d", "c", "blocks"),
			edge("c", "b", "blocks"),
			edge("b", "a", "blocks"),
			edge("a", "d", "conditional-blocks"),
			edge("a", "c", "relates-to")
		], "[a] [b] [c] [d] | a=0/0 b=1/0<a> c=2/0<b> d=3/0<a c>");
		// A cycle, and anything that depends on it, stays in layer 0.
		expectLayout(["a", "b", "c", "d"], [
			edge("a", "b", "blocks"),
			edge("b", "a", "blocks"),
			edge("c", "a", "blocks"),
			edge("d", "x", "blocks")
		], "[a b c d] | a=0/0<b> b=0/1<a> c=0/2<a> d=0/3<x>");
		// Children move up to their parent's layer, whatever the edge order, but their dependents stay.
		expectLayout(["epic", "bug", "child", "leaf", "after"], [
			edge("leaf", "child", "parent-child"),
			edge("child", "epic", "parent-child"),
			edge("epic", "bug", "blocks"),
			edge("after", "leaf", "blocks")
		],
			"[bug] [after child epic leaf] | after=1/0<leaf> bug=0/0 child=1/1 epic=1/2<bug> leaf=1/3");
		// A layer that every node leaves stays in the list, empty.
		expectLayout(["x", "y"], [edge("x", "y", "blocks"), edge("y", "x", "parent-child")], "[] [x y] | x=1/0<y> y=1/1");
		// The last parent edge of a child wins.
		expectLayout(["p", "q", "c", "z"], [
			edge("q", "z", "blocks"),
			edge("c", "q", "parent-child"),
			edge("c", "p", "parent-child")
		], "[c p z] [q] | c=0/0 p=0/1 q=1/0<z> z=0/2");
		// Byte order puts upper case first; a repeated edge and a repeated issue count as given.
		expectLayout(["b", "B", "a", "b"], [edge("b", "a", "blocks"), edge("b", "a", "blocks")], "[B a] [b] | B=0/0 a=0/1 b=1/0<a a>");
	}

	/**
		The gutter grids are what upstream buildDAGGutterGrid prints for the same edges;
		the other values follow upstream graph_visual.go by hand. Parity covers the real runs.
	**/
	static function drawingContracts():Void {
		// Merges: crossings, arrowheads, joins, then T-junctions; anything else is overwritten.
		equal(dagMergeRune(" ", "╮"), "╮");
		equal(dagMergeRune("│", "─"), "┼");
		equal(dagMergeRune("─", "│"), "┼");
		equal(dagMergeRune("┼", "▶"), "▶");
		equal(dagMergeRune("─", "─"), "─");
		equal(dagMergeRune("│", "│"), "│");
		equal(dagMergeRune("│", "╮"), "┤");
		equal(dagMergeRune("│", "╯"), "┤");
		equal(dagMergeRune("│", "╰"), "├");
		equal(dagMergeRune("│", "╭"), "├");
		equal(dagMergeRune("─", "╮"), "┬");
		equal(dagMergeRune("─", "╭"), "┬");
		equal(dagMergeRune("─", "╰"), "┴");
		equal(dagMergeRune("─", "╯"), "┴");
		equal(dagMergeRune("╮", "─"), "─");
		equal(dagMergeRune("┤", "│"), "│");
		// A straight edge is an arrow on the title line; a lone row change turns in the middle column.
		expectGutter([gutterEdge(0, 0)], 2, [
			"      ",
			"─────▶",
			"      ",
			"      ",
			"      ",
			"      ",
			"      ",
			"      ",
			"      "
		]);
		expectGutter([gutterEdge(0, 1)], 2, [
			"      ",
			"───╮  ",
			"   │  ",
			"   │  ",
			"   │  ",
			"   │  ",
			"   ╰─▶",
			"      ",
			"      "
		]);
		expectGutter([gutterEdge(1, 0)], 2, [
			"      ",
			"   ╭─▶",
			"   │  ",
			"   │  ",
			"   │  ",
			"   │  ",
			"───╯  ",
			"      ",
			"      "
		]);
		// Two row changes take columns 1 and 4; later strokes merge over earlier ones.
		expectGutter([gutterEdge(0, 1), gutterEdge(1, 0), gutterEdge(0, 0)], 2, [
			"      ",
			"─────▶",
			" │  │ ",
			" │  │ ",
			" │  │ ",
			" │  │ ",
			"────┴▶",
			"      ",
			"      "
		]);
		expectGutter([gutterEdge(2, 0), gutterEdge(1, 0), gutterEdge(0, 2), gutterEdge(0, 0)], 3, [
			"      ", "─────▶", " ││ │ ", " ││ │ ", " ││ │ ", " ││ │ ", "─┼╯ │ ", " │  │ ", " │  │ ", " │  │ ", " │  │ ", "─╯  ╰▶", "      ", "      "
		]);
		// Past four row changes, channels share columns. A row past the grid is not drawn but
		// still takes a channel.
		expectGutter([
			gutterEdge(0, 1),
			gutterEdge(0, 2),
			gutterEdge(0, 3),
			gutterEdge(0, 4),
			gutterEdge(0, 5),
			gutterEdge(0, 9)
		], 6, [
			"      ", "───╮  ", " │││  ", " │││  ", " │││  ", " │││  ", " ││┼─▶", " │││  ", " │││  ", " │││  ", " │││  ", " ╰│┼─▶", "  ││  ", "  ││  ",
			"  ││  ", "  ││  ", "  │┼─▶", "  ││  ", "  ││  ", "  ││  ", "  ││  ", "  ╰┼─▶", "   │  ", "   │  ", "   │  ", "   │  ", "   ╰─▶", "      ",
			"      "
		]);
		// Boxes fit the title cut to 22 runes and the ID in bytes with its priority, and are at least 18 wide.
		equal(computeDagNodeWidth([dagNode("a-1", "", "open", 2)]), 18);
		equal(computeDagNodeWidth([dagNode("a-1", "Ünïcödé title", "open", 2)]), 18);
		equal(computeDagNodeWidth([dagNode("a-1", "A title much longer than twenty-two runes", "open", 2)]), 27);
		equal(computeDagNodeWidth([dagNode("a-ünïcödé-id", "x", "open", 2)]), 22);
		final tabbed = dagNode("a-1", "Tab\there", "closed", 3);
		equal(dagNodeLine(tabbed, 18, 0), "┌──────────────────┐");
		equal(dagNodeLine(tabbed, 18, 1), "│ ✓ Tab    here       │");
		equal(dagNodeLine(dagNode("a-1", "Tab\there", "open", 3), 18, 1), "│ ○ Tab\there       │");
		equal(dagNodeLine(tabbed, 18, 2), "│ a-1 P3           │");
		equal(dagNodeLine(tabbed, 18, 3), "└──────────────────┘");
		equal(dagNodeLine(dagNode("a-1", "A title much longer than the box", "hooked", 0), 18, 1), "│ ◇ A title much … │");
		equal(dagNodeLine(tabbed, 18, 4), "                    ");
		// An edge crosses every gutter up to its target, at the target's row past the first. A repeat,
		// a row into an earlier layer (here into a lifted child's dependent), and other types are left out.
		final ids = ["a", "b", "c", "d", "e", "f"];
		final edges = [
			edge("c", "d", "blocks"),
			edge("c", "b", "blocks"),
			edge("b", "a", "blocks"),
			edge("e", "d", "blocks"),
			edge("c", "a", "blocks"),
			edge("c", "e", "blocks"),
			edge("b", "a", "blocks"),
			edge("a", "c", "relates-to"),
			edge("b", "f", "blocks"),
			edge("f", "c", "parent-child")
		];
		final gutters = collectGutterEdges(computeGraphLayout(ids, edges), edges);
		equal([
			for (gutter in gutters) [for (row in gutter) '${row.sourceRow}>${row.targetRow}'].join(" ")
		].join(" | "), "1>0 0>0 1>1 | 0>0 1>0");
		equal(collectGutterEdges(computeGraphLayout(["a"], []), []).length, 0);
	}

	/** The compact view follows upstream renderGraphCompact by hand; parity covers the real runs. */
	static function compactContracts():Void {
		// Only a closed issue's tab turns into four spaces. A title is cut to 50 characters, counted in runes.
		equal(formatCompactNode(dagNode("a-1", "Tab\there", "closed", 3)), "✓ a-1 P3 Tab    here");
		equal(formatCompactNode(dagNode("a-1", "Tab\there", "deferred", 0)), "❄ a-1 P0 Tab\there");
		equal(formatCompactNode(dagNode("a-1", "Ü" + StringTools.lpad("", "x", 50), "hooked", 2)), "◇ a-1 P2 Ü" + StringTools.lpad("", "x", 48) + "…");
		// Children sort by priority, then by ID with numeric segments compared as numbers.
		equal(compareCompactChildren(dagNode("x-9", "", "open", 1), dagNode("x-1", "", "open", 2)) < 0, true);
		equal(compareCompactChildren(dagNode("x-10", "", "open", 2), dagNode("x-9", "", "open", 2)) > 0, true);
		equal(compareCompactChildren(dagNode("x-2.10", "", "open", 2), dagNode("x-2.9", "", "open", 2)) > 0, true);
		equal(compareCompactChildren(dagNode("x-1", "", "open", 2), dagNode("x-01", "", "open", 2)), 0);
		// A child keeps its own line in its layer and shows again below each parent, to any depth.
		final issues = [
			dagNode("t-root", "Root", "open", 1),
			dagNode("t-blk", "Blocker", "open", 3),
			dagNode("t-10", "Ten", "open", 2),
			dagNode("t-2", "Two", "closed", 2),
			dagNode("t-2.1", "Nested", "open", 0)
		];
		final edges = [
			edge("t-root", "t-blk", "blocks"),
			edge("t-10", "t-root", "parent-child"),
			edge("t-2", "t-root", "parent-child"),
			edge("t-2.1", "t-2", "parent-child")
		];
		final nodes = [for (issue in issues) issue.id => issue];
		equal(renderCompactGraph("t-root", nodes, computeGraphLayout([for (issue in issues) issue.id], edges), edges), [
			"",
			"📊 Dependency graph for t-root (5 issues, 2 layers)",
			"",
			"  Status: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred",
			"",
			"  LAYER 0 (ready)",
			"  └── ○ t-blk P3 Blocker",
			"",
			"  LAYER 1",
			"  ├── ○ t-10 P2 Ten",
			"  ├── ✓ t-2 P2 Two",
			"  │   └── ○ t-2.1 P0 Nested",
			"  ├── ○ t-2.1 P0 Nested",
			"  └── ○ t-root P1 Root",
			"      ├── ✓ t-2 P2 Two",
			"      │   └── ○ t-2.1 P0 Nested",
			"      └── ○ t-10 P2 Ten",
			"",
			""
		].join("\n"));
	}

	/** The `--open` filter follows upstream filterSubgraphOpen by hand; parity covers the real runs. */
	static function openContracts():Void {
		final issues:Array<OpenGraphIssue> = [
			openIssue("p", "open", 1),
			openIssue("a", "open", 2),
			openIssue("b", "closed", 2),
			openIssue("c", "open", 2),
			openIssue("d", "deferred", 3),
			openIssue("e", "in_progress", 1),
			openIssue("f", "blocked", 1),
			openIssue("g", "closed", 3),
			openIssue("g2", "hooked", 3),
			openIssue("h", "open", 1),
			openIssue("x", "pinned", 0)
		];
		final edges = [
			edge("b", "a", "blocks"),
			edge("c", "b", "blocks"),
			edge("c", "d", "blocks"),
			edge("f", "a", "blocks"),
			edge("f", "a", "blocks"),
			edge("f", "c", "blocks"),
			edge("a", "p", "parent-child"),
			edge("x", "p", "parent-child"),
			edge("a", "c", "relates-to"),
			edge("g", "c", "blocks"),
			edge("g2", "g", "blocks"),
			edge("h", "g2", "blocks"),
			edge("e", "d", "blocks")
		];
		// Rows between open issues stay once; then a walk joins each open issue to the open ones it
		// reaches over issues left out, unless a row already joins them. The walk stops at open issues.
		final open = filterOpenGraph("b", issues, edges);
		equal([for (row in open.edges) '${row.dependsOnId}>${row.issueId} ${row.type}'].join(", "),
			"a>f blocks, c>f blocks, p>a parent-child, c>a relates-to, a>c blocks, c>h blocks");
		// A left-out root gives way to the first issue with the lowest priority number.
		equal(open.rootId, "p");
		equal(filterOpenGraph("c", issues, edges).rootId, "c");
		equal(filterOpenGraph("b", [openIssue("b", "closed", 0), openIssue("x", "pinned", 0), openIssue("d", "deferred", 0)], []), null);
	}

	/** The page template keeps upstream's text, with its JavaScript escape, around the three values. */
	static function htmlContracts():Void {
		final page = graphHtmlPage("T &amp; t", "[N]", "[L]");
		equal(StringTools.startsWith(page, '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<title>T &amp; t</title>\n'), true);
		equal(page.indexOf('<script>\nconst nodes = [N];\nconst links = [L];\nconst statusColors = {') > 0, true);
		equal(page.indexOf('d.title.substring(0,17) + "\\u2026"') > 0, true);
		equal(StringTools.endsWith(page, "</script>\n</body>\n</html>\n"), true);
	}

	static function openIssue(id:String, status:String, priority:Int):OpenGraphIssue {
		return {id: id, status: status, priority: priority};
	}

	static function expectGutter(edges:Array<DagEdge>, rows:Int, expected:Array<String>):Void {
		equal(buildDagGutterGrid(edges, 6, rows * 5 - 1, 5).join("|"), expected.join("|"));
	}

	static function gutterEdge(sourceRow:Int, targetRow:Int):DagEdge {
		return {sourceRow: sourceRow, targetRow: targetRow};
	}

	static function dagNode(id:String, title:String, status:String, priority:Int):DagNode {
		return {
			id: id,
			title: title,
			status: status,
			priority: priority
		};
	}

	static function expectLayout(ids:Array<String>, edges:Array<GraphEdge>, expected:String):Void {
		final layout = computeGraphLayout(ids, edges);
		equal(layout.maxLayer, layout.layers.length - 1);
		final nodeIds = [for (id in layout.nodes.keys()) id];
		nodeIds.sort(compareUtf8);
		final nodes = [
			for (id in nodeIds) {
				final node = layout.nodes.get(id);
				final targets = node.dependsOn.length == 0 ? "" : '<${node.dependsOn.join(" ")}>';
				'${id}=${node.layer}/${node.position}${targets}';
			}
		];
		equal([for (layer in layout.layers) '[${layer.join(" ")}]'].join(" ") + " | " + nodes.join(" "), expected);
	}

	static function edge(issueId:String, dependsOnId:String, type:String):GraphEdge {
		return {issueId: issueId, dependsOnId: dependsOnId, type: type};
	}

	static function expectCycles(graph:Map<String, Array<String>>, expected:String):Void {
		equal([for (cycle in walkBlockingCycles(graph)) '[${cycle.join(" ")}]'].join(" "), expected);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
