package beadshx.nativeextern.windows;

/** Opaque native `windows.Handle` of one open file. No Go finalizer closes it. */
@:go.import("golang.org/x/sys/windows")
@:go.package("windows")
@:go.name("Handle")
@:go.valueType
extern class Handle {}
