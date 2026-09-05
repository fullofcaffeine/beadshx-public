package beadshx.store;

/** Storage fetch shape already chosen by Haxe query policy. */
enum QueryFetch {
	CompleteCandidates;
	OrderedPage(limit:Int, offset:Int, sortBy:String, reverse:Bool);
}

/** Mechanical query filter facts that the native storage layer can execute. */
typedef QueryStorageFilter = {
	final status:String;
	final excludeStatuses:Array<String>;
	final priority:OptionalInt;
	final priorityMin:OptionalInt;
	final priorityMax:OptionalInt;
	final issueType:String;
	final excludeTypes:Array<String>;
	final assignee:String;
	final noAssignee:Bool;
	final labels:Array<String>;
	final labelsAny:Array<String>;
	final noLabels:Bool;
	final titleContains:String;
	final descriptionContains:String;
	final notesContains:String;
	final emptyDescription:Bool;
	final createdAfter:OptionalQueryInstant;
	final createdBefore:OptionalQueryInstant;
	final updatedAfter:OptionalQueryInstant;
	final updatedBefore:OptionalQueryInstant;
	final startedAfter:OptionalQueryInstant;
	final startedBefore:OptionalQueryInstant;
	final closedAfter:OptionalQueryInstant;
	final closedBefore:OptionalQueryInstant;
	final ids:Array<String>;
	final idPrefix:String;
	final specPrefix:String;
	final parentId:String;
	final pinned:QueryOptionalBool;
	final ephemeral:QueryOptionalBool;
	final template:QueryOptionalBool;
	final moleculeType:String;
	final metadataFields:Array<IssueListMetadataFilter>;
	final hasMetadataKey:String;
}

/** One closed native query-row request; no expression or AST crosses here. */
typedef QueryStorageRequest = {
	final filter:QueryStorageFilter;
	final fetch:QueryFetch;
}

/** Copied native rows plus explicit completeness and continuation evidence. */
typedef QueryRowPage = {
	final rows:Array<IssueQueryRow>;
	final sourceHasMore:Bool;
	final complete:Bool;
}
