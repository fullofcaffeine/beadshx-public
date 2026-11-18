import beadshx.relation.DependencyTree.TreeDirection;
import beadshx.relation.DependencyTree.TreeNode;
import beadshx.relation.DependencyTree.mergeBidirectionalTree;
import beadshx.relation.DependencyTree.parseTreeDirection;
import beadshx.relation.DependencyTree.pruneBidirectionalByStatus;
import beadshx.relation.DependencyTree.pruneTreeByStatus;

/**
	Pins the dependency-tree prune and merge rules against upstream issueops.

	The prune and merge values were printed by running upstream PruneTreeByStatus and
	MergeBidirectionalTree on the same nodes (a one-off oracle under
	.toolchains/tree-walk-oracle). The `both` prune follows upstream
	pruneBidirectionalByStatus, which is not exported.
**/
class Main {
	static function main():Void {
		pruneContracts();
		mergeContracts();
		bidirectionalContracts();
		directionContracts();
		Sys.println("dep tree Haxe contracts: PASS");
	}

	static function pruneContracts():Void {
		final tree = [
			node("r", "open", 0, ""),
			node("a", "closed", 1, "r"),
			node("b", "open", 2, "a"),
			node("c", "closed", 1, "r"),
			node("d", "blocked", 2, "c")
		];
		equal(show(pruneTreeByStatus(tree, "open")), "[r@0< a@1<r b@2<a]");
		equal(show(pruneTreeByStatus(tree, "closed")), "[r@0< a@1<r c@1<r]");
		equal(show(pruneTreeByStatus(tree, "blocked")), "[r@0< c@1<r d@2<c]");
		equal(show(pruneTreeByStatus(tree, "deferred")), "[]");
		final loop = [node("x", "open", 1, "y"), node("y", "closed", 1, "x"), node("s", "open", 0, "s")];
		equal(show(pruneTreeByStatus(loop, "open")), "[x@1<y y@1<x s@0<s]");
	}

	static function mergeContracts():Void {
		final down = [node("r", "open", 0, ""), node("x", "open", 1, "r")];
		final up = [node("r", "open", 0, ""), node("y", "closed", 1, "r"), node("x", "open", 2, "y")];
		equal(show(mergeBidirectionalTree(down, up, "r")), "[y@1<r x@2<y r@0< x@1<r]");
		equal(show(mergeBidirectionalTree(down, [], "r")), "[r@0< x@1<r]");
	}

	static function bidirectionalContracts():Void {
		final down = [node("r", "open", 0, ""), node("x", "open", 1, "r")];
		final up = [node("r", "open", 0, ""), node("y", "closed", 1, "r")];
		// Only the up half survives, so the down half gets its root back.
		final upOnly = pruneBidirectionalByStatus(down, up, "r", "closed");
		equal(show(upOnly.down), "[r@0<]");
		equal(show(upOnly.up), "[r@0< y@1<r]");
		equal(show(mergeBidirectionalTree(upOnly.down, upOnly.up, "r")), "[y@1<r r@0<]");
		// The down half keeps its own root; nothing is added.
		final both = pruneBidirectionalByStatus(down, up, "r", "open");
		equal(show(both.down), "[r@0< x@1<r]");
		equal(show(both.up), "[r@0<]");
		// Nothing survives: the answer stays empty, root included.
		final none = pruneBidirectionalByStatus(down, up, "r", "deferred");
		equal(show(mergeBidirectionalTree(none.down, none.up, "r")), "[]");
	}

	static function directionContracts():Void {
		equal(parseTreeDirection("down"), TreeDown);
		equal(parseTreeDirection("up"), TreeUp);
		equal(parseTreeDirection("both"), TreeBoth);
		equal(parseTreeDirection("Down"), null);
		equal(parseTreeDirection(""), null);
	}

	static function node(id:String, status:String, depth:Int, parentId:String):TreeNode<String> {
		return {
			id: id,
			status: status,
			issue: id,
			depth: depth,
			parentId: parentId,
			edgeFromParent: depth == 0 ? "" : "blocks"
		};
	}

	static function show(nodes:Array<TreeNode<String>>):String {
		return "[" + [for (node in nodes) '${node.id}@${node.depth}<${node.parentId}'].join(" ") + "]";
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
