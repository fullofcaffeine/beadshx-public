package beadshx.store;

import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.EmbeddedDatabaseLookup.inProgressDatabaseDirectories;
import beadshx.workspace.RedirectSource;

/**
	What upstream's open of a workspace's embedded Dolt store prints and names
	when it fails without a write.

	Why: this build refuses or fails before it opens the store in those cases,
	so it prints what the open would print. What: Dolt's logrus warnings for
	in-progress database directories, and the store directory that the
	errors name. How: it only reads the store directory.
**/
@:goNative
final class DoltStoreOpen {
	/**
		Dolt's warning for each directory in `beadsDir`'s store that holds the
		in-progress marker, which it skips when it opens the store: logrus's
		text format with the time of the open and the absolute path. "" for
		none.
	**/
	public static function inProgressWarnings(beadsDir:String):String {
		final dataDir = storeDirectory(beadsDir);
		final warnings = new StringBuf();
		for (entry in inProgressDatabaseDirectories(beadsDir))
			warnings.add('time="${TimePkg.now().format("2006-01-02T15:04:05Z07:00")}" level=warning msg="skipping in-progress database directory" path=${logrusValue(FilepathPkg.join(dataDir, entry))}\n');
		return warnings.toString();
	}

	/** The absolute `embeddeddolt` directory of `beadsDir`, which the open errors name. */
	public static function storeDirectory(beadsDir:String):String {
		return FilepathPkg.join(RedirectSource.canonicalizePath(beadsDir), "embeddeddolt");
	}

	/**
		A logrus text-format value: as it is, or quoted as Go's %q quotes it
		when it holds another character than an ASCII letter, a digit or one of
		`-._/@^+`.
	**/
	static function logrusValue(value:String):String {
		for (index in 0...value.length) {
			final code = StringTools.fastCodeAt(value, index);
			final plain = (code >= "a".code && code <= "z".code)
				|| (code >= "A".code && code <= "Z".code)
				|| (code >= "0".code && code <= "9".code)
				|| "-._/@^+".indexOf(String.fromCharCode(code)) >= 0;
			if (!plain)
				return StrconvPkg.quote(value);
		}
		return value;
	}
}
