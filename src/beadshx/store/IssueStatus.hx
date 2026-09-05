package beadshx.store;

/** Typed issue status, with an explicit fallback for future upstream values. */
enum IssueStatus {
	Open;
	InProgress;
	Blocked;
	Closed;
	Deferred;
	Pinned;
	OtherStatus(value:String);
}
