package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/** Result of one Haxe-owned partial-ID candidate scan. */
enum EmbeddedIssueIdSearchResult {
	EmbeddedIssueIds(ids:Array<String>);
	EmbeddedIssueIdSearchFailure(message:String);
}

/** Supplies deduplicated issue and wisp IDs to Haxe abbreviation policy. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueIdSearch {
	static final READ_IDS = "SELECT id FROM (" + "SELECT id FROM issues WHERE LOWER(id) LIKE ? " + "UNION SELECT id FROM wisps WHERE LOWER(id) LIKE ?"
		+ ") candidates ORDER BY id ASC";

	static final WORDING = new EmbeddedReadWording("open embedded issue-ID connector", "ping embedded issue-ID database",
		"begin embedded issue-ID transaction");

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(query:String):EmbeddedIssueIdSearchResult {
		final read = EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readIds(context, transaction, query));
		return switch WORDING.joinedResult(read) {
			case Failure(message): EmbeddedIssueIdSearchFailure(message);
			case Success(ids): EmbeddedIssueIds(ids);
		};
	}

	/** Every failure of the query or its rows; the session joins each failed release step after it. */
	static function readIds(context:Context, transaction:Tx, query:String):StoreResult<Array<String>> {
		final pattern = "%" + query.toLowerCase() + "%";
		final queried = transaction.queryContext(context, READ_IDS, pattern, pattern);
		if (queried.value2 != null)
			return Failure('search embedded issue IDs: ${queried.value2.toString()}');

		final rows = queried.value1;
		final ids = new Array<String>();
		var failure = "";
		while (failure == "" && rows.next()) {
			final id = new NullString();
			final scanError = rows.scan(id);
			if (scanError != null)
				failure = 'scan embedded issue ID: ${scanError.toString()}';
			else if (!id.valid)
				failure = "scan embedded issue ID: id is null";
			else
				ids.push(id.string);
		}
		final rowError = rows.err();
		final closeRowsError = rows.close();
		if (failure != "")
			return Failure(failure);
		if (rowError != null)
			return Failure('finish embedded issue-ID search: ${rowError.toString()}');
		if (closeRowsError != null)
			return Failure('close embedded issue-ID search: ${closeRowsError.toString()}');
		return Success(ids);
	}
}
