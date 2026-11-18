import beadshx.relation.DependencyCycle.buildCycles;
import beadshx.relation.DependencyCycle.canonicalCyclePaths;

/**
	Pins the canonical cycle order against upstream issueops.CanonicalCyclePaths.

	Each expected value was printed by running upstream's own function on the same
	graph (a one-off oracle under .toolchains/cycle-paths-oracle).
**/
class Main {
	static function main():Void {
		pathContracts();
		buildContracts();
		Sys.println("dep cycles Haxe contracts: PASS");
	}

	static function pathContracts():Void {
		expectPaths(["b" => ["a"], "a" => ["b"]], "[a b]");
		expectPaths(["c" => ["a", "a"], "a" => ["b"], "b" => ["c"]], "[a b c]");
		expectPaths(["x" => ["z", "y"], "y" => ["x"], "z" => ["x"], "q" => ["x"]], "[x y] [x z]");
		expectPaths(["s" => ["s"]], "[s]");
		expectPaths(["m" => ["k"], "k" => ["z"], "z" => ["m"]], "[k z m]");
		expectPaths(["a" => ["ext:1"]], "");
		expectPaths(["d" => ["b"], "b" => ["c"], "c" => ["b"]], "[b c]");
		expectPaths(["B" => ["a"], "a" => ["B"], "é" => ["a"], "a.1" => ["é"]], "[B a]");
	}

	static function buildContracts():Void {
		var lookups = 0;
		final cycles = buildCycles([["a", "ghost"], ["a", "b"]], id -> {
			lookups++;
			return id == "ghost" ? null : id;
		});
		equal(lookups, 3);
		equal(cycles.length, 2);
		equal(cycles[0].partial, true);
		equal(cycles[0].members[1].id, "ghost");
		equal(cycles[0].members[1].issue, null);
		equal(cycles[1].partial, false);
		equal(cycles[1].members[1].issue, "b");
	}

	static function expectPaths(graph:Map<String, Array<String>>, expected:String):Void {
		equal([for (path in canonicalCyclePaths(graph)) '[${path.join(" ")}]'].join(" "), expected);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
