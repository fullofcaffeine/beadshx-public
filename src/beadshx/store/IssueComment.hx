package beadshx.store;

/** One typed comment body returned by --include-comments. */
typedef IssueComment = {
	final id:String;
	final issueId:String;
	final author:String;
	final text:String;
	final createdAt:String;
}
