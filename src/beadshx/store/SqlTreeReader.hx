package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyTree.DependencyTreeRequest;
import beadshx.relation.DependencyTree.TreeDirection;
import beadshx.relation.DependencyTree.TreeNode;
import beadshx.relation.DependencyTree.mergeBidirectionalTree;
import beadshx.relation.DependencyTree.pruneBidirectionalByStatus;
import beadshx.relation.DependencyTree.pruneTreeByStatus;
import beadshx.relation.RelatedIssue;
import beadshx.relation.RelationRead.prepareRelationRead;
import beadshx.store.SqlIssueReader.readIssueInTx;
import beadshx.store.SqlRelationReader.readSqlRelations;

/**
	Walks a dependency tree in the caller's SQL snapshot, like upstream issueops.WalkDependencyTreeInTx.

	The root is read first, so a missing root fails instead of giving an empty tree.
	The walk is depth first. Each node is read like GetIssueInTx, and its neighbors come
	from both dependency tables in raw row order; `relates-to` edges are not followed.
	A node already visited is not visited again, so a cycle ends the descent, and nodes
	at `maxDepth` or deeper are not included. A `both` walk prunes each half by status
	before the halves are merged. Any read error stops the walk. The caller owns the
	transaction and connection lifetime, and checks the row cap afterward.
**/
@:goNative
final class SqlTreeReader {
	public static function readSqlTree(context:Context, transaction:Tx, request:DependencyTreeRequest):StoreResult<Array<TreeNode<RelatedIssue>>> {
		switch readIssueInTx(context, transaction, request.rootId) {
			case Failure(message):
				return Failure(message);
			case Success(_):
		}
		final reverse = switch request.direction {
			case TreeDown: false;
			case TreeUp: true;
			case TreeBoth: return readBidirectionalTree(context, transaction, request);
		};
		final nodes = switch walk(context, transaction, request.rootId, request.maxDepth, reverse) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		return Success(request.status == "" ? nodes : pruneTreeByStatus(nodes, request.status));
	}

	static function readBidirectionalTree(context:Context, transaction:Tx, request:DependencyTreeRequest):StoreResult<Array<TreeNode<RelatedIssue>>> {
		var down = switch walk(context, transaction, request.rootId, request.maxDepth, false) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		var up = switch walk(context, transaction, request.rootId, request.maxDepth, true) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		if (request.status != "") {
			final pruned = pruneBidirectionalByStatus(down, up, request.rootId, request.status);
			down = pruned.down;
			up = pruned.up;
		}
		return Success(mergeBidirectionalTree(down, up, request.rootId));
	}

	static function walk(context:Context, transaction:Tx, rootId:String, maxDepth:Int, reverse:Bool):StoreResult<Array<TreeNode<RelatedIssue>>> {
		final nodes = new Array<TreeNode<RelatedIssue>>();
		final failure = visit(context, transaction, {
			id: rootId,
			depth: 0,
			maxDepth: maxDepth,
			reverse: reverse,
			parentId: "",
			edgeFromParent: ""
		}, new Map<String, Bool>(), nodes);
		return failure == null ? Success(nodes) : Failure(failure);
	}

	/** Appends one node and its subtree to `nodes`; returns an error message, or null. */
	static function visit(context:Context, transaction:Tx, step:TreeStep, visited:Map<String, Bool>, nodes:Array<TreeNode<RelatedIssue>>):Null<String> {
		if (step.depth >= step.maxDepth || visited.exists(step.id))
			return null;
		visited.set(step.id, true);
		final issue = switch readIssueInTx(context, transaction, step.id) {
			case Failure(message): return message;
			case Success(value): value;
		};
		final plan = switch prepareRelationRead(step.id, step.reverse ? "in" : "out", []) {
			case RelationPlanInvalid(message): return message;
			case RelationPlanReady(value): value;
		};
		final related = switch readSqlRelations(context, transaction, plan) {
			case Failure(message): return message;
			case Success(rows): rows;
		};
		nodes.push({
			id: issue.id,
			status: issue.status,
			issue: issue,
			depth: step.depth,
			parentId: step.parentId,
			edgeFromParent: step.edgeFromParent
		});
		for (neighbor in related) {
			if (neighbor.dependencyType == "relates-to")
				continue;
			final failure = visit(context, transaction, {
				id: neighbor.fields.id,
				depth: step.depth + 1,
				maxDepth: step.maxDepth,
				reverse: step.reverse,
				parentId: step.id,
				edgeFromParent: neighbor.dependencyType
			}, visited, nodes);
			if (failure != null)
				return failure;
		}
		return null;
	}
}

/** Where the walk is: the node to visit and the edge that led to it. */
private typedef TreeStep = {
	final id:String;
	final depth:Int;
	final maxDepth:Int;
	final reverse:Bool;
	final parentId:String;
	final edgeFromParent:String;
}
