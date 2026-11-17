package beadshx.store;

import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.relation.RelatedIssue;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.relation.RelationRead.finishRelationRead;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.SqlRelationReader.readSqlRelations;

/** Own one read transaction; all relation semantics are authored Haxe over independent APIs. */
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedRelationReader {
	public static function read(beadsDir:String, databaseName:String, plan:RelationReadPlan):StoreResult<Array<RelatedIssue>> {
		final config = new Config();
		config.directory = haxe.io.Path.join([beadsDir, "embeddeddolt"]);
		config.database = resolveEmbeddedDatabaseName(beadsDir, databaseName);
		config.commitName = "BeadsHX read-only relation snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.multiStatements = true;
		final opened = DoltDriverPkg.newConnector(config);
		if (opened.value2 != null)
			return Failure('open embedded relation connector: ${opened.value2.toString()}');
		final connector = opened.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final started = database.beginTx(context, new TxOptions());
		if (started.value2 != null) {
			database.close();
			connector.close();
			return Failure('begin embedded relation transaction: ${started.value2.toString()}');
		}
		final outcome = readSqlRelations(context, started.value1, plan);
		final rollbackError = started.value1.rollback();
		final closeDatabaseError = database.close();
		final closeConnectorError = connector.close();
		if (rollbackError != null)
			return Failure('roll back embedded relation transaction: ${rollbackError.toString()}');
		if (closeDatabaseError != null)
			return Failure('close embedded relation database: ${closeDatabaseError.toString()}');
		if (closeConnectorError != null)
			return Failure('close embedded relation connector: ${closeConnectorError.toString()}');
		return switch outcome {
			case Failure(message): Failure(message);
			case Success(rows):
				final neighbors = new Array<RelatedIssue>();
				for (row in rows) {
					final extended:IssueLongFields = {
						isBlocked: row.fields.isBlocked,
						leaseExpiresAt: row.fields.leaseExpiresAt,
						heartbeatAt: row.fields.heartbeatAt,
						leaseGrantedNode: row.fields.leaseGrantedNode,
						compactionLevel: row.fields.compactionLevel,
						compactedAt: row.fields.compactedAt,
						compactedAtCommit: row.fields.compactedAtCommit,
						originalSize: row.fields.originalSize,
						sender: row.fields.sender,
						ephemeral: row.fields.ephemeral,
						noHistory: row.fields.noHistory,
						storageClass: row.fields.storageClass,
						pinned: row.fields.pinned,
						template: row.fields.template,
						bondedFrom: [],
						awaitType: row.fields.awaitType,
						awaitId: row.fields.awaitId,
						timeout: row.fields.timeout,
						timeoutNanos: row.fields.timeoutNanos,
						waiters: row.fields.waiters,
						sourceFormula: "",
						sourceLocation: "",
						workType: row.fields.workType,
						eventKind: row.fields.eventKind,
						actor: row.fields.actor,
						target: row.fields.target,
						payload: row.fields.payload
					};
					neighbors.push(relatedIssue(row.fields, row.labels, extended, row.dependencyType));
				}
				Success(finishRelationRead(plan, neighbors));
		};
	}
}
