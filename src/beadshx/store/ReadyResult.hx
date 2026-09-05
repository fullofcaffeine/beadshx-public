package beadshx.store;

/** One ready page plus the information needed by both output contracts. */
typedef ReadyResult = {
	final page:IssueListPage;
	final truncated:Bool;
	final total:ReadyTotal;
	final hasOpenIssues:Bool;
}
