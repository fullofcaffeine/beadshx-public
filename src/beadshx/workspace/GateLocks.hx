package beadshx.workspace;

/** A shared advisory lock that a GateLockPort took on one gate file. */
interface GateLock {
	/** Unlocks the file and closes it. The lock also ends with the process. */
	function release():Void;
}

/** What one try for a shared lock on a gate file found. */
enum GateLockAttempt {
	/** The shared lock is held until `lock.release()` or the end of the process. */
	GateLockHeld(lock:GateLock);

	/** No file at the path. Upstream creates it there; this build does not, and takes no lock on it. */
	GateLockFileMissing;

	/** The platform has no advisory lock, as for upstream's js/wasm build, which counts the lock as taken. */
	GateLockUnsupported;

	/** Another process holds a conflicting (exclusive) lock. */
	GateLockBusy;

	/** The file did not open; the native error text, such as `permission denied`. */
	GateLockOpenFailed(error:String);

	/** The lock call failed for another reason than a conflicting lock; the native error text. */
	GateLockFailed(error:String);
}

/**
	The platform's shared, non-blocking advisory lock on an existing file.

	Why: upstream's internal/lockfile takes `flock(LOCK_SH|LOCK_NB)` on Unix
	and `LockFileEx(LOCKFILE_FAIL_IMMEDIATELY)` on Windows. What: one try,
	without a wait. How: the file opens read-only and is never created, so
	nothing is written.
**/
interface GateLockPort {
	function tryShared(path:String):GateLockAttempt;
}

/**
	Owns platform selection for gate locks.

	The common generated file names no platform package. A module with a Go
	build constraint installs the implementation for its platforms (see
	UnixGateLocks and WindowsGateLocks).
**/
final class GateLockAccess {
	static var implementation:GateLockPort = new UnsupportedGateLocks();

	public static function install(value:GateLockPort):Bool {
		implementation = value;
		return true;
	}

	public static function tryShared(path:String):GateLockAttempt {
		return implementation.tryShared(path);
	}
}

/** Platforms without an installed implementation, which take no lock. */
private final class UnsupportedGateLocks implements GateLockPort {
	public function new() {}

	public function tryShared(path:String):GateLockAttempt {
		return GateLockUnsupported;
	}
}
