package beadshx.nativeextern.windows;

/**
	The `golang.org/x/sys/windows` calls of upstream's internal/lockfile for a
	shared workspace gate (lock_shared_windows.go, lock_windows.go), with a
	read-only open in place of its `O_CREATE|O_RDWR` open.

	Go types the lock flags, the reserved word and the byte counts as
	`uint32`, so they are `go.NativeUint32` here: `lockfileFailImmediately`,
	`go.NativeUint32.fromInt(0)` and `math.MaxUint32`. Only
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

	@:go.name("LOCKFILE_FAIL_IMMEDIATELY") public static var lockfileFailImmediately(default, never):go.NativeUint32;

	/** The `syscall.Errno` that `LockFileEx` returns while another process holds a conflicting lock. */
	@:go.name("ERROR_LOCK_VIOLATION") public static var errorLockViolation(default, never):go.NativeError;

	/** `windows.Open(path, mode, perm)`; callers never pass `O_CREAT`, so they pass `go.NativeUint32.fromInt(0)` as Go's `uint32` perm. */
	@:go.tupleReturn
	@:go.tupleValueResults("0")
	@:go.name("Open") public static function open(path:String, mode:Int, permission:go.NativeUint32):HandleResult;

	@:go.valueArgs("0")
	@:go.name("LockFileEx") public static function lockFileEx(file:Handle, flags:go.NativeUint32, reserved:go.NativeUint32, bytesLow:go.NativeUint32,
		bytesHigh:go.NativeUint32, overlapped:Overlapped):Null<go.NativeError>;

	@:go.valueArgs("0")
	@:go.name("UnlockFileEx") public static function unlockFileEx(file:Handle, reserved:go.NativeUint32, bytesLow:go.NativeUint32, bytesHigh:go.NativeUint32,
		overlapped:Overlapped):Null<go.NativeError>;

	@:go.valueArgs("0")
	@:go.name("CloseHandle") public static function closeHandle(handle:Handle):Null<go.NativeError>;
}
