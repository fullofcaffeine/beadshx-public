package beadshx.workspace;

import beadshx.workspace.GateLocks;
import beadshx.nativeextern.errors.Errors;
import beadshx.nativeextern.math.MathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.syscall.SyscallPkg;
import beadshx.nativeextern.windows.Handle;
import beadshx.nativeextern.windows.Overlapped;
import beadshx.nativeextern.windows.WindowsPkg;

/**
	Upstream's Windows gate lock (internal/lockfile/lock_shared_windows.go:15):
	`LockFileEx` with `LOCKFILE_FAIL_IMMEDIATELY` and no exclusive flag over
	the whole file, where `ERROR_LOCK_VIOLATION` or `EWOULDBLOCK` means
	another process holds the lock exclusively.

	Upstream opens the file with `O_CREATE|O_RDWR`
	(internal/workspacegate/gate.go:390). This build opens it `O_RDONLY`,
	which a shared lock does not need writable, and never creates it.
**/
@:goBuildConstraint("windows")
@:keep
@:goNative
final class WindowsGateLocks implements GateLockPort {
	static final installed:Bool = GateLockAccess.install(new WindowsGateLocks());

	public function new() {}

	public function tryShared(path:String):GateLockAttempt {
		final opened = WindowsPkg.open(path, WindowsPkg.oRdonly | WindowsPkg.oCloexec, go.NativeUint32.fromInt(0));
		final openError = opened.value2;
		if (openError != null)
			return OsPkg.isNotExist(openError) ? GateLockFileMissing : GateLockOpenFailed(openError.text());
		final handle = opened.value1;
		final lockError = WindowsPkg.lockFileEx(handle, WindowsPkg.lockfileFailImmediately, go.NativeUint32.fromInt(0), MathPkg.maxUint32, MathPkg.maxUint32,
			new Overlapped());
		if (lockError == null)
			return GateLockHeld(new WindowsGateLock(handle));
		WindowsPkg.closeHandle(handle);
		return Errors.matches(lockError, WindowsPkg.errorLockViolation)
			|| Errors.matches(lockError, SyscallPkg.ewouldblock) ? GateLockBusy : GateLockFailed(lockError.text());
	}
}

/** A held `LockFileEx` lock on one open handle. */
@:goBuildConstraint("windows")
@:goNative
private final class WindowsGateLock implements GateLock {
	final handle:Handle;

	public function new(handle:Handle) {
		this.handle = handle;
	}

	/** Upstream's release (internal/workspacegate/gate.go:354): unlock, then close. Both are best effort. */
	public function release():Void {
		WindowsPkg.unlockFileEx(handle, go.NativeUint32.fromInt(0), MathPkg.maxUint32, MathPkg.maxUint32, new Overlapped());
		WindowsPkg.closeHandle(handle);
	}
}
