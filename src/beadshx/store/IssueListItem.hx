package beadshx.store;

/** One typed issue row returned by the read-only list capability. */
typedef IssueListItem = {
	> IssueRecord,
	final longFields:IssueLongFields;
	final sender:String;
	final labels:Array<String>;
	final dependencies:Array<IssueListDependency>;
	final dependencyCount:Int;
	final dependentCount:Int;
	final commentCount:Int;
	final parent:String;
	final blockedBy:Array<String>;
	final blocks:Array<String>;
	final blockingParent:String;
}
