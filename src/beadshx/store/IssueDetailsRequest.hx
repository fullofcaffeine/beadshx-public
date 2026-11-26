package beadshx.store;

/** Named options for the show detail reader contract. */
typedef IssueDetailsRequest = {
	final includeDependents:Bool;
	final includeComments:Bool;
	final briefDependencies:Bool;

	/**
		Upstream show's text views read the dependents and the comment bodies
		with store calls of their own and ignore a failure (cmd/bd/show.go:200-235,
		show_display.go:117-141, show_thread.go:136-162); IssueReader.Get, behind
		`show --json`, stops on it. When true, a failed read leaves no dependents
		or no comments.
	**/
	final ?bestEffortRelations:Bool;
}
