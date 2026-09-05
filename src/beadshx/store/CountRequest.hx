package beadshx.store;

/** Typed predicate for a cardinality query; it intentionally has no paging. */
typedef CountRequest = {
	final status:String;
	final issueType:String;
	final assignee:String;
	final priority:OptionalInt;
	final priorityMin:OptionalInt;
	final priorityMax:OptionalInt;
	final labels:Array<String>;
	final labelsAny:Array<String>;
	final titleSearch:String;
	final idFilter:String;
	final titleContains:String;
	final descriptionContains:String;
	final notesContains:String;
	final timeFilters:Array<IssueListTimeFilter>;
	final emptyDescription:Bool;
	final noAssignee:Bool;
	final noLabels:Bool;
	final includeInfra:Bool;
}
