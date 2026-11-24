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
import beadshx.cli.TerminalStyles;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.relation.OpenGraph.OpenGraphIssue;
import beadshx.relation.OpenGraph.filterOpenGraph;
import beadshx.relation.AllGraphs.AllGraphIssue;
import beadshx.relation.AllGraphs.groupAllGraphs;
import beadshx.relation.GoSort.goPdqsort;
import beadshx.relation.GoSort.goSortSlice;
import beadshx.store.SqlRowCap;

/** Generated keys for one Go sort.Slice oracle case, and the labels the oracle prints for them. */
private typedef SortCase = {
	final n:Int;
	final seed:Int;
	final distinct:Int;
	final pattern:String;
	final labels:String;
}

private typedef SortItem = {
	final key:Int;
	final label:Int;
}

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
	/** Upstream's styles with colors off: every style is empty and turns a tab into four spaces, as lipgloss does. */
	static final plainStyles = TerminalStyles.plain(_ -> new EmptyLipglossStyle());

	static function main():Void {
		cycleContracts();
		layoutContracts();
		drawingContracts();
		compactContracts();
		openContracts();
		htmlContracts();
		goSortContracts();
		allGraphContracts();
		rowCapContracts();
		Sys.println("graph Haxe contracts: PASS");
	}

	/**
		`graph --all` asks for one row more than its cap. A cap of 2147483647 must ask for
		LIMIT 2147483648, not a 32-bit wrap. The parity smoke cannot run that query, because
		Dolt reserves memory in proportion to the limit (about 1.8 GB in upstream bd too).
	**/
	static function rowCapContracts():Void {
		equal(SqlRowCap.limitClause(0), "");
		equal(SqlRowCap.limitClause(-1), "");
		equal(SqlRowCap.limitClause(1), " LIMIT 2");
		equal(SqlRowCap.limitClause(2147483646), " LIMIT 2147483647");
		equal(SqlRowCap.limitClause(2147483647), " LIMIT 2147483648");
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
		equal(dagNodeLine(tabbed, 18, 0, plainStyles), "┌──────────────────┐");
		equal(dagNodeLine(tabbed, 18, 1, plainStyles), "│ ✓ Tab    here       │");
		equal(dagNodeLine(dagNode("a-1", "Tab\there", "open", 3), 18, 1, plainStyles), "│ ○ Tab\there       │");
		equal(dagNodeLine(tabbed, 18, 2, plainStyles), "│ a-1 P3           │");
		equal(dagNodeLine(tabbed, 18, 3, plainStyles), "└──────────────────┘");
		equal(dagNodeLine(dagNode("a-1", "A title much longer than the box", "hooked", 0), 18, 1, plainStyles), "│ ◇ A title much … │");
		equal(dagNodeLine(tabbed, 18, 4, plainStyles), "                    ");
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
		equal(formatCompactNode(dagNode("a-1", "Tab\there", "closed", 3), plainStyles), "✓ a-1 P3 Tab    here");
		equal(formatCompactNode(dagNode("a-1", "Tab\there", "deferred", 0), plainStyles), "❄ a-1 P0 Tab\there");
		equal(formatCompactNode(dagNode("a-1", "Ü" + StringTools.lpad("", "x", 50), "hooked", 2), plainStyles),
			"◇ a-1 P2 Ü" + StringTools.lpad("", "x", 48) + "…");
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
		equal(renderCompactGraph("t-root", nodes, computeGraphLayout([for (issue in issues) issue.id], edges), edges, plainStyles), [
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

	/**
		Each case lists the labels that Go's sort.Slice leaves for generated keys, as the
		git-ignored one-off oracle `.toolchains/gosort-oracle/main.go` prints them: in full
		up to 64 elements, and as two rolling hashes `#a/b` above. Equal keys show where
		pdqsort leaves equal elements. The cases reach every branch but heapsort, which
		the oracle's copy of pdqsort reaches when no bad pivots are left.
	**/
	static function goSortContracts():Void {
		final cases = [
			"0 7 3 random|",
			"0 23 1 reversed|",
			"1 7 3 random|0",
			"1 23 1 reversed|0",
			"12 7 3 random|3 7 8 5 6 9 0 1 2 4 10 11",
			"12 23 1 reversed|11 10 9 8 7 6 5 4 3 2 1 0",
			"13 7 3 random|3 8 7 6 5 9 4 0 2 1 10 11 12",
			"13 11 1000 random|4 2 11 9 12 7 3 6 8 5 0 10 1",
			"13 3 2 sorted|0 1 2 3 4 5 6 7 8 9 10 11 12",
			"13 5 2 reversed|12 11 10 8 9 6 7 5 4 3 2 0 1",
			"13 9 1 equal|0 1 2 3 4 5 6 7 8 9 10 11 12",
			"13 13 3 organ|0 1 2 12 11 9 8 5 10 4 3 6 7",
			"13 17 4 sawtooth|8 12 4 0 1 9 5 6 10 2 7 3 11",
			"13 19 7 nearly|0 1 2 3 7 4 10 5 6 12 8 9 11",
			"13 23 1 reversed|12 11 10 9 8 7 6 5 4 3 2 1 0",
			"20 7 3 random|7 17 15 3 14 8 5 16 18 9 6 13 12 11 4 2 10 1 0 19",
			"20 11 1000 random|4 2 17 14 16 11 9 12 7 3 15 6 18 13 19 8 5 0 10 1",
			"20 3 2 sorted|0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19",
			"20 5 2 reversed|19 18 17 16 15 14 13 11 12 10 9 8 7 6 5 4 3 2 1 0",
			"20 9 1 equal|0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19",
			"20 13 3 organ|0 1 2 19 18 15 5 3 4 17 16 12 6 13 14 8 7 11 10 9",
			"20 17 4 sawtooth|0 16 4 12 8 1 17 5 13 9 10 6 14 2 18 11 7 15 3 19",
			"20 19 7 nearly|0 1 2 3 4 7 5 6 8 9 11 12 13 14 15 16 17 10 18 19",
			"20 23 1 reversed|19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0",
			"51 7 3 random|15 47 46 3 43 42 39 7 8 38 36 30 26 17 14 35 29 13 18 49 20 21 5 23 24 41 6 9 16 32 40 31 28 33 34 0 10 37 27 12 11 25 22 4 44 45 2 1 48 19 50",
			"51 11 1000 random|48 25 42 44 4 49 47 2 31 17 50 41 30 14 45 22 16 26 11 34 9 20 28 12 21 29 24 23 37 39 7 32 3 15 6 18 13 19 8 33 40 5 46 27 38 0 43 10 35 36 1",
			"51 3 2 sorted|0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50",
			"51 5 2 reversed|50 49 48 47 46 45 44 43 42 40 41 39 38 37 36 34 35 33 32 31 30 29 28 26 27 25 24 23 22 21 20 19 18 17 16 14 15 13 12 11 10 8 9 7 6 5 4 3 2 0 1",
			"51 9 1 equal|0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50",
			"51 13 3 organ|50 1 2 0 49 3 4 5 46 47 48 44 8 43 6 45 7 10 9 11 42 41 40 12 14 13 39 38 37 35 34 15 36 16 17 20 31 32 33 18 19 29 23 22 21 28 30 24 25 26 27",
			"51 17 4 sawtooth|16 48 44 40 4 36 32 28 8 0 24 20 12 25 29 49 13 17 1 45 41 21 37 5 33 9 6 42 50 26 30 18 14 10 34 46 2 22 38 39 3 11 27 43 23 19 35 47 31 15 7",
			"51 19 7 nearly|0 1 2 3 4 5 6 8 12 9 10 11 13 14 15 38 16 17 18 19 20 21 22 23 24 43 25 26 27 28 29 30 31 7 32 33 34 35 46 37 36 40 41 42 39 44 45 47 48 49 50",
			"51 23 1 reversed|50 49 48 47 46 45 44 43 42 41 40 39 38 37 36 35 34 33 32 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0",
			"100 7 3 random|#33045/19146",
			"100 11 1000 random|#4666/27720",
			"100 3 2 sorted|#63475/42752",
			"100 5 2 reversed|#13559/46961",
			"100 9 1 equal|#63475/42752",
			"100 13 3 organ|#61689/634",
			"100 17 4 sawtooth|#26548/63484",
			"100 19 7 nearly|#22085/17725",
			"100 23 1 reversed|#43340/27533",
			"1000 7 3 random|#37176/53465",
			"1000 11 1000 random|#24648/11159",
			"1000 3 2 sorted|#64505/49179",
			"1000 5 2 reversed|#899/41243",
			"1000 9 1 equal|#64505/49179",
			"1000 13 3 organ|#50582/20777",
			"1000 17 4 sawtooth|#52020/3387",
			"1000 19 7 nearly|#22408/28724",
			"1000 23 1 reversed|#63616/60859"
		];
		final heapCases = [
			"13 7 3 random|8 7 3 6 5 9 11 2 10 4 1 12 0",
			"20 11 1000 random|4 2 17 14 16 11 9 12 7 3 15 6 18 13 19 8 5 0 10 1",
			"64 13 3 organ|62 1 63 2 0 60 5 59 3 61 4 56 58 6 8 7 57 55 54 53 11 9 10 14 13 12 50 52 51 49 48 47 17 16 15 46 44 45 20 19 18 23 22 43 21 42 41 26 25 24 40 39 38 29 28 27 37 36 35 30 34 33 32 31"
		];
		for (line in cases) {
			final sample = sortCase(line);
			final items = sortInput(sample);
			goSortSlice(items, (left, right) -> left.key < right.key);
			equal(sortLabels(items), sample.labels);
		}
		for (line in heapCases) {
			final sample = sortCase(line);
			final items = sortInput(sample);
			goPdqsort({
				less: (i, j) -> {
					final left:SortItem = items[i];
					final right:SortItem = items[j];
					return left.key < right.key;
				},
				swap: (i, j) -> {
					final left:SortItem = items[i];
					items[i] = items[j];
					items[j] = left;
				}
			}, 0, items.length, 0);
			equal(sortLabels(items), sample.labels);
		}
	}

	/** One case written as `n seed distinct pattern|labels`. */
	static function sortCase(line:String):SortCase {
		final parts = line.split("|");
		final fields = parts[0].split(" ");
		return {
			n: Std.parseInt(fields[0]),
			seed: Std.parseInt(fields[1]),
			distinct: Std.parseInt(fields[2]),
			pattern: fields[3],
			labels: parts[1]
		};
	}

	/** The oracle's key generator. */
	static function sortInput(sample:SortCase):Array<SortItem> {
		final items = new Array<SortItem>();
		var x = sample.seed;
		for (i in 0...sample.n) {
			x = (x * 75 + 74) % 65537;
			final key = switch sample.pattern {
				case "random": x % sample.distinct;
				case "sorted": Std.int(i / sample.distinct);
				case "reversed": Std.int((sample.n - i) / sample.distinct);
				case "organ": i < Std.int(sample.n / 2) ? Std.int(i / sample.distinct) : Std.int((sample.n - i) / sample.distinct);
				case "sawtooth": i % sample.distinct;
				case "nearly": x % sample.distinct == 0 ? x % sample.n : i;
				case _: 0;
			};
			items.push({key: key, label: i});
		}
		return items;
	}

	static function sortLabels(items:Array<SortItem>):String {
		if (items.length <= 64)
			return [for (item in items) Std.string(item.label)].join(" ");
		var first = 0;
		var second = 0;
		for (item in items) {
			first = (first * 31 + item.label + 1) % 65521;
			second = (second * 37 + item.label + 1) % 65519;
		}
		return '#${first}/${second}';
	}

	/**
		The groups follow upstream assembleAllSubgraphs by hand, except the order of the
		tied singletons, which the sort oracle printed from Go's sort.Slice.
	**/
	static function allGraphContracts():Void {
		// Walks start in issue order and visit neighbors in row order; larger groups come
		// first. An epic outranks any other root; among equals a lower priority number wins.
		expectGroups([
			graphIssue("a", 2, "task"),
			graphIssue("b", 1, "task"),
			graphIssue("c", 3, "epic"),
			graphIssue("d", 3, "task"),
			graphIssue("e", 1, "task"),
			graphIssue("f", 1, "bug"),
			graphIssue("g", 0, "task"),
			graphIssue("h", 1, "epic")
		], [
			edge("b", "a", "blocks"),
			edge("e", "d", "blocks"),
			edge("c", "a", "parent-child"),
			edge("g", "c", "relates-to"),
			edge("h", "g", "blocks")
		], "h:[a b c g h]<0 2 3 4> e:[d e]<1> f:[f]");
		// Two groups of one size keep the priority order of their first members.
		expectGroups([graphIssue("x", 3, "task"), graphIssue("y", 1, "task"), graphIssue("z", 2, "task")], [], "y:[y] z:[z] x:[x]");
		// More than 12 groups: sort.Slice does not keep tied groups in issue order.
		final priorities = [2, 2, 1, 3, 2, 1, 0, 2, 2, 1, 3, 2, 2, 1];
		final singletons = [
			for (index in 0...priorities.length)
				graphIssue('s${index}', priorities[index], "task")
		];
		equal([for (group in groupAllGraphs(singletons, [])) group.rootId].join(" "), "s6 s9 s2 s5 s13 s4 s1 s7 s8 s0 s11 s12 s3 s10");
		expectGroups([], [], "");
	}

	static function expectGroups(issues:Array<AllGraphIssue>, edges:Array<GraphEdge>, expected:String):Void {
		equal([
			for (group in groupAllGraphs(issues, edges)) {
				final rows = group.edgeIndexes.length == 0 ? "" : '<${group.edgeIndexes.join(" ")}>';
				'${group.rootId}:[${group.issueIds.join(" ")}]${rows}';
			}
		].join(" "), expected);
	}

	static function graphIssue(id:String, priority:Int, issueType:String):AllGraphIssue {
		return {id: id, priority: priority, issueType: issueType};
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

/** Stands in for an empty lipgloss v2 style, which prints the text with each tab turned into four spaces. */
private final class EmptyLipglossStyle implements TextStyle {
	public function new() {}

	public function render(text:String):String {
		return StringTools.replace(text, "\t", "    ");
	}
}
