package beadshx.store;

import beadshx.nativeextern.errors.Errors;
import beadshx.nativeextern.errors.Errors.ErrorMatch;
import beadshx.nativeextern.mysql.MySqlError;
import beadshx.nativeextern.regexp.Regexp.RegexpPkg;

/** Native error boundary: preserve Go identity while Haxe owns classification. */
@:goNative
final class DatabaseErrors {
	static final quotedTableMissing = RegexpPkg.mustCompile("(?i)\\btable\\s+'[^']+'\\s+(doesn't exist|does not exist)\\b");
	static final unquotedTableMissing = RegexpPkg.mustCompile("(?i)^table\\s+`?[^\\s'`]+`?\\s+(doesn't exist|does not exist)\\b");

	/**
		Match the pinned upstream missing-table contract without flattening native errors.
		A matched driver code is authoritative even when its text suggests another code.
		Only errors without a MySQL cause use the legacy text patterns; missing columns
		and schemas must not turn into optional-table absence.
	**/
	public static function isTableNotExist(error:go.NativeError):Bool {
		if (error == null)
			return false;
		final matchedError:ErrorMatch<MySqlError> = Errors.asType(error);
		if (matchedError.matched)
			return matchedError.value.number == 1146;
		final message = error.text().toLowerCase();
		return message.indexOf("error 1146") >= 0 || quotedTableMissing.matchString(message) || unquotedTableMissing.matchString(message);
	}

	/**
		Dolt's `Error 1049: database not found`. Upstream's embedded open runs
		``USE `db` `` and fails there before its schema check; this build starts
		each connection in the database, so the first query meets that error.
	**/
	public static function isDatabaseNotFound(error:go.NativeError):Bool {
		if (error == null)
			return false;
		final matchedError:ErrorMatch<MySqlError> = Errors.asType(error);
		if (matchedError.matched)
			return matchedError.value.number == 1049;
		return error.text().toLowerCase().indexOf("error 1049") >= 0;
	}
}
