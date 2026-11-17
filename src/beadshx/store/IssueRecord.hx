package beadshx.store;

/** Shared typed fields serialized by top-level and dependency issue records. */
typedef IssueRecord = {
	final id:String;
	final title:String;
	final description:String;
	final design:String;
	final acceptanceCriteria:String;
	final notes:String;
	final specId:String;
	final status:String;
	final priority:JsonInteger;
	final issueType:String;
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
	final dueAt:String;
	final deferUntil:String;

	/** NULL omits the wire field; an empty string remains present. */
	final externalRef:Null<String>;

	final sourceSystem:String;
	final metadata:StoredMetadata;
	final wispType:String;
	final moleculeType:String;
}
