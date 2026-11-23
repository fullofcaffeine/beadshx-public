package beadshx.store;

import beadshx.nativeextern.bytes.Buffer;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.encoding.json.JsonPkg;
import beadshx.store.SqlExportReader.ExportComment;
import beadshx.store.SqlExportReader.ExportDependency;
import beadshx.store.SqlExportReader.ExportIssue;
import haxe.Json;

/**
	The JSON line that upstream `bd export` writes for one issue.

	Why: the snapshot body must be byte-equal to upstream v1.2.1's export line.
	What: upstream `json.Marshal(exportIssueRecord)` (cmd/bd/export.go):
	`_type`, the `types.Issue` fields in struct order with their `omitempty`
	rules, `dependency_count`, `dependent_count`, `comment_count`, and
	`wisp_plane` when true. `sanitizeZeroTime` turns a zero `created_at` or
	`updated_at` into the Unix epoch. Fields that the export read never fills
	(`is_blocked`, `bonded_from`, `source_formula`, `source_location`,
	`parent`) are never written.
	How: Go's encoder writes each string without HTML escaping, and one
	`json.HTMLEscape` of the whole line then escapes `<`, `>` and `&` as
	`json.Marshal` does. Metadata is a `json.RawMessage`, which Go compacts;
	metadata that Go cannot compact fails as `json.Marshal` fails.
**/
@:goNative
final class ExportIssueLine {
	/** `sanitizeZeroTime`'s replacement for a zero timestamp: `time.Unix(0, 0).UTC()`. */
	static inline final UNIX_EPOCH = "1970-01-01T00:00:00Z";

	/** `json.Marshal` of Go's zero `time.Time`. */
	static inline final GO_ZERO_TIME = "0001-01-01T00:00:00Z";

	public static function render(issue:ExportIssue):StoreResult<String> {
		final row = issue.fields;
		final fields = ['"_type":"issue"', field("id", row.id), field("title", row.title)];
		optional(fields, "description", row.description);
		optional(fields, "design", row.design);
		optional(fields, "acceptance_criteria", row.acceptanceCriteria);
		optional(fields, "notes", row.notes);
		optional(fields, "spec_id", row.specId);
		optional(fields, "status", row.status);
		fields.push('"priority":${row.priority.wireValue()}');
		optional(fields, "issue_type", row.issueType);
		optional(fields, "assignee", row.assignee);
		optional(fields, "owner", row.owner);
		switch row.estimatedMinutes {
			case IntegerAbsent:
			case IntegerPresent(value):
				fields.push('"estimated_minutes":${value.wireValue()}');
		}
		fields.push(field("created_at", sanitizedTime(row.createdAt)));
		optional(fields, "created_by", row.createdBy);
		fields.push(field("updated_at", sanitizedTime(row.updatedAt)));
		optional(fields, "started_at", row.startedAt);
		optional(fields, "closed_at", row.closedAt);
		optional(fields, "close_reason", row.closeReason);
		optional(fields, "closed_by_session", row.closedBySession);
		optional(fields, "lease_expires_at", row.leaseExpiresAt);
		optional(fields, "heartbeat_at", row.heartbeatAt);
		optional(fields, "lease_granted_node", row.leaseGrantedNode);
		optional(fields, "due_at", row.dueAt);
		optional(fields, "defer_until", row.deferUntil);
		if (row.externalRef != null)
			fields.push(field("external_ref", row.externalRef));
		optional(fields, "source_system", row.sourceSystem);
		if (!row.metadata.isAbsent()) {
			final compacted = new Buffer();
			final error = JsonPkg.compact(compacted, BytesPkg.newBufferString(row.metadata.wireValue()).bytes());
			if (error != null)
				return Failure('failed to marshal issue ${row.id}: json: error calling MarshalJSON for type json.RawMessage: ${error.text()}');
			fields.push('"metadata":${compacted.stringValue()}');
		}
		if (row.compactionLevel.compare(0) != 0)
			fields.push('"compaction_level":${row.compactionLevel.wireValue()}');
		optional(fields, "compacted_at", row.compactedAt);
		if (row.compactedAtCommit != null)
			fields.push(field("compacted_at_commit", row.compactedAtCommit));
		if (row.originalSize.compare(0) != 0)
			fields.push('"original_size":${row.originalSize.wireValue()}');
		if (issue.labels.length > 0)
			fields.push('"labels":${stringArray(issue.labels)}');
		if (issue.dependencies.length > 0)
			fields.push('"dependencies":[${[for (dependency in issue.dependencies) renderDependency(dependency)].join(",")}]');
		if (issue.comments.length > 0)
			fields.push('"comments":[${[for (comment in issue.comments) renderComment(comment)].join(",")}]');
		optional(fields, "sender", row.sender);
		if (row.ephemeral)
			fields.push('"ephemeral":true');
		if (row.noHistory)
			fields.push('"no_history":true');
		optional(fields, "wisp_type", row.wispType);
		optional(fields, "storage_class", row.storageClass);
		if (row.pinned)
			fields.push('"pinned":true');
		if (row.template)
			fields.push('"is_template":true');
		optional(fields, "await_type", row.awaitType);
		optional(fields, "await_id", row.awaitId);
		if (row.timeoutNanos.compare(0) != 0)
			fields.push('"timeout":${row.timeoutNanos.wireValue()}');
		if (row.waiters.length > 0)
			fields.push('"waiters":${stringArray(row.waiters)}');
		optional(fields, "mol_type", row.moleculeType);
		optional(fields, "work_type", row.workType);
		optional(fields, "event_kind", row.eventKind);
		optional(fields, "actor", row.actor);
		optional(fields, "target", row.target);
		optional(fields, "payload", row.payload);
		fields.push('"dependency_count":${issue.dependencyCount}');
		fields.push('"dependent_count":${issue.dependentCount}');
		fields.push('"comment_count":${issue.commentCount}');
		if (issue.wispPlane)
			fields.push('"wisp_plane":true');
		return Success(escapeHtml('{${fields.join(",")}}'));
	}

	/** `types.Dependency`; the export read selects no row ID, so `id` is always empty and left out. */
	static function renderDependency(dependency:ExportDependency):String {
		final fields = [
			field("issue_id", dependency.issueId),
			field("depends_on_id", dependency.dependsOnId),
			field("type", dependency.type),
			field("created_at", dependency.createdAt)
		];
		optional(fields, "created_by", dependency.createdBy);
		optional(fields, "metadata", dependency.metadata);
		optional(fields, "thread_id", dependency.threadId);
		return '{${fields.join(",")}}';
	}

	/** `types.Comment`. */
	static function renderComment(comment:ExportComment):String {
		final fields = [
			field("id", comment.id),
			field("issue_id", comment.issueId),
			field("author", comment.author),
			field("text", comment.text),
			field("created_at", comment.createdAt)
		];
		return '{${fields.join(",")}}';
	}

	/** `sanitizeZeroTime`: Go's zero time is written as the Unix epoch. */
	static inline function sanitizedTime(value:String):String {
		return value == GO_ZERO_TIME ? UNIX_EPOCH : value;
	}

	static inline function field(name:String, value:String):String {
		return '"$name":${Json.stringify(value)}';
	}

	/** An `omitempty` string field, which Go leaves out when it is empty. */
	static inline function optional(fields:Array<String>, name:String, value:String):Void {
		if (value != "")
			fields.push(field(name, value));
	}

	static function stringArray(values:Array<String>):String {
		return '[${[for (value in values) Json.stringify(value)].join(",")}]';
	}

	/** `json.HTMLEscape`, which turns `json.Encoder` output without HTML escaping into `json.Marshal` output. */
	public static function escapeHtml(line:String):String {
		final escaped = new Buffer();
		JsonPkg.htmlEscape(escaped, BytesPkg.newBufferString(line).bytes());
		return escaped.stringValue();
	}
}
