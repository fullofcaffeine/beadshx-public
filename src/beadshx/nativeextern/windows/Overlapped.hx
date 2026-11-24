package beadshx.nativeextern.windows;

/** A zero `windows.Overlapped`: `LockFileEx` and `UnlockFileEx` then start at byte 0, as upstream's lockfile calls them. */
@:go.import("golang.org/x/sys/windows")
@:go.package("windows")
@:go.name("Overlapped")
@:go.struct
extern class Overlapped {
	public function new();
}
