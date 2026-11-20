package beadshx.nativeextern.syscall;

/** Opaque native `syscall.Signal` value, which `os.Process.Signal` accepts. */
@:go.import("syscall")
@:go.package("syscall")
@:go.name("Signal")
@:go.valueType
extern class Signal {}
