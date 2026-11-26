package beadshx.store;

import beadshx.relation.RelatedIssue;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueDetailsReader.readSqlDependencyRows;
import beadshx.store.SqlIssueDetailsReader.readSqlIssueDetails;

/**
	Reads the issue details of `bd show` and the dependents of `show --refs`
	and `--children` from the workspace's embedded database, entirely in
	authored Haxe (SqlIssueDetailsReader).

	Each read owns one rollback-only read of the shared `EmbeddedSession`. Like
	the native facade's reads, it always opens the workspace's configured
	database.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueDetailsReader {
	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, "");
	}

	public function read(id:String, request:IssueDetailsRequest):StoreResult<IssueDetailsLookup> {
		// A failed read wins over the session's release steps.
		return EmbeddedReadWording.forNoun("detail", true)
			.bodyFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> readSqlIssueDetails(context, transaction, id, request)));
	}

	/** Upstream `GetDependentsWithMetadata`: every issue that depends on `id`, with its whole record. */
	public function readDependents(id:String):StoreResult<Array<RelatedIssue>> {
		return EmbeddedReadWording.forNoun("relation", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> readSqlDependencyRows(context, transaction, id, Incoming)));
	}
}
