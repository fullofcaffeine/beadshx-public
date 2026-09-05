package beadshx.cli;

/** A typed parse outcome keeps usage failures out of command handlers. */
enum ParseResult {
	Parsed(invocation:Invocation);
	UsageFailure(message:String);
	OutputFailure(mode:OutputMode, message:String);
	ExactFailure(message:String, exitCode:Int);
	UnknownCommand(name:String);
}
