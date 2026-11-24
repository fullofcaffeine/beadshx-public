package beadshx.nativeextern.os;

import beadshx.nativeextern.fs.FileMode;

/** The `os.FileInfo` answers upstream's path checks read. */
@:go.import("os")
@:go.package("os")
@:go.name("FileInfo")
extern interface FileInfo {
	@:go.name("IsDir") public function isDir():Bool;

	@:go.valueReturn
	@:go.name("Mode") public function mode():FileMode;
}
