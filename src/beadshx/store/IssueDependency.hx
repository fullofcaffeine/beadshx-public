package beadshx.store;

/** One typed show dependency row with its own labels and its relationship type. */
typedef IssueDependency = {
	> IssueRecord,
	final labels:Array<String>;
	final dependencyType:String;
}
