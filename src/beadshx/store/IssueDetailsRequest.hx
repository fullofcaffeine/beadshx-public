package beadshx.store;

/** Named options for the show detail reader contract. */
typedef IssueDetailsRequest = {
	final includeDependents:Bool;
	final includeComments:Bool;
	final briefDependencies:Bool;
}
