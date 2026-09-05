package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.NullTime;
import beadshx.nativeextern.database.sql.Rows;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.Connector;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** Result of the relation-free Haxe-owned issue-detail tracer. */
enum EmbeddedScalarIssueDetailsResult {
	EmbeddedScalarDetailsFound(details:IssueDetails);
	EmbeddedScalarDetailsMissing;
	EmbeddedScalarDetailsRequireRelations;
	EmbeddedScalarDetailsFailure(message:String);
}

private typedef ScalarIssueFields = {
	final id:String;
	final title:String;
	final description:String;
	final design:String;
	final acceptanceCriteria:String;
	final notes:String;
	final specId:String;
	final status:String;
	final priority:Int;
	final issueType:String;
	final isBlocked:Bool;
	final assignee:String;
	final owner:String;
	final estimatedMinutes:OptionalInt;
	final createdAt:String;
	final createdBy:String;
	final updatedAt:String;
	final startedAt:String;
	final closedAt:String;
	final closeReason:String;
	final closedBySession:String;
	final leaseExpiresAt:String;
	final heartbeatAt:String;
	final leaseGrantedNode:String;
	final dueAt:String;
	final deferUntil:String;
	final externalRef:String;
	final sourceSystem:String;
	final metadata:JsonValue;
	final wispType:String;
	final moleculeType:String;
	final compactionLevel:Int;
	final compactedAt:String;
	final compactedAtCommit:String;
	final originalSize:Int;
	final sender:String;
	final ephemeral:Bool;
	final noHistory:Bool;
	final storageClass:String;
	final pinned:Bool;
	final template:Bool;
	final awaitType:String;
	final awaitId:String;
	final timeout:String;
	final timeoutNanos:JsonInteger;
	final waiters:Array<String>;
	final workType:String;
	final eventKind:String;
	final actor:String;
	final target:String;
	final payload:String;
	final revision:JsonInteger;
}

/**
	Hydrates one relation-free issue entirely in authored Haxe.

	The reader owns one connector and rollback-only transaction. It returns a
	distinct relation result when the issue has edges or comments, so callers can
	retain the transitional native path without silently returning partial data.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedScalarIssueDetailsReader {
	static inline final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";
	static final ISSUE_COLUMNS = "id, title, description, design, acceptance_criteria, notes, COALESCE(spec_id, ''), status, "
		+ "CAST(priority AS CHAR), issue_type, CAST(is_blocked AS CHAR), COALESCE(assignee, ''), COALESCE(owner, ''), "
		+ "COALESCE(CAST(estimated_minutes AS CHAR), ''), created_at, COALESCE(created_by, ''), updated_at, started_at, closed_at, "
		+ "COALESCE(close_reason, ''), COALESCE(closed_by_session, ''), leases.lease_expires_at, leases.heartbeat_at, "
		+ "COALESCE(leases.granted_node, ''), due_at, defer_until, COALESCE(external_ref, ''), COALESCE(source_system, ''), "
		+ "COALESCE(CAST(metadata AS CHAR), ''), COALESCE(wisp_type, ''), COALESCE(mol_type, ''), "
		+ "COALESCE(CAST(compaction_level AS CHAR), '0'), compacted_at, COALESCE(compacted_at_commit, ''), "
		+ "COALESCE(CAST(original_size AS CHAR), '0'), COALESCE(sender, ''), COALESCE(CAST(ephemeral AS CHAR), '0'), "
		+ "COALESCE(CAST(no_history AS CHAR), '0'), COALESCE(storage_class, ''), COALESCE(CAST(pinned AS CHAR), '0'), "
		+ "COALESCE(CAST(is_template AS CHAR), '0'), COALESCE(await_type, ''), COALESCE(await_id, ''), "
		+ "COALESCE(CAST(timeout_ns AS CHAR), '0'), COALESCE(waiters, ''), COALESCE(work_type, ''), COALESCE(event_kind, ''), "
		+ "COALESCE(actor, ''), COALESCE(target, ''), COALESCE(payload, ''), CAST(row_lock AS CHAR)";
	static final READ_ISSUE = "SELECT " + ISSUE_COLUMNS + " FROM issues LEFT JOIN leases ON leases.issue_id = issues.id WHERE issues.id = ?";
	static final READ_WISP = "SELECT " + ISSUE_COLUMNS + " FROM wisps LEFT JOIN leases ON leases.issue_id = wisps.id WHERE wisps.id = ?";
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

	public function read(id:String):EmbeddedScalarIssueDetailsResult {
		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.commitName = "BeadsHX read-only scalar issue details";
		config.commitEmail = "beadshx-readonly@invalid";
		config.database = databaseName;
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		if (openedConnector.value2 != null)
			return EmbeddedScalarDetailsFailure('open embedded detail connector: ${openedConnector.value2.toString()}');
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final pingError = database.pingContext(context);
		if (pingError != null)
			return failAfterDatabase('ping embedded detail database: ${pingError.toString()}', database, connector);
		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null)
			return failAfterDatabase('begin embedded detail transaction: ${openedTransaction.value2.toString()}', database, connector);
		final transaction = openedTransaction.value1;

		var fields:Null<ScalarIssueFields> = null;
		var isWisp = false;
		switch readFields(context, transaction, READ_ISSUE, id) {
			case Failure(message):
				return failAfterTransaction(message, transaction, database, connector);
			case Success(value):
				fields = value;
		}
		if (fields == null) {
			isWisp = true;
			switch readFields(context, transaction, READ_WISP, id) {
				case Failure(message):
					return failAfterTransaction(message, transaction, database, connector);
				case Success(value):
					fields = value;
			}
		}
		if (fields == null)
			return finish(EmbeddedScalarDetailsMissing, transaction, database, connector);
		final issue = fields;

		final counts = readRelationCounts(context, transaction, id, isWisp);
		switch counts {
			case Failure(message):
				return failAfterTransaction(message, transaction, database, connector);
			case Success(hasRelations):
				if (hasRelations)
					return finish(EmbeddedScalarDetailsRequireRelations, transaction, database, connector);
		}
		final labels = readLabels(context, transaction, id, isWisp);
		return switch labels {
			case Failure(message): failAfterTransaction(message, transaction, database, connector);
			case Success(values):
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
				finish(EmbeddedScalarDetailsFound({
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
					comments: [],
					parent: "",
					dependentCount: 0,
					dependencyCount: 0,
					commentCount: 0,
					commentsOmitted: false,
					epicProgress: NoEpicProgress,
					revision: issue.revision,
					longFields: longFields
				}), transaction, database, connector);
		};
	}

	static function readFields(context:Context, transaction:Tx, query:String, id:String):StoreResult<Null<ScalarIssueFields>> {
		final queried = transaction.queryContext(context, query, id);
		if (queried.value2 != null)
			return Failure('read scalar issue "$id": ${queried.value2.toString()}');
		final rows = queried.value1;
		if (!rows.next()) {
			final rowError = rows.err();
			final closeError = rows.close();
			if (rowError != null)
				return Failure('finish scalar issue "$id": ${rowError.toString()}');
			if (closeError != null)
				return Failure('close scalar issue "$id": ${closeError.toString()}');
			return Success(null);
		}
		final text = [for (_ in 0...42) new NullString()];
		final createdAt = new NullTime();
		final updatedAt = new NullTime();
		final startedAt = new NullTime();
		final closedAt = new NullTime();
		final leaseExpiresAt = new NullTime();
		final heartbeatAt = new NullTime();
		final dueAt = new NullTime();
		final deferUntil = new NullTime();
		final compactedAt = new NullTime();
		final scanError = rows.scan(text[0], text[1], text[2], text[3], text[4], text[5], text[6], text[7], text[8], text[9], text[10], text[11], text[12],
			text[13], createdAt, text[14], updatedAt, startedAt, closedAt, text[15], text[16], leaseExpiresAt, heartbeatAt, text[17], dueAt, deferUntil,
			text[18], text[19], text[20], text[21], text[22], text[23], compactedAt, text[24], text[25], text[26], text[27], text[28], text[29], text[30],
			text[31], text[32], text[33], text[34], text[35], text[36], text[37], text[38], text[39], text[40], text[41]);
		if (scanError != null) {
			rows.close();
			return Failure('scan scalar issue "$id": ${scanError.toString()}');
		}
		final rowError = rows.err();
		final closeError = rows.close();
		if (rowError != null)
			return Failure('finish scalar issue "$id": ${rowError.toString()}');
		if (closeError != null)
			return Failure('close scalar issue "$id": ${closeError.toString()}');

		final priority = parseIntField(text[8], "priority", id);
		final compactionLevel = parseIntField(text[23], "compaction_level", id);
		final originalSize = parseIntField(text[25], "original_size", id);
		var priorityValue = 0;
		var compactionValue = 0;
		var originalSizeValue = 0;
		switch priority {
			case Failure(message):
				return Failure(message);
			case Success(value):
				priorityValue = value;
		}
		switch compactionLevel {
			case Failure(message):
				return Failure(message);
			case Success(value):
				compactionValue = value;
		}
		switch originalSize {
			case Failure(message):
				return Failure(message);
			case Success(value):
				originalSizeValue = value;
		}
		var estimated:OptionalInt = OptionalInt.IntAbsent;
		if (value(text[13]) != "") {
			final parsedEstimated = Std.parseInt(value(text[13]));
			if (parsedEstimated == null)
				return Failure('scalar issue "$id" has invalid estimated_minutes');
			estimated = OptionalInt.IntPresent(parsedEstimated);
		}
		var metadata:StoreResult<JsonValue> = Success(JsonValue.fromValidatedNative(""));
		if (value(text[20]) != "")
			metadata = JsonValue.parse(value(text[20]), 'scalar issue "$id" metadata');
		final waiters = JsonValue.parseStringArray(value(text[35]), 'scalar issue "$id" waiters');
		final timeoutNanos = JsonInteger.parse(value(text[34]));
		final revision = JsonInteger.parse(value(text[41]));
		var metadataValue:Null<JsonValue> = null;
		var waiterValues:Array<String> = [];
		var timeoutValue:Null<JsonInteger> = null;
		var revisionValue:Null<JsonInteger> = null;
		switch metadata {
			case Failure(message):
				return Failure(message);
			case Success(parsed):
				metadataValue = parsed;
		}
		switch waiters {
			case Failure(message):
				return Failure(message);
			case Success(parsed):
				waiterValues = parsed;
		}
		switch timeoutNanos {
			case Failure(message):
				return Failure(message);
			case Success(parsed):
				timeoutValue = parsed;
		}
		switch revision {
			case Failure(message):
				return Failure(message);
			case Success(parsed):
				revisionValue = parsed;
		}
		if (metadataValue == null || timeoutValue == null || revisionValue == null)
			return Failure('scalar issue "$id" lost a validated field');
		final timeoutText = durationText(value(text[34]), id);
		return switch timeoutText {
			case Failure(message): Failure(message);
			case Success(timeout): Success({
					id: value(text[0]),
					title: value(text[1]),
					description: value(text[2]),
					design: value(text[3]),
					acceptanceCriteria: value(text[4]),
					notes: value(text[5]),
					specId: value(text[6]),
					status: value(text[7]),
					priority: priorityValue,
					issueType: value(text[9]),
					isBlocked: boolValue(text[10]),
					assignee: value(text[11]),
					owner: value(text[12]),
					estimatedMinutes: estimated,
					createdAt: timeValue(createdAt),
					createdBy: value(text[14]),
					updatedAt: timeValue(updatedAt),
					startedAt: timeValue(startedAt),
					closedAt: timeValue(closedAt),
					closeReason: value(text[15]),
					closedBySession: value(text[16]),
					leaseExpiresAt: timeValue(leaseExpiresAt),
					heartbeatAt: timeValue(heartbeatAt),
					leaseGrantedNode: value(text[17]),
					dueAt: timeValue(dueAt),
					deferUntil: timeValue(deferUntil),
					externalRef: value(text[18]),
					sourceSystem: value(text[19]),
					metadata: metadataValue,
					wispType: value(text[21]),
					moleculeType: value(text[22]),
					compactionLevel: compactionValue,
					compactedAt: timeValue(compactedAt),
					compactedAtCommit: value(text[24]),
					originalSize: originalSizeValue,
					sender: value(text[26]),
					ephemeral: boolValue(text[27]),
					noHistory: boolValue(text[28]),
					storageClass: value(text[29]),
					pinned: boolValue(text[30]),
					template: boolValue(text[31]),
					awaitType: value(text[32]),
					awaitId: value(text[33]),
					timeout: timeout,
					timeoutNanos: timeoutValue,
					waiters: waiterValues,
					workType: value(text[36]),
					eventKind: value(text[37]),
					actor: value(text[38]),
					target: value(text[39]),
					payload: value(text[40]),
					revision: revisionValue
				});
		};
	}

	static function readRelationCounts(context:Context, transaction:Tx, id:String, isWisp:Bool):StoreResult<Bool> {
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
		final commentsTable = isWisp ? "wisp_comments" : "comments";
		final comments = transaction.queryContext(context, 'SELECT CAST(COUNT(*) AS CHAR) FROM $commentsTable WHERE issue_id = ?', id);
		if (comments.value2 != null)
			return Failure('read scalar issue comment count: ${comments.value2.toString()}');
		final commentRows = comments.value1;
		if (commentRows.next()) {
			final count = new NullString();
			final scanError = commentRows.scan(count);
			if (scanError != null) {
				commentRows.close();
				return Failure('scan scalar issue comment count: ${scanError.toString()}');
			}
			final parsedCount = parseRelationCount(count, "comments", id);
			switch parsedCount {
				case Failure(message):
					commentRows.close();
					return Failure(message);
				case Success(value):
					if (value != 0)
						hasRelations = true;
			}
		}
		final commentError = commentRows.err();
		final closeCommentsError = commentRows.close();
		if (commentError != null)
			return Failure('finish scalar issue comment count: ${commentError.toString()}');
		if (closeCommentsError != null)
			return Failure('close scalar issue comment count: ${closeCommentsError.toString()}');
		return Success(hasRelations);
	}

	static function readLabels(context:Context, transaction:Tx, id:String, isWisp:Bool):StoreResult<Array<String>> {
		final table = isWisp ? "wisp_labels" : "labels";
		final queried = transaction.queryContext(context, 'SELECT label FROM $table WHERE issue_id = ? ORDER BY label', id);
		if (queried.value2 != null)
			return Failure('read scalar issue labels: ${queried.value2.toString()}');
		final rows = queried.value1;
		final labels = new Array<String>();
		while (rows.next()) {
			final label = new NullString();
			final scanError = rows.scan(label);
			if (scanError != null) {
				rows.close();
				return Failure('scan scalar issue label: ${scanError.toString()}');
			}
			if (label.valid)
				labels.push(label.string);
		}
		final rowError = rows.err();
		final closeError = rows.close();
		if (rowError != null)
			return Failure('finish scalar issue labels: ${rowError.toString()}');
		if (closeError != null)
			return Failure('close scalar issue labels: ${closeError.toString()}');
		return Success(labels);
	}

	static function durationText(nanos:String, id:String):StoreResult<String> {
		if (nanos == "0")
			return Success("");
		final parsed = TimePkg.parseDuration(nanos + "ns");
		return parsed.value2 == null ? Success(parsed.value1.toString()) : Failure('scalar issue "$id" has invalid timeout_ns: ${parsed.value2.toString()}');
	}

	static function parseIntField(field:NullString, name:String, id:String):StoreResult<Int> {
		return switch Std.parseInt(value(field)) {
			case null: Failure('scalar issue "$id" has invalid $name');
			case parsed: Success(parsed);
		};
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

	static inline function boolValue(field:NullString):Bool
		return value(field) == "1";

	static inline function timeValue(field:NullTime):String
		return field.valid ? field.time.format(GO_RFC3339_NANO) : "";

	static function finish(result:EmbeddedScalarIssueDetailsResult, transaction:Tx, database:DB, connector:Connector):EmbeddedScalarIssueDetailsResult {
		final rollbackError = transaction.rollback();
		if (rollbackError != null)
			return failAfterDatabase('roll back embedded detail transaction: ${rollbackError.toString()}', database, connector);
		final closeDatabaseError = database.close();
		if (closeDatabaseError != null) {
			connector.close();
			return EmbeddedScalarDetailsFailure('close embedded detail database: ${closeDatabaseError.toString()}');
		}
		final closeConnectorError = connector.close();
		return closeConnectorError == null ? result : EmbeddedScalarDetailsFailure('close embedded detail connector: ${closeConnectorError.toString()}');
	}

	static function failAfterTransaction(message:String, transaction:Tx, database:DB, connector:Connector):EmbeddedScalarIssueDetailsResult {
		transaction.rollback();
		return failAfterDatabase(message, database, connector);
	}

	static function failAfterDatabase(message:String, database:DB, connector:Connector):EmbeddedScalarIssueDetailsResult {
		database.close();
		connector.close();
		return EmbeddedScalarDetailsFailure(message);
	}
}
