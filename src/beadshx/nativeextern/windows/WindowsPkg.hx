package beadshx.nativeextern.windows;

/**
	The `golang.org/x/sys/windows` calls of upstream's internal/lockfile for a
	shared workspace gate (lock_shared_windows.go, lock_windows.go), with a
	read-only open in place of its `O_CREATE|O_RDWR` open.

	Go types the lock flags, the reserved word and the byte counts as
	`uint32`. Callers pass Go constants there (`lockfileFailImmediately`, `0`
	and `math.MaxUint32`); Go rejects an `int` variable at compile time. Only
	the `@:goBuildConstraint("windows")` module may use this class: the
	package has no files on other platforms.
**/
@:go.import("golang.org/x/sys/windows")
@:go.package("windows")
@:goNative
extern class WindowsPkg {
	@:go.name("O_RDONLY") public static var oRdonly(default, never):Int;

	/** Without it `windows.Open` makes the handle inheritable; Go's `os.OpenFile` always passes it. */
	@:go.name("O_CLOEXEC") public static var oCloexec(default, never):Int;

	@:go.name("LOCKFILE_FAIL_IMMEDIATELY") public static var lockfileFailImmediately(default, never):Int;

	/** The `syscall.Errno` that `LockFileEx` returns while another process holds a conflicting lock. */
	@:go.name("ERROR_LOCK_VIOLATION") public static var errorLockViolation(default, never):go.NativeError;

	/** `windows.Open(path, mode, perm)`; callers pass the constant `0` as Go's `uint32` perm and never `O_CREAT`. */
	@:go.tupleReturn
	@:go.tupleValueResults("0")
	@:go.name("Open") public static function open(path:String, mode:Int, permission:Int):HandleResult;

	@:go.valueArgs("0")
	@:go.name("LockFileEx") public static function lockFileEx(file:Handle, flags:Int, reserved:Int, bytesLow:Int, bytesHigh:Int,
		overlapped:Overlapped):Null<go.NativeError>;

	@:go.valueArgs("0")
	@:go.name("UnlockFileEx") public static function unlockFileEx(file:Handle, reserved:Int, bytesLow:Int, bytesHigh:Int,
		overlapped:Overlapped):Null<go.NativeError>;

	@:go.valueArgs("0")
	@:go.name("CloseHandle") public static function closeHandle(handle:Handle):Null<go.NativeError>;
}
