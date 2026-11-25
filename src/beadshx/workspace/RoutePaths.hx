package beadshx.workspace;

import beadshx.nativeextern.filepath.FilepathPkg;

/**
	The paths that upstream's routed reads open.

	Why: a prefix route or contributor auto-routing can name the workspace
	that the command already reads, by another path. Upstream then opens the
	same store a second time, so the read answers as the first one did.
	What: upstream routing.ExpandPath, and whether two paths name one
	directory.
	How: it only reads the file system, through Go's path/filepath.
**/
@:goNative
final class RoutePaths {
	/**
		Upstream routing.ExpandPath: a leading `~/` joined to the home directory
		($HOME, as os.UserHomeDir reads it on Unix), and a relative path made
		absolute with filepath.Abs. A path that does not expand stays.
	**/
	public static function expandRoutePath(path:String):String {
		var expanded = path;
		if (StringTools.startsWith(expanded, "~/")) {
			final home = Sys.getEnv("HOME");
			if (home != null && home != "")
				expanded = FilepathPkg.join(home, expanded.substr(2));
		}
		if (!FilepathPkg.isAbs(expanded)) {
			final absolute = FilepathPkg.abs(expanded);
			if (absolute.value2 == null)
				expanded = absolute.value1;
		}
		return expanded;
	}

	/**
		Whether two paths name one directory: after filepath.Abs, and after
		filepath.EvalSymlinks where it resolves. A routed read opens a store by
		its path, so another path to the same `.beads` opens the same store.
	**/
	public static function sameDirectory(left:String, right:String):Bool {
		return resolvedPath(left) == resolvedPath(right);
	}

	static function resolvedPath(path:String):String {
		final absolute = FilepathPkg.abs(path);
		final cleaned = absolute.value2 == null ? absolute.value1 : FilepathPkg.clean(path);
		final resolved = FilepathPkg.evalSymlinks(cleaned);
		return resolved.value2 == null ? resolved.value1 : cleaned;
	}
}
