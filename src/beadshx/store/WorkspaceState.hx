package beadshx.store;

import haxe.io.Path;

/** Reads optional local runtime state without treating absence as failure. */
function readLastTouchedId(beadsDir:String):String {
	final path = Path.join([beadsDir, "last-touched"]);
	if (!sys.FileSystem.exists(path))
		return "";
	try {
		return StringTools.trim(sys.io.File.getContent(path));
	} catch (_:haxe.Exception) {
		return "";
	}
}
