package beadshx.nativeextern.os;

/** Exact standard-library streams, the temporary directory, user directories, file information, host name and process lookup, with their platform rules and errors. */
@:go.import("os")
@:go.package("os")
@:goNative
extern class OsPkg {
	/** `os.Stdin`: the process's standard input. */
	@:go.name("Stdin") public static var stdin(default, never):File;

	/** `os.Stdout`: the process's standard output. */
	@:go.name("Stdout") public static var stdout(default, never):File;

	/**
		`os.Stderr`: the process's standard error, which Go code reads each time
		it prints there. Null makes those prints fail without output, as Go's
		writes to a nil `*os.File` do.
	**/
	@:go.name("Stderr") public static var stderr:Null<File>;

	/** `os.TempDir`: TMPDIR on Unix, or `/tmp` when it is empty. */
	@:go.name("TempDir") public static function tempDir():String;

	@:go.tupleReturn
	@:go.name("UserHomeDir") public static function userHomeDir():PathResult;

	@:go.tupleReturn
	@:go.name("UserConfigDir") public static function userConfigDir():PathResult;

	@:go.tupleReturn
	@:go.name("Stat") public static function stat(path:String):StatResult;

	/** Like `stat`, but describes a symbolic link itself instead of its target. */
	@:go.tupleReturn
	@:go.name("Lstat") public static function lstat(path:String):StatResult;

	@:go.tupleReturn
	@:go.name("Hostname") public static function hostname():PathResult;

	/** `os.ErrProcessDone`: what signalling a process that has ended returns. */
	@:go.name("ErrProcessDone") public static var errProcessDone(default, never):go.NativeError;

	@:go.name("IsNotExist") public static function isNotExist(error:go.NativeError):Bool;

	/** On Unix this always succeeds without touching the process; `Process.signal` then probes it. */
	@:go.tupleReturn
	@:go.name("FindProcess") public static function findProcess(pid:Int):FindProcessResult;
}
