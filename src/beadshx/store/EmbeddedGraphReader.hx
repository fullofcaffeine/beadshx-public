package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.relation.RelatedIssue;
import beadshx.store.SqlGraphReader.AllGraphLoad;
import beadshx.store.SqlGraphReader.GraphLoad;

/**
	Own one read transaction for `bd graph`, `bd graph --all` and `bd graph check`; the graph semantics are authored Haxe.

	Each read stands for several upstream store calls, each with its own
	rollback. After a failed body, upstream `withConn` joins the failed
	rollback and closes to the body's error, which already carries the words
	of upstream's caller. After a successful body, the first upstream call of
	the flow is the one that meets a failed release step, so its caller's
	words come first.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedGraphReader {
	static final WORDING = EmbeddedReadWording.forNoun("graph", false);

	/** Upstream DetectCycles, one store call whose error `bd graph check` wraps itself. */
	public static function readCycles(beadsDir:String, databaseName:String):StoreResult<Array<Array<String>>> {
		return WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, SqlGraphReader.readGraphCycles));
	}

	public static function readSubgraph(beadsDir:String, databaseName:String, rootId:String):StoreResult<GraphLoad> {
		return finishSubgraph(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlGraphReader.readGraphSubgraph(context, transaction, rootId)));
	}

	public static function readIssues(beadsDir:String, databaseName:String, ids:Array<String>):StoreResult<Array<RelatedIssue>> {
		return WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlGraphReader.readGraphIssues(context, transaction, ids)));
	}

	public static function readAll(beadsDir:String, databaseName:String, maxRows:Int):StoreResult<AllGraphLoad> {
		return finishAllGraphs(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlGraphReader.readAllGraphs(context, transaction, maxRows)));
	}

	/** loadGraphSubgraph wraps its first store call, GetIssue of the root, with `failed to get issue: `. */
	static function finishSubgraph<T>(read:EmbeddedRead<StoreResult<T>>):StoreResult<T> {
		return afterCallerWords(read, "failed to get issue");
	}

	/**
		loadAllGraphSubgraphs wraps its first store call, SearchIssues of the
		open issues, with `failed to search issues: `. A row cap comes from
		inside SearchIssues, and `handleMaxRowsError` finds it through the
		join with `errors.As`, so the cap stays and the release errors go.
		Upstream searches the open, in_progress and blocked issues in three
		store calls; this one read cannot tell which search a failed release
		step would have met first, so the cap stays for each of them.
	**/
	static function finishAllGraphs(read:EmbeddedRead<StoreResult<AllGraphLoad>>):StoreResult<AllGraphLoad> {
		return switch read {
			case EmbeddedReadFinished(Success(AllGraphRowLimitExceeded(found, cap)), _): Success(AllGraphRowLimitExceeded(found, cap));
			case _: afterCallerWords(read, "failed to search issues");
		};
	}

	/** `withConn`'s join, with `callerWords` before the release errors of a successful body. */
	static function afterCallerWords<T>(read:EmbeddedRead<StoreResult<T>>, callerWords:String):StoreResult<T> {
		return switch read {
			case EmbeddedReadFinished(Success(_), cleanup) if (cleanup.length > 0):
				Failure('$callerWords: ${EmbeddedReadWording.joinReadErrors(null, cleanup)}');
			case _: WORDING.joinedResult(read);
		};
	}
}
