package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.relation.DependencyTree.DependencyTreeRequest;
import beadshx.relation.DependencyTree.TreeNode;
import beadshx.relation.RelatedIssue;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.SqlTreeReader.readSqlTree;

/** Own one read transaction for `bd dep tree`; the walk semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedTreeReader {
	public static function read(beadsDir:String, databaseName:String, request:DependencyTreeRequest):StoreResult<Array<TreeNode<RelatedIssue>>> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only tree snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded tree connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded tree transaction: ${started.value2.toString()}');
		}
		final outcome = readSqlTree(context, started.value1, request);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded tree transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded tree database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded tree connector: ${closeConnectorError.toString()}');
		return outcome;
	}
}
