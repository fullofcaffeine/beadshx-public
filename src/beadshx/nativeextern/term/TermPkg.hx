package beadshx.nativeextern.term;

/** The exact `golang.org/x/term` checks that upstream's internal/ui and Markdown wrap width make on the process streams. */
@:go.import("golang.org/x/term")
@:go.package("term")
@:goNative
extern class TermPkg {
	/** Whether descriptor `fd` is a terminal. */
	@:go.name("IsTerminal") public static function isTerminal(fd:Int):Bool;

	/** The column and row count of the terminal on descriptor `fd`, or an error when it is no terminal. */
	@:go.tupleReturn
	@:go.name("GetSize") public static function getSize(fd:Int):SizeResult;
}
