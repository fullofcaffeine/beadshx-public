package beadshx.store;

/** Result of an exact issue lookup, separate from native/store failure. */
enum IssueLookup {
	IssueFound(summary:IssueSummary);
	IssueMissing;
}
