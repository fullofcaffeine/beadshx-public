package beadshx.workspace;

import beadshx.workspace.GateLocks;
import beadshx.nativeextern.errors.Errors;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.unix.UnixPkg;

/**
	Upstream's Unix gate lock (internal/lockfile/lock_shared_unix.go:14):
	`flock(fd, LOCK_SH|LOCK_NB)`, where `EWOULDBLOCK` means another process
	holds the lock exclusively.

	Upstream opens the file with `O_CREATE|O_RDWR`
	(internal/workspacegate/gate.go:390). This build opens it `O_RDONLY`,
	which flock does not need writable, and never creates it.
**/
@:goBuildConstraint("unix")
@:keep
@:goNative
final class UnixGateLocks implements GateLockPort {
	static final installed:Bool = GateLockAccess.install(new UnixGateLocks());

	public function new() {}

	public function tryShared(path:String):GateLockAttempt {
		final opened = UnixPkg.open(path, UnixPkg.oRdonly | UnixPkg.oCloexec, 0);
		final openError = opened.value2;
		if (openError != null)
			return OsPkg.isNotExist(openError) ? GateLockFileMissing : GateLockOpenFailed(openError.text());
		final descriptor = opened.value1;
		final lockError = UnixPkg.flock(descriptor, UnixPkg.lockSh | UnixPkg.lockNb);
		if (lockError == null)
			return GateLockHeld(new UnixGateLock(descriptor));
		UnixPkg.close(descriptor);
		return Errors.matches(lockError, UnixPkg.ewouldblock) ? GateLockBusy : GateLockFailed(lockError.text());
	}
}

/** A held `flock` on one open descriptor. */
@:goBuildConstraint("unix")
@:goNative
private final class UnixGateLock implements GateLock {
	final descriptor:Int;

	public function new(descriptor:Int) {
		this.descriptor = descriptor;
	}

	/** Upstream's release (internal/workspacegate/gate.go:354): unlock, then close. Both are best effort. */
	public function release():Void {
		UnixPkg.flock(descriptor, UnixPkg.lockUn);
		UnixPkg.close(descriptor);
	}
}
