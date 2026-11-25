package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.relation.RelatedIssue;
import beadshx.store.SqlGraphReader.GraphLoad;

/** Own one read transaction for `bd graph`, `bd graph --all` and `bd graph check`; the graph semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedGraphReader {
	public static function readCycles(beadsDir:String, databaseName:String):StoreResult<Array<Array<String>>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readGraphCycles(context, transaction));
	}

	public static function readSubgraph(beadsDir:String, databaseName:String, rootId:String):StoreResult<GraphLoad> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readGraphSubgraph(context, transaction, rootId));
	}

	public static function readIssues(beadsDir:String, databaseName:String, ids:Array<String>):StoreResult<Array<RelatedIssue>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readGraphIssues(context, transaction, ids));
	}

	public static function readAll(beadsDir:String, databaseName:String, maxRows:Int):StoreResult<SqlGraphReader.AllGraphLoad> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlGraphReader.readAllGraphs(context, transaction, maxRows));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		return EmbeddedReadWording.forNoun("graph", false).cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, reader));
	}
}
