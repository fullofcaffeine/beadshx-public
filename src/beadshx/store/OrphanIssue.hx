package beadshx.store;

/** One still-active issue referenced by its newest matching commit. */
typedef OrphanIssue = {
	> OrphanCandidate,
	final latestCommit:String;
	final latestCommitMessage:String;
}
