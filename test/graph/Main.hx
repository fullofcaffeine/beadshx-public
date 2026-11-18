import beadshx.relation.DependencyCycle.walkBlockingCycles;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.relation.GraphLayout.computeGraphLayout;

/**
	Pins the `bd graph check` cycle walk against upstream issueops.DetectCyclesInTx,
	and the `bd graph <id>` layers against upstream computeLayout.

	Upstream walks from the roots in Go map order, so with two or more members its
	output can differ between runs. These values follow the same walk from the roots
	in byte order, one of upstream's possible outcomes; the parity smoke covers only
	the cases that every root order prints the same way.
**/
class Main {
	static function main():Void {
		cycleContracts();
		layoutContracts();
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
