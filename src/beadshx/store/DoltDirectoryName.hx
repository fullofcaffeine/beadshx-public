package beadshx.store;

import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.CustomConfig.isGoSpace;

/**
	Dolt dbfactory.DirToDBName: the name of the database that a directory in
	an embedded store holds.

	Why: Dolt reads DOLT_DBNAME_REPLACE from the process environment when it
	loads the store, so the same directory can hold two different names.
	What: the directory name, unless that variable is set and not empty: then
	the name is trimmed, each space or hyphen becomes `_`, and runs of `_`
	become one, so `my-db` holds `my_db`. How: Go's unicode.IsSpace decides a
	space, as Dolt's strings.Map does.
**/
@:goNative
final class DoltDirectoryName {
	public static function databaseName(directory:String):String {
		final replace = Sys.getEnv("DOLT_DBNAME_REPLACE");
		if (replace == null || replace == "")
			return directory;
		final trimmed = goTrimSpace(directory);
		final mapped = new StringBuf();
		for (index in 0...trimmed.length) {
			final code = trimmed.charCodeAt(index);
			mapped.addChar(isGoSpace(code) || code == "-".code ? "_".code : code);
		}
		var name = mapped.toString();
		while (name.indexOf("__") >= 0)
			name = StringTools.replace(name, "__", "_");
		return name;
	}
}
