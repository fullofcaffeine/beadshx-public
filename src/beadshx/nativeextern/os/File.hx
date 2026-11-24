package beadshx.nativeextern.os;

/** An opaque standard-library `*os.File`, such as `os.Stdin`, passed to native APIs unchanged. */
@:go.import("os")
@:go.package("os")
@:go.name("File")
@:goNative
extern class File {
	/**
		The file's descriptor (`(*os.File).Fd`), a Go `uintptr`. Upstream passes
		`int(os.Stdout.Fd())` to `term.GetSize`; on Windows it is the console handle.
	**/
	@:go.name("Fd") public function fd():go.NativeUintptr;
}
