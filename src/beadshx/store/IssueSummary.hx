package beadshx.store;

/** Complete typed value needed to render one compact issue row. */
typedef IssueSummary = {
	final id:String;
	final title:String;
	final status:IssueStatus;
	final priority:Int;
	final issueType:IssueType;
}
