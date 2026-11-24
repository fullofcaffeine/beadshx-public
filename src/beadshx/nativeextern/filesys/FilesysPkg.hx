package beadshx.nativeextern.filesys;

/** Exact Dolt filesys package variables. */
@:go.import("github.com/dolthub/dolt/go/libraries/utils/filesys")
@:go.package("filesys")
@:goNative
extern class FilesysPkg {
	/** `filesys.LocalFS`: the local file system, which makes a relative path absolute from the working directory before it reads. */
	@:go.name("LocalFS") public static var localFs(default, never):Filesys;
}
