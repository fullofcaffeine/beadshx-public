package beadshx.cli;

/**
	An argument check that upstream runs in the command body, after its root
	pre-run loaded metadata.json, printed its warnings and opened the store.
	Cobra's own checks (unknown flags, flag values that do not parse, argument
	counts) fail before the pre-run, so the parser still reports those at once.
	The parser keeps the first failed body check in upstream's order, and the
	command reports it where upstream gathers its input.
**/
enum DeferredCheck {
	ChecksPassed;

	/** Upstream HandleError: `Error: <message>` on stderr, also under --json. */
	PlainCheckFailure(message:String);

	/** Upstream HandleErrorRespectJSON: a JSON error object on stdout under --json. */
	OutputCheckFailure(message:String);

	/** A complete stderr text with its own exit code, such as the --skip-labels conflict. */
	ExactCheckFailure(message:String, exitCode:Int);
}
