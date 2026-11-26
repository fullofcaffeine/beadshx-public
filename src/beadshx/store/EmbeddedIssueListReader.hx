package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;
import beadshx.store.SqlIssueListReader.readSqlIssueList;

/** Own one read transaction for a list read; the list semantics are authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueListReader {
	static final WORDING = EmbeddedReadWording.forNoun("list", false);

	public static function read(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int, layers:IssueListConfigLayers):IssueListResult {
		return switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> readSqlIssueList(context, transaction, request, limit, layers)) {
			case EmbeddedReadNotStarted(stage, error, _): ListFailure(WORDING.stageMessage(stage, error));
			case EmbeddedReadFinished(result, cleanup): cleanup.length == 0 ? result : ListFailure(WORDING.cleanupMessage(cleanup[0]));
		};
	}
}
