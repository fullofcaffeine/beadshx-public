package beadshx.nativeextern.syscall;

/** The exact `syscall.Signal(n)` conversion; signal 0 asks whether a process exists without signalling it. */
@:go.import("syscall")
@:go.package("syscall")
@:goNative
extern class SyscallPkg {
	@:go.valueReturn
	@:go.name("Signal") public static function signal(number:Int):Signal;
}
