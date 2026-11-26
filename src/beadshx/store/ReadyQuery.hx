package beadshx.store;

/**
	Which of upstream's two ready reads a `bd ready` view makes.

	`bd ready --json` asks GetReadyWorkWithCounts; the human view asks the bare
	GetReadyWork (cmd/bd/ready.go:181 and :220), which reads wisps with another
	query and then reads each issue's parent epic. Only an embedded workspace
	tells them apart; the native facade reads the counted query for both.
**/
enum ReadyQuery {
	/** GetReadyWorkWithCounts: each row with its counts, its parent and its dependencies. */
	ReadyWorkWithCounts;

	/** GetReadyWork: the issue records alone, then the parent epic titles (buildParentEpicMap). */
	ReadyWork;
}
