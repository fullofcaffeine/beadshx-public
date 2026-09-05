package beadshx.store;

/** One list time predicate carrying a validated canonical RFC3339 timestamp. */
enum IssueListTimeFilter {
	CreatedAfter(value:String);
	CreatedBefore(value:String);
	UpdatedAfter(value:String);
	UpdatedBefore(value:String);
	ClosedAfter(value:String);
	ClosedBefore(value:String);
	DeferAfter(value:String);
	DeferBefore(value:String);
	DueAfter(value:String);
	DueBefore(value:String);
}
