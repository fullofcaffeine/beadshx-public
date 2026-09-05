package beadshx.store;

/** One typed dependency edge embedded in an issue-list JSON row. */
typedef IssueListDependency = {
	final id:String;
	final issueId:String;
	final dependsOnId:String;
	final dependencyType:String;
	final createdAt:String;
	final createdBy:String;
	final metadata:String;
	final threadId:String;
}
