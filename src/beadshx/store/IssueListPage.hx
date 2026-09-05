package beadshx.store;

/** One ordered list page plus an explicit truncation signal. */
typedef IssueListPage = {
	final items:Array<IssueListItem>;
	final hasMore:Bool;
	final formatted:String;
}
