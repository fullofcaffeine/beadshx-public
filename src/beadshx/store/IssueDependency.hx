package beadshx.store;

/**
	One typed show dependency row with its own labels, the rest of its issue row and its relationship type.

	Upstream prints each row as a whole `types.IssueWithDependencyMetadata`
	(internal/types/types.go:1130-1133), so `longFields` keeps every other issue
	field that the full read fills, its claim lease among them.
**/
typedef IssueDependency = {
	> IssueRecord,
	final labels:Array<String>;
	final longFields:IssueLongFields;
	final dependencyType:String;
}
