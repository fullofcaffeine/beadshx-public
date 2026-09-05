package beadshx.store;

/** Result of an exact detail lookup, separate from native/store failure. */
enum IssueDetailsLookup {
	DetailsFound(details:IssueDetails);
	DetailsMissing;
}
