package beadshx.cli;

/** A typed parse outcome keeps usage failures out of command handlers. */
enum ParseResult {
	Parsed(invocation:Invocation);
	UsageFailure(message:String);

	/** A flag error on a command group that prints its usage after the error, as cobra does without SilenceUsage. */
	GroupUsageFailure(message:String, group:Command);

	OutputFailure(mode:OutputMode, message:String);
	ExactFailure(message:String, exitCode:Int);
	UnknownCommand(name:String);
}
