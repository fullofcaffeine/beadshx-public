package beadshx.store;

/** One blocker-aware ready-work query, separate from presentation choices. */
typedef ReadyRequest = {
	final issueType:String;
	final assignee:String;
	final unassigned:Bool;
	final labels:Array<String>;
	final labelsAny:Array<String>;
	final excludeLabels:Array<String>;
	final labelPattern:String;
	final labelRegex:String;
	final priority:OptionalInt;
	final parentId:String;
	final moleculeType:String;
	final includeDeferred:Bool;
	final includeEphemeral:Bool;
	final excludeTypes:Array<String>;
	final metadataFields:Array<IssueListMetadataFilter>;
	final hasMetadataKey:String;
	final sort:ReadySort;
	final limit:OptionalInt;
	final offset:OptionalInt;
	final brief:Bool;
	final maxRows:OptionalInt;
	final maxRowsSource:String;
}
