import beadshx.relation.DependencyCycle.walkBlockingCycles;

/**
	Pins the `bd graph check` cycle walk against upstream issueops.DetectCyclesInTx.

	Upstream walks from the roots in Go map order, so with two or more members its
	output can differ between runs. These values follow the same walk from the roots
	in byte order, one of upstream's possible outcomes; the parity smoke covers only
	the cases that every root order prints the same way.
**/
class Main {
	static function main():Void {
		cycleContracts();
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

	static function expectCycles(graph:Map<String, Array<String>>, expected:String):Void {
		equal([for (cycle in walkBlockingCycles(graph)) '[${cycle.join(" ")}]'].join(" "), expected);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
