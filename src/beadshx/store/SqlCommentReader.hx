package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullInt64;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.Time;
import go.NativePointer;

/** One bound issue ID; the embedded store resolves the comment table itself. */
typedef SqlCommentRead = {
	final id:String;
}

/** Detail body inclusion does not suppress the independent aggregate count. */
typedef SqlCommentDetailRead = {
	> SqlCommentRead,
	final includeComments:Bool;
}

/** The native detail count is int64, including values wider than Haxe Int. */
typedef SqlCommentDetails = {
	final comments:Array<IssueComment>;
	final commentCount:JsonInteger;
	final commentsOmitted:Bool;
}

/**
	Port the embedded store's direct comment path, rather than its UOW adapter.

	CountIssueComments always reads durable comments. Requested bodies separately
	probe active wisps, even when the issue row came from the durable table. Query
	and scan wrappers belong to issueops; detail assembly adds the iterator prefix.
	Rows.Err precedes the ignored deferred Close, preserving the first error.
**/
@:goNative
final class SqlCommentReader {
	/** Count errors are ignored upstream, but a value scanned before an error survives. */
	public static function readSqlIssueCommentDetails(context:Context, transaction:Tx, read:SqlCommentDetailRead):StoreResult<SqlCommentDetails> {
		final count = readSqlCommentCount(context, transaction, read.id);
		if (!read.includeComments)
			return Success({comments: [], commentCount: count, commentsOmitted: count.compare(0) > 0});
		return switch readSqlIssueComments(context, transaction, read) {
			case Failure(message): Failure(message);
			case Success(comments): Success({comments: comments, commentCount: count, commentsOmitted: false});
		};
	}

	static function readSqlCommentCount(context:Context, transaction:Tx, id:String):JsonInteger {
		final value = new NullInt64();
		// NullInt64 uses database/sql's int64 conversion without narrowing. Its
		// different NULL error is immaterial here: both destinations retain zero,
		// and the pinned detail assembler discards this error independently.
		transaction.queryRowContext(context, "SELECT count(*) FROM comments WHERE issue_id = ?", id).scanInt64(value);
		return NativeIntegers.fromInt64(value.value);
	}

	public static function readSqlIssueComments(context:Context, transaction:Tx, read:SqlCommentRead):StoreResult<Array<IssueComment>> {
		// IsActiveWispInTx deliberately falls back on every query or scan error.
		final table = SqlWispRouting.isActiveWispInTx(context, transaction, read.id) ? "wisp_comments" : "comments";
		final query = 'SELECT id, issue_id, author, text, created_at FROM $table WHERE issue_id = ? ORDER BY created_at ASC, id ASC';
		final outer = 'iter comments ${read.id}: ';
		final queried = transaction.queryContext(context, query, read.id);
		if (queried.value2 != null)
			return Failure(outer + 'get issue comments from $table: ' + queried.value2.toString());
		final rows = queried.value1;
		final comments = new Array<IssueComment>();
		while (rows.next()) {
			final id = NativePointer.of("");
			final issueId = NativePointer.of("");
			final author = NativePointer.of("");
			final text = NativePointer.of("");
			final createdAt = new Time();
			final scanError = rows.scan(id, issueId, author, text, createdAt);
			if (scanError != null) {
				rows.close();
				return Failure(outer + "get issue comments: scan: " + scanError.toString());
			}
			comments.push({
				id: id.get(),
				issueId: issueId.get(),
				author: author.get(),
				text: text.get(),
				createdAt: createdAt.format("2006-01-02T15:04:05.999999999Z07:00")
			});
		}
		final iterationError = rows.err();
		rows.close();
		return iterationError == null ? Success(comments) : Failure(outer + iterationError.toString());
	}
}
