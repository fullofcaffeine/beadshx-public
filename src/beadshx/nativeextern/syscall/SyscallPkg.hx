package beadshx.nativeextern.syscall;

/** The exact `syscall.Signal(n)` conversion; signal 0 asks whether a process exists without signalling it. */
@:go.import("syscall")
@:go.package("syscall")
@:goNative
extern class SyscallPkg {
	@:go.valueReturn
	@:go.name("Signal") public static function signal(number:Int):Signal;

	/** "No such process": signal 0 to a process that has ended. */
	@:go.name("ESRCH") public static var esrch(default, never):go.NativeError;

	/** "Is a directory": what Go's `os.OpenFile` returns for a directory opened for writing. */
	@:go.name("EISDIR") public static var eisdir(default, never):go.NativeError;

	/** On Windows, the error that upstream's lockfile also counts as a held lock. */
	@:go.name("EWOULDBLOCK") public static var ewouldblock(default, never):go.NativeError;
}
