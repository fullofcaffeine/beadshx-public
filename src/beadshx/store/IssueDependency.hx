package beadshx.store;

/** One typed show dependency row with its relationship type. */
typedef IssueDependency = {
	> IssueRecord,
	final dependencyType:String;
}
