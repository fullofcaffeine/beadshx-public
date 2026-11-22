package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.SQL_READ_WISP;
import beadshx.store.SqlIssueRow.readSqlIssueFields;
import beadshx.store.SqlCommentReader.readSqlIssueCommentDetails;

/** Labels and iteration error travel together because the direct store preserves partial rows. */
private typedef ScalarLabels = {
	final values:Array<String>;
	final error:Null<String>;
}

/** Result of the edge-free Haxe-owned issue-detail tracer. */
enum EmbeddedScalarIssueDetailsResult {
	EmbeddedScalarDetailsFound(details:IssueDetails);
	EmbeddedScalarDetailsMissing;
	EmbeddedScalarDetailsRequireRelations;
	EmbeddedScalarDetailsFailure(message:String);
}

/**
	Hydrates one edge-free issue entirely in authored Haxe.

	The reader owns one rollback-only read of the shared `EmbeddedSession`. It returns a
	distinct relation result when the issue has edges, so callers can
	retain the transitional native path without silently returning partial data.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedScalarIssueDetailsReader {
	static final READ_RELATION_COUNTS = "SELECT 'dependencies', COUNT(*) FROM dependencies WHERE issue_id = ? "
		+ "UNION ALL SELECT 'wisp_dependencies', COUNT(*) FROM wisp_dependencies WHERE issue_id = ? "
		+ "UNION ALL SELECT 'dependents', COUNT(*) FROM dependencies WHERE COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) = ? "
		+
		"UNION ALL SELECT 'wisp_dependents', COUNT(*) FROM wisp_dependencies WHERE COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) = ?";

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, "");
	}

	public function read(id:String, request:IssueDetailsRequest):EmbeddedScalarIssueDetailsResult {
		final read = EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readOutcome(context, transaction, id, request));
		// A failed read wins over the session's release steps.
		return switch EmbeddedReadWording.forNoun("detail", true).bodyFailureFirst(read) {
			case Failure(message): EmbeddedScalarDetailsFailure(message);
			case Success(result): result;
		};
	}

	/** A failed assembly is the body failure that `bodyFailureFirst` lets win over the release steps. */
	static function readOutcome(context:Context, transaction:Tx, id:String, request:IssueDetailsRequest):StoreResult<EmbeddedScalarIssueDetailsResult> {
		return switch readFromTransaction(context, transaction, id, request) {
			case EmbeddedScalarDetailsFailure(message): Failure(message);
			case result: Success(result);
		};
	}

	/** Assemble within a caller-owned transaction; the outer reader retains cleanup precedence. */
	static function readFromTransaction(context:Context, transaction:Tx, id:String, request:IssueDetailsRequest):EmbeddedScalarIssueDetailsResult {
		var fields:Null<SqlIssueFields> = null;
		var isWisp = false;
		switch readSqlIssueFields(context, transaction, SQL_READ_ISSUE, id) {
			case Failure(message):
				return EmbeddedScalarDetailsFailure(message);
			case Success(value):
				fields = value;
		}
		if (fields == null) {
			isWisp = true;
			switch readSqlIssueFields(context, transaction, SQL_READ_WISP, id) {
				case Failure(message):
					return EmbeddedScalarDetailsFailure(message);
				case Success(value):
					fields = value;
			}
		}
		if (fields == null)
			return EmbeddedScalarDetailsMissing;
		final issue = fields;
		// GetIssueInTx fetches labels before detail assembly and treats this first error as fatal.
		final initialLabels = readLabels(context, transaction, id, isWisp);
		if (initialLabels.error != null)
			return EmbeddedScalarDetailsFailure("get issue labels: " + initialLabels.error);

		// BuildIssueDetails overwrites the first labels and deliberately ignores this error.
		final values = readLabels(context, transaction, id, SqlWispRouting.isActiveWispInTx(context, transaction, id)).values;

		final counts = readRelationCounts(context, transaction, id);
		switch counts {
			case Failure(message):
				return EmbeddedScalarDetailsFailure(message);
			case Success(hasRelations):
				if (hasRelations)
					return EmbeddedScalarDetailsRequireRelations;
		}
		return switch readSqlIssueCommentDetails(context, transaction, {
			id: id,
			includeComments: request.includeComments
		}) {
			case Failure(message): EmbeddedScalarDetailsFailure(message);
			case Success(commentDetails):
				final longFields:IssueLongFields = {
					isBlocked: issue.isBlocked,
					leaseExpiresAt: issue.leaseExpiresAt,
					heartbeatAt: issue.heartbeatAt,
					leaseGrantedNode: issue.leaseGrantedNode,
					compactionLevel: issue.compactionLevel,
					compactedAt: issue.compactedAt,
					compactedAtCommit: issue.compactedAtCommit,
					originalSize: issue.originalSize,
					sender: issue.sender,
					ephemeral: issue.ephemeral,
					noHistory: issue.noHistory,
					storageClass: issue.storageClass,
					pinned: issue.pinned,
					template: issue.template,
					bondedFrom: [],
					awaitType: issue.awaitType,
					awaitId: issue.awaitId,
					timeout: issue.timeout,
					timeoutNanos: issue.timeoutNanos,
					waiters: issue.waiters,
					sourceFormula: "",
					sourceLocation: "",
					workType: issue.workType,
					eventKind: issue.eventKind,
					actor: issue.actor,
					target: issue.target,
					payload: issue.payload
				};
				EmbeddedScalarDetailsFound({
					id: issue.id,
					title: issue.title,
					description: issue.description,
					design: issue.design,
					acceptanceCriteria: issue.acceptanceCriteria,
					notes: issue.notes,
					specId: issue.specId,
					status: issue.status,
					priority: issue.priority,
					issueType: issue.issueType,
					assignee: issue.assignee,
					owner: issue.owner,
					estimatedMinutes: issue.estimatedMinutes,
					createdAt: issue.createdAt,
					createdBy: issue.createdBy,
					updatedAt: issue.updatedAt,
					startedAt: issue.startedAt,
					closedAt: issue.closedAt,
					closeReason: issue.closeReason,
					closedBySession: issue.closedBySession,
					dueAt: issue.dueAt,
					deferUntil: issue.deferUntil,
					externalRef: issue.externalRef,
					sourceSystem: issue.sourceSystem,
					metadata: issue.metadata,
					wispType: issue.wispType,
					moleculeType: issue.moleculeType,
					labels: values,
					dependencies: [],
					dependents: [],
					comments: commentDetails.comments,
					parent: "",
					dependentCount: 0,
					dependencyCount: 0,
					commentCount: commentDetails.commentCount,
					commentsOmitted: commentDetails.commentsOmitted,
					epicProgress: NoEpicProgress,
					revision: issue.revision,
					longFields: longFields
				});
		};
	}

	static function readRelationCounts(context:Context, transaction:Tx, id:String):StoreResult<Bool> {
		final queried = transaction.queryContext(context, READ_RELATION_COUNTS, id, id, id, id);
		if (queried.value2 != null)
			return Failure('read scalar issue relation counts: ${queried.value2.toString()}');
		final rows = queried.value1;
		var hasRelations = false;
		while (rows.next()) {
			final kind = new NullString();
			final count = new NullString();
			final scanError = rows.scan(kind, count);
			if (scanError != null) {
				rows.close();
				return Failure('scan scalar issue relation counts: ${scanError.toString()}');
			}
			final parsedCount = parseRelationCount(count, value(kind), id);
			switch parsedCount {
				case Failure(message):
					rows.close();
					return Failure(message);
				case Success(value):
					if (value != 0)
						hasRelations = true;
			}
		}
		final rowError = rows.err();
		final closeError = rows.close();
		if (rowError != null)
			return Failure('finish scalar issue relation counts: ${rowError.toString()}');
		if (closeError != null)
			return Failure('close scalar issue relation counts: ${closeError.toString()}');
		return Success(hasRelations);
	}

	/** Direct GetLabelsInTx semantics: failed scan discards rows, iteration failure retains them. */
	static function readLabels(context:Context, transaction:Tx, id:String, isWisp:Bool):ScalarLabels {
		final table = isWisp ? "wisp_labels" : "labels";
		final queried = transaction.queryContext(context, 'SELECT label FROM $table WHERE issue_id = ? ORDER BY label', id);
		if (queried.value2 != null)
			return {values: [], error: 'get labels: ${queried.value2.toString()}'};
		final rows = queried.value1;
		final labels = new Array<String>();
		while (rows.next()) {
			final label = go.NativePointer.of("");
			final scanError = rows.scan(label);
			if (scanError != null) {
				rows.close();
				return {values: [], error: 'get labels: scan: ${scanError.toString()}'};
			}
			labels.push(label.get());
		}
		// Pinned function evaluates Err before its deferred Close, ignoring Close's return.
		final rowError = rows.err();
		rows.close();
		return {values: labels, error: rowError == null ? null : rowError.toString()};
	}

	static function parseRelationCount(field:NullString, kind:String, id:String):StoreResult<Int> {
		return switch Std.parseInt(value(field)) {
			case null: Failure('scalar issue "$id" has invalid $kind count');
			case parsed if (parsed < 0): Failure('scalar issue "$id" has negative $kind count');
			case parsed: Success(parsed);
		};
	}

	static inline function value(field:NullString):String
		return field.valid ? field.string : "";
}
