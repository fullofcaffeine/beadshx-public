package beadshx.store;

/** One ready page plus the information needed by both output contracts. */
typedef ReadyResult = {
	final page:IssueListPage;
	final truncated:Bool;
	final total:ReadyTotal;
	final hasOpenIssues:Bool;

	/**
		Each ready issue's parent epic title, keyed by the issue ID, as upstream's
		human view reads them (buildParentEpicMap); null when the read that
		answered did not read them, so the view looks the parents up itself.
	**/
	final ?parentEpicTitles:Map<String, String>;
}
