package beadshx.store;

/**
	One full stale issue and its labels, as upstream's stale read returns it.
	`updatedAt` gives its age.
**/
typedef StaleIssue = {
	> IssueRecord,
	final labels:Array<String>;
	final longFields:IssueLongFields;
}
