package beadshx.nativeextern.os;

import beadshx.nativeextern.fs.FileMode;

/** The `os.FileInfo` answers upstream's path checks read. */
@:go.import("os")
@:go.package("os")
@:go.name("FileInfo")
@:goNative
extern interface FileInfo {
	@:go.name("IsDir") public function isDir():Bool;

	@:go.valueReturn
	@:go.name("Mode") public function mode():FileMode;

	/** `FileInfo.Size`: the length in bytes of a regular file. */
	@:go.name("Size") public function size():go.NativeInt64;
}
