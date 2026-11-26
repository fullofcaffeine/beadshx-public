package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.NullInt64;
import beadshx.nativeextern.database.sql.NullTime;
import beadshx.nativeextern.database.sql.Rows;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.time.TimePkg;

/** Typed scalar row shared by detail and relation reads within their owning SQL snapshot. */
typedef SqlIssueFields = {
	final id:String;
	final contentHash:String;
	final sourceRepo:String;
	final title:String;
	final description:String;
	final design:String;
	final acceptanceCriteria:String;
	final notes:String;
	final specId:String;
	final status:String;
	final priority:JsonInteger;
	final issueType:String;
	final isBlocked:Bool;
	final assignee:String;
	final owner:String;
	final estimatedMinutes:OptionalIssueInteger;
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
	final externalRef:Null<String>;
	final sourceSystem:String;
	final metadata:StoredMetadata;
	final wispType:String;
	final moleculeType:String;
	final compactionLevel:JsonInteger;
	final compactedAt:String;
	final compactedAtCommit:Null<String>;
	final originalSize:JsonInteger;
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

/** The same SQL row scanner serves scalar detail and batched relation hydration. */
enum SqlIssueScanOrigin {
	ScalarDetail;
	RelationHydration;
}

/** Keep driver identity through Scan; each caller owns its contextual error text. */
enum SqlIssueNativeScanResult {
	SqlIssueScanned(fields:SqlIssueFields);
	SqlIssueScanFailure(error:go.NativeError);
	SqlIssueDecodeFailure(message:String);
}

/** Explicit native authority for shared database/sql decoding; callers own effects. */
@:goNative
final class SqlIssueRow {
	static final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";
	static final GO_RFC3339 = "2006-01-02T15:04:05Z07:00";
	static final GO_MYSQL_DATETIME = "2006-01-02 15:04:05";
	static final GO_ZERO_TIME = "0001-01-01T00:00:00Z";
	public static final SQL_ISSUE_COLUMNS = "id, content_hash, title, description, design, acceptance_criteria, notes, status, priority, issue_type, assignee, estimated_minutes, created_at, created_by, owner, updated_at, started_at, closed_at, external_ref, spec_id, compaction_level, compacted_at, compacted_at_commit, original_size, source_repo, close_reason, closed_by_session, sender, ephemeral, no_history, wisp_type, pinned, is_template, await_type, await_id, timeout_ns, waiters, mol_type, event_kind, actor, target, payload, due_at, defer_until, work_type, source_system, metadata, row_lock, storage_class, leases.lease_expires_at, leases.heartbeat_at, leases.granted_node";
	public static final SQL_READ_ISSUE = "SELECT " + SQL_ISSUE_COLUMNS + " FROM issues LEFT JOIN leases ON leases.issue_id = issues.id WHERE issues.id = ?";
	public static final SQL_READ_WISP = "SELECT " + SQL_ISSUE_COLUMNS + " FROM wisps LEFT JOIN leases ON leases.issue_id = wisps.id WHERE wisps.id = ?";

	/** Read one scalar issue without owning or changing the caller's transaction. */
	public static function readSqlIssueFields(context:Context, transaction:Tx, query:String, id:String):StoreResult<Null<SqlIssueFields>> {
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
		final result = scanSqlIssueFields(rows, id, ScalarDetail);
		final rowError = rows.err();
		final closeError = rows.close();
		return switch result {
			case Failure(message): Failure(message);
			case Success(fields):
				if (rowError != null) Failure('finish scalar issue "$id": ${rowError.toString()}'); else if (closeError != null)
					Failure('close scalar issue "$id": ${closeError.toString()}'); else Success(fields);
		};
	}

	/** Decode the current row; the transaction owner retains cursor lifetime. */
	public static function scanSqlIssueFields(rows:Rows, id:String, origin:SqlIssueScanOrigin):StoreResult<SqlIssueFields> {
		return switch scanSqlIssueFieldsNative(rows, id) {
			case SqlIssueScanned(fields): Success(fields);
			case SqlIssueScanFailure(error):
				final cause = error.text();
				Failure(switch origin {
					case ScalarDetail: 'scan scalar issue "$id": $cause';
					case RelationHydration: cause;
				});
			case SqlIssueDecodeFailure(message): Failure(message);
		};
	}

	/** Decode one native SQL row without flattening a possible driver error. */
	public static function scanSqlIssueFieldsNative(rows:Rows, id:String):SqlIssueNativeScanResult {
		return scanSqlIssueFieldsWithExtra(rows, id, []);
	}

	/**
		Decode one native SQL row whose issue columns come first, as
		`scanSqlIssueFieldsNative` does, and scan the columns after them into
		`extra`, in order, in the same `Scan` call (upstream's compositeReadyRow).
	**/
	public static function scanSqlIssueFieldsWithExtra(rows:Rows, id:String, extra:Array<Dynamic>):SqlIssueNativeScanResult {
		final rowId = go.NativePointer.of("");
		final contentHash = new NullString();
		final title = go.NativePointer.of("");
		final description = go.NativePointer.of("");
		final design = go.NativePointer.of("");
		final acceptanceCriteria = go.NativePointer.of("");
		final notes = go.NativePointer.of("");
		final status = go.NativePointer.of("");
		final priority = go.NativePointer.of(0);
		final issueType = go.NativePointer.of("");
		final assignee = new NullString();
		final estimatedMinutes = new NullInt64();
		final createdAt = new NullString();
		final createdBy = new NullString();
		final owner = new NullString();
		final updatedAt = new NullString();
		final startedAt = new NullTime();
		final closedAt = new NullTime();
		final externalRef = new NullString();
		final specId = new NullString();
		final compactionLevel = go.NativePointer.of(0);
		final compactedAt = new NullTime();
		final compactedAtCommit = new NullString();
		final originalSize = new NullInt64();
		final sourceRepo = new NullString();
		final closeReason = new NullString();
		final closedBySession = new NullString();
		final sender = new NullString();
		final ephemeral = new NullInt64();
		final noHistory = new NullInt64();
		final wispType = new NullString();
		final pinned = new NullInt64();
		final template = new NullInt64();
		final awaitType = new NullString();
		final awaitId = new NullString();
		final timeoutNanos = new NullInt64();
		final waiters = new NullString();
		final moleculeType = new NullString();
		final eventKind = new NullString();
		final actor = new NullString();
		final target = new NullString();
		final payload = new NullString();
		final dueAt = new NullTime();
		final deferUntil = new NullTime();
		final workType = new NullString();
		final sourceSystem = new NullString();
		final metadata = new NullString();
		final rowLock = new NullInt64();
		final storageClass = new NullString();
		final leaseExpiresAt = new NullTime();
		final heartbeatAt = new NullTime();
		final leaseGrantedNode = new NullString();
		final destinations:Array<Dynamic> = [
			rowId,
			contentHash,
			title,
			description,
			design,
			acceptanceCriteria,
			notes,
			status,
			priority,
			issueType,
			assignee,
			estimatedMinutes,
			createdAt,
			createdBy,
			owner,
			updatedAt,
			startedAt,
			closedAt,
			externalRef,
			specId,
			compactionLevel,
			compactedAt,
			compactedAtCommit,
			originalSize,
			sourceRepo,
			closeReason,
			closedBySession,
			sender,
			ephemeral,
			noHistory,
			wispType,
			pinned,
			template,
			awaitType,
			awaitId,
			timeoutNanos,
			waiters,
			moleculeType,
			eventKind,
			actor,
			target,
			payload,
			dueAt,
			deferUntil,
			workType,
			sourceSystem,
			metadata,
			rowLock,
			storageClass,
			leaseExpiresAt,
			heartbeatAt,
			leaseGrantedNode
		];
		for (destination in extra)
			destinations.push(destination);
		final scanError = rows.scanNative(...destinations);
		if (scanError != null)
			return SqlIssueScanFailure(scanError);
		final timeoutValue:JsonInteger = timeoutNanos.valid ? NativeIntegers.fromInt64(timeoutNanos.value) : 0;
		final revisionValue:JsonInteger = rowLock.valid ? NativeIntegers.fromInt64(rowLock.value) : 0;
		return switch durationText(timeoutValue.wireValue(), id) {
			case Failure(message): SqlIssueDecodeFailure(message);
			case Success(timeout): SqlIssueScanned({
					id: rowId.get(),
					contentHash: value(contentHash),
					sourceRepo: value(sourceRepo),
					title: title.get(),
					description: description.get(),
					design: design.get(),
					acceptanceCriteria: acceptanceCriteria.get(),
					notes: notes.get(),
					specId: value(specId),
					status: status.get(),
					priority: NativeIntegers.fromInt(priority.get()),
					issueType: issueType.get(),
					isBlocked: false,
					assignee: value(assignee),
					owner: value(owner),
					estimatedMinutes: estimatedMinutes.valid ? OptionalIssueInteger.IntegerPresent(NativeIntegers.fromInt64(estimatedMinutes.value)) : OptionalIssueInteger.IntegerAbsent,
					createdAt: parseIssueTime(createdAt),
					createdBy: value(createdBy),
					updatedAt: parseIssueTime(updatedAt),
					startedAt: timeValue(startedAt),
					closedAt: timeValue(closedAt),
					closeReason: value(closeReason),
					closedBySession: value(closedBySession),
					leaseExpiresAt: timeValue(leaseExpiresAt),
					heartbeatAt: timeValue(heartbeatAt),
					leaseGrantedNode: value(leaseGrantedNode),
					dueAt: timeValue(dueAt),
					deferUntil: timeValue(deferUntil),
					externalRef: externalRef.valid ? externalRef.string : null,
					sourceSystem: value(sourceSystem),
					metadata: StoredMetadata.fromSql(value(metadata)),
					wispType: value(wispType),
					moleculeType: value(moleculeType),
					compactionLevel: NativeIntegers.fromInt(compactionLevel.get()),
					compactedAt: timeValue(compactedAt),
					compactedAtCommit: compactedAtCommit.valid ? compactedAtCommit.string : null,
					originalSize: originalSize.valid ? NativeIntegers.fromInt64(originalSize.value) : 0,
					sender: value(sender),
					ephemeral: nativeFlag(ephemeral),
					noHistory: nativeFlag(noHistory),
					storageClass: value(storageClass),
					pinned: nativeFlag(pinned),
					template: nativeFlag(template),
					awaitType: value(awaitType),
					awaitId: value(awaitId),
					timeout: timeout,
					timeoutNanos: timeoutValue,
					waiters: parseIssueWaiters(waiters),
					workType: value(workType),
					eventKind: value(eventKind),
					actor: value(actor),
					target: value(target),
					payload: value(payload),
					revision: revisionValue
				});
		};
	}

	static function durationText(nanos:String, id:String):StoreResult<String> {
		if (nanos == "0")
			return Success("");
		final parsed = TimePkg.parseDuration(nanos + "ns");
		return parsed.value2 == null ? Success(parsed.value1.toString()) : Failure('scalar issue "$id" has invalid timeout_ns: ${parsed.value2.toString()}');
	}

	public static inline function value(field:NullString):String
		return field.valid ? field.string : "";

	/** Native Scan accepts signed64 integers; every nonzero value is true. */
	public static inline function nativeFlag(field:NullInt64):Bool
		return field.valid && NativeIntegers.fromInt64(field.value).wireValue() != "0";

	public static inline function timeValue(field:NullTime):String
		return field.valid ? field.time.format(GO_RFC3339_NANO) : "";

	/** The pinned scanner reads TEXT dates and treats invalid input as Go's zero time. */
	public static function parseIssueTime(field:NullString):String {
		if (!field.valid || field.string == "")
			return GO_ZERO_TIME;
		for (layout in [GO_RFC3339_NANO, GO_RFC3339, GO_MYSQL_DATETIME]) {
			final parsed = TimePkg.parse(layout, field.string);
			if (parsed.value2 == null)
				return parsed.value1.format(GO_RFC3339_NANO);
		}
		return GO_ZERO_TIME;
	}

	/** The pinned issue scanner treats malformed waiter JSON as no waiters. */
	static function parseIssueWaiters(field:NullString):Array<String> {
		return switch JsonValue.parseStringArrayNullAsEmpty(value(field), "issue waiters") {
			case Success(values): values;
			case Failure(_): [];
		};
	}
}
