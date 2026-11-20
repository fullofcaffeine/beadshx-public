package beadshx.nativeextern.os;

/** The `os.FileInfo` answer upstream's path checks read. */
@:go.import("os")
@:go.package("os")
@:go.name("FileInfo")
extern interface FileInfo {
	@:go.name("IsDir") public function isDir():Bool;
}
