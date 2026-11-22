package beadshx.store;

import beadshx.relation.RelatedIssue;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelationRead.finishRelationRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlRelationReader.readSqlRelations;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** Own one read transaction; all relation semantics are authored Haxe over independent APIs. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedRelationReader {
	public static function read(beadsDir:String, databaseName:String, plan:RelationReadPlan):StoreResult<Array<RelatedIssue>> {
		final outcome = EmbeddedReadWording.forNoun("relation", false)
			.cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readSqlRelations(context, transaction, plan)));
		return switch outcome {
			case Failure(message): Failure(message);
			case Success(rows):
				final neighbors = new Array<RelatedIssue>();
				for (row in rows)
					neighbors.push(relatedIssueFromSql(row.fields, row.labels, row.dependencyType));
				Success(finishRelationRead(plan, neighbors));
		};
	}
}
