package beadshx.store;

/** `bd history` has the same embedded-only Haxe SQL route as `bd comments`. */
final HISTORY_ROUTE_UNAVAILABLE = "history is not available yet for server-mode or proxied workspaces in this build";

/** One `dolt_history_issues` row, as upstream HistoryInTx scans it. */
typedef IssueHistoryEntry = {
	final commitHash:String;
	final committer:String;

	/** The commit date in RFC 3339 with nanoseconds, in the zone the driver scanned it in. */
	final commitDate:String;

	/** The commit date as `2006-01-02 15:04:05`, in that same zone. */
	final commitDateText:String;

	final issue:HistoryIssue;
}

/** The issue fields HistoryInTx fills; every other Issue field keeps its Go zero value. */
typedef HistoryIssue = {
	final id:String;
	final title:String;
	final description:String;
	final design:String;
	final acceptanceCriteria:String;
	final notes:String;
	final status:String;
	final priority:Int;
	final issueType:String;
	final assignee:String;
	final owner:String;
	final estimatedMinutes:OptionalIssueInteger;
	final createdAt:String;
	final createdBy:String;
	final updatedAt:String;

	/** Empty when the column is NULL. */
	final closedAt:String;

	final closeReason:String;
	final pinned:Bool;
	final moleculeType:String;
}

/** One audit event, as upstream scanEvents reads it; null keeps SQL NULL apart from empty text. */
typedef IssueEvent = {
	final id:String;
	final issueId:String;
	final eventType:String;
	final actor:String;
	final oldValue:Null<String>;
	final newValue:Null<String>;
	final comment:Null<String>;

	/** RFC 3339 with nanoseconds, in the zone the driver scanned it in. */
	final createdAt:String;

	/** `2006-01-02 15:04:05`, in that same zone. */
	final createdAtText:String;
}
