package beadshx.store;

/** One full stale issue plus the native epoch value needed for age rendering. */
typedef StaleIssue = {
	> IssueRecord,
	final longFields:IssueLongFields;
	final updatedAtMillis:Float;
}
