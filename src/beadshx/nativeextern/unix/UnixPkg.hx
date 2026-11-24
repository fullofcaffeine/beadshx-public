package beadshx.nativeextern.unix;

/**
	The `golang.org/x/sys/unix` calls of upstream's internal/lockfile for a
	shared workspace gate (lock_shared_unix.go, lock_unix.go), with a
	read-only open in place of its `O_CREATE|O_RDWR` open.

	The descriptor is a raw `int`, which no Go finalizer closes, so a lock
	stays held until `close` or the end of the process. Only the
	`@:goBuildConstraint("unix")` module may use this class: the package has
	no files on other platforms.
**/
@:go.import("golang.org/x/sys/unix")
@:go.package("unix")
@:goNative
extern class UnixPkg {
	@:go.name("O_RDONLY") public static var oRdonly(default, never):Int;

	/** Keeps the descriptor out of child processes, as Go's `os.OpenFile` does. */
	@:go.name("O_CLOEXEC") public static var oCloexec(default, never):Int;

	@:go.name("LOCK_SH") public static var lockSh(default, never):Int;
	@:go.name("LOCK_NB") public static var lockNb(default, never):Int;
	@:go.name("LOCK_UN") public static var lockUn(default, never):Int;

	/** The `syscall.Errno` that a non-blocking `flock` returns while another process holds a conflicting lock. */
	@:go.name("EWOULDBLOCK") public static var ewouldblock(default, never):go.NativeError;

	/**
		`unix.Open(path, mode, perm)`. Go's `perm` is a `uint32`, the mode of a
		file that `O_CREAT` creates. Callers pass the constant `0` and never
		`O_CREAT`; Go rejects an `int` variable there at compile time.
	**/
	@:go.tupleReturn
	@:go.name("Open") public static function open(path:String, mode:Int, permission:Int):OpenResult;

	@:go.name("Flock") public static function flock(descriptor:Int, operation:Int):Null<go.NativeError>;
	@:go.name("Close") public static function close(descriptor:Int):Null<go.NativeError>;
}
