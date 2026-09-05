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
	final priority:Int;
	final issueType:String;
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
	final dueAt:String;
	final deferUntil:String;
	final externalRef:String;
	final sourceSystem:String;
	final metadata:JsonValue;
	final wispType:String;
	final moleculeType:String;
}
