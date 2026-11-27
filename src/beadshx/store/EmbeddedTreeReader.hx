package beadshx.store;

import beadshx.relation.DependencyTree.DependencyTreeRequest;
import beadshx.relation.DependencyTree.TreeNode;
import beadshx.relation.RelatedIssue;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlTreeReader.readSqlTree;

/** Own one read transaction for `bd dep tree`; the walk semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedTreeReader {
	public static function read(beadsDir:String, databaseName:String, request:DependencyTreeRequest):StoreResult<Array<TreeNode<RelatedIssue>>> {
		return EmbeddedReadWording.forNoun("tree", false)
			.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlTree(context, transaction, request)));
	}
}
