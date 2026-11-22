package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlCommentReader.readSqlDirectIssueComments;

/** Own one read transaction for `bd comments`; the comment read is authored Haxe. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCommentReader {
	public static function read(beadsDir:String, databaseName:String, issueId:String):StoreResult<Array<IssueComment>> {
		return EmbeddedReadWording.forNoun("comments", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> readSqlDirectIssueComments(context, transaction, issueId)));
	}
}
