package beadshx.store;

/** One typed show dependency row with its own labels, its claim lease and its relationship type. */
typedef IssueDependency = {
	> IssueRecord,
	final labels:Array<String>;
	final lease:IssueLease;
	final dependencyType:String;
}
