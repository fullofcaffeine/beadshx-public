package beadshx.nativeextern.os;

import beadshx.nativeextern.syscall.Signal;

/** A standard-library `*os.Process` handle; delivering signal 0 tests that the process exists and may be signalled. */
@:go.import("os")
@:go.package("os")
@:go.name("Process")
@:goNative
extern class Process {
	@:go.valueArgs("0")
	@:go.name("Signal") public function signal(signal:Signal):go.NativeError;
}
