package beadshx.nativeextern.exec;

/** A standard-library `*exec.Cmd` that captures stdout and keeps stderr out of the terminal. */
@:go.import("os/exec")
@:go.package("exec")
@:go.name("Cmd")
@:goNative
extern class Cmd {
	@:go.tupleReturn
	@:go.name("Output") public function output():CmdOutputResult;
}
