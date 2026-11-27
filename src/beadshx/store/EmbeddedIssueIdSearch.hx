package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueFilter.IssueSearchFilter;
import beadshx.store.SqlIssueListReader.IssueSearchFailure;
import beadshx.store.SqlIssueSearch.SearchedIssueIds;

/** Result of one Haxe-owned partial-ID candidate scan. */
enum EmbeddedIssueIdSearchResult {
	EmbeddedIssueIds(ids:Array<String>);
	EmbeddedIssueIdSearchFailure(message:String);
}

/**
	The candidate IDs of a partial-ID lookup: upstream ResolvePartialID's
	`SearchIssueIDs(ctx, searchPart, IssueFilter{})` (internal/utils/id_parser.go:137).

	Why: a failed search must say what upstream's says ("search issues: search
	issues: ..."), and Dolt words a failed query after its SQL.
	What: SqlIssueSearch's ID search with the search part as its query text,
	which matches the title and the ID as upstream's query does; the caller
	keeps only the IDs whose hash matches. Haxe abbreviation policy picks the
	issue.
	How: one read of the shared `EmbeddedSession`; each failed release step
	follows the read's error.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueIdSearch {
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

	static function readIds(context:Context, transaction:Tx, query:String):StoreResult<Array<String>> {
		final filter = new IssueSearchFilter();
		filter.queryText = query;
		return switch SqlIssueSearch.searchIssueIds(context, transaction, filter) {
			case IssueIdsFound(ids): Success(ids);
			case IssueIdsNotSearched(SearchFailed(message, _)): Failure(message);
			// The filter sets no row cap, so this branch only completes the switch.
			case IssueIdsNotSearched(SearchRowCap(found, _, cap)): Failure('row cap: $found over $cap');
		};
	}
}
