package beadshx.nativeextern.term;

/** The exact `golang.org/x/term` size query that upstream's Markdown wrap width makes on stdout. */
@:go.import("golang.org/x/term")
@:go.package("term")
@:goNative
extern class TermPkg {
	/** The column and row count of the terminal on descriptor `fd`, or an error when it is no terminal. */
	@:go.tupleReturn
	@:go.name("GetSize") public static function getSize(fd:Int):SizeResult;
}
