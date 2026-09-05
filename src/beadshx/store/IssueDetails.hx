package beadshx.store;

/**
	Typed storage-neutral values for the first successful show JSON slice.

	Empty strings retain the native zero values. The renderer applies the pinned
	Beads `omitempty` rules at the public JSON boundary.
**/
typedef IssueDetails = {
	> IssueRecord,
	final labels:Array<String>;
	final dependencies:Array<IssueDependency>;
	final dependents:Array<IssueDependency>;
	final comments:Array<IssueComment>;
	final parent:String;
	final dependentCount:Int;
	final dependencyCount:Int;
	final commentCount:Int;
	final commentsOmitted:Bool;
	final epicProgress:EpicProgress;
	final revision:JsonInteger;
	final longFields:IssueLongFields;
}
