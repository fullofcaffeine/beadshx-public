package beadshx.config;

import beadshx.nativeextern.regexp.Regexp.RegexpPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import haxe.io.Bytes;
import sys.io.File;

/**
	subosito/gotenv v1.6.0's Read, which upstream uses to parse `.beads/.env`.

	Why: upstream loads per-workspace variables from `.beads/.env` with gotenv
	before it reads BD_ and BEADS_ settings, and gotenv has its own rules for
	quotes, comments, `export`, `$VAR` expansion, line endings and byte order
	marks. What: the variables of one file, or null when gotenv reports an
	error, because upstream then takes nothing from that file. How: the same
	steps as gotenv's strictParse with override off. Go's regexp, through a
	precise extern, matches each logical line with gotenv's exact pattern; the
	decoding, line splitting, quote scan, unescaping and expansion are ported
	here. A .env file is expected to be valid UTF-8 (or UTF-16 with a byte
	order mark); Haxe strings hold Unicode scalars, so an ill-formed UTF-8
	byte can reach the environment as U+FFFD where Go would keep the byte.
**/
@:goNative
final class DotEnv {
	/** gotenv's linePattern: an optional `export`, a key, `=` or `:` and an optional quoted or bare value and comment. */
	static final line = RegexpPkg.mustCompile("\\A\\s*(?:export\\s+)?([\\w\\.]+)(?:\\s*=\\s*|:\\s+?)('(?:\\'|[^'])*'|\"(?:\\\"|[^\"])*\"|[^#\\n]+)?\\s*(?:\\s*\\#.*)?\\z");

	/** bufio.Scanner's default limit: a longer line stops gotenv's scan with an error. */
	static inline final MAX_LINE_BYTES = 64 * 1024;

	/**
		gotenv.Read: the file's variables, or null when it cannot be read or
		gotenv rejects it. `lookup` stands for os.LookupEnv, which `$VAR`
		expansion consults before the file's own earlier variables.
	**/
	public static function read(path:String, lookup:String->Null<String>):Null<Map<String, String>> {
		final bytes = try File.getBytes(path) catch (_:haxe.Exception) null;
		if (bytes == null)
			return null;
		return parse(decode(bytes), lookup);
	}

	/** gotenv's strictParse over decoded text: null for a too-long line, an unclosed quote or a line that does not match. */
	public static function parse(text:String, lookup:String->Null<String>):Null<Map<String, String>> {
		final lines = splitLines(text);
		for (raw in lines)
			if (Bytes.ofString(raw).length >= MAX_LINE_BYTES)
				return null;
		final variables = new Map<String, String>();
		var next = 0;
		while (next < lines.length) {
			var logical = goTrimSpace(lines[next]);
			next++;
			if (logical == "" || logical.charAt(0) == "#")
				continue;
			var quote = openQuote(logical);
			// A quoted value that does not close on its line continues on the next lines, untrimmed.
			while (quote != "" && next < lines.length) {
				final continued = lines[next];
				next++;
				logical += "\n" + continued;
				final closing = continued.lastIndexOf(quote);
				if (closing > 0 && continued.charAt(closing - 1) == "\\")
					continue;
				if (closing >= 0)
					quote = "";
			}
			if (quote != "" || !parseLine(logical, variables, lookup))
				return null;
		}
		return variables;
	}

	/**
		The quote that gotenv expects to close on a later line: the first character
		of the trimmed value after the first `=` (else the first `:`), when it is a
		quote and gotenv's check finds no closing quote. That check indexes the
		value with a position found in the value without its opening quote, as
		gotenv does.
	**/
	static function openQuote(logical:String):String {
		var separator = logical.indexOf("=");
		if (separator == -1)
			separator = logical.indexOf(":");
		if (separator <= 0 || separator >= logical.length - 1)
			return "";
		final value = goTrimSpace(logical.substr(separator + 1));
		final first = value.charAt(0);
		if (first != "\"" && first != "'")
			return "";
		final closing = goTrimSpace(value.substr(1)).lastIndexOf(first);
		return closing >= 0 && value.charAt(closing) != "\\" ? "" : first;
	}

	/** gotenv's parseLine: sets the key and returns true, or returns false when the line does not match. */
	static function parseLine(logical:String, variables:Map<String, String>, lookup:String->Null<String>):Bool {
		final groups = line.findStringSubmatch(logical);
		if (groups.length == 0)
			return false;
		final key = goTrimSpace(groups[1]);
		var value = goTrimSpace(groups[2]);
		var singleQuoted = false;
		var doubleQuoted = false;
		if (value.length >= 2) {
			final last = value.length - 1;
			doubleQuoted = value.charAt(0) == "\"" && value.charAt(last) == "\"";
			singleQuoted = value.charAt(0) == "'" && value.charAt(last) == "'";
			if (singleQuoted || doubleQuoted)
				value = value.substring(1, last);
		}
		if (doubleQuoted) {
			value = StringTools.replace(value, "\\n", "\n");
			value = StringTools.replace(value, "\\r", "\r");
			value = unescape(value);
		}
		if (!singleQuoted)
			value = expand(value, variables, lookup);
		variables.set(key, value);
		return true;
	}

	/** gotenv's `\\([^$])` → `$1`: a backslash before any character but `$` is dropped. */
	static function unescape(value:String):String {
		final result = new StringBuf();
		var index = 0;
		while (index < value.length) {
			final character = value.charAt(index);
			if (character == "\\" && index + 1 < value.length && value.charAt(index + 1) != "$") {
				result.add(value.charAt(index + 1));
				index += 2;
			} else {
				result.add(character);
				index++;
			}
		}
		return result.toString();
	}

	/**
		gotenv's variablePattern `(\\)?(\$)(\{?([A-Z0-9_]+)?\}?)` replaced by
		varReplacement: `\$` keeps a literal `$`, a bare `$` or `${}` stays, and a
		name takes the process value, else the file's earlier value, else "".
		The braces need not pair; whichever are present belong to the match.
	**/
	static function expand(value:String, variables:Map<String, String>, lookup:String->Null<String>):String {
		final result = new StringBuf();
		var index = 0;
		while (index < value.length) {
			final character = value.charAt(index);
			final escaped = character == "\\" && index + 1 < value.length && value.charAt(index + 1) == "$";
			if (!escaped && character != "$") {
				result.add(character);
				index++;
				continue;
			}
			var end = escaped ? index + 2 : index + 1;
			final braced = end < value.length && value.charAt(end) == "{";
			if (braced)
				end++;
			final nameStart = end;
			while (end < value.length && isNameCharacter(value.charAt(end)))
				end++;
			final name = value.substring(nameStart, end);
			if (end < value.length && value.charAt(end) == "}")
				end++;
			final matched = value.substring(index, end);
			result.add(if (escaped) {
				matched.substr(1);
			} else if (name == "") {
				matched;
			} else {
				final processValue = lookup(name);
				processValue != null ? processValue : variables.exists(name) ? variables.get(name) : "";
			});
			index = end;
		}
		return result.toString();
	}

	static function isNameCharacter(character:String):Bool {
		final code = character.charCodeAt(0);
		return code != null && ((code >= "A".code && code <= "Z".code) || (code >= "0".code && code <= "9".code) || code == "_".code);
	}

	/**
		gotenv's encoding choice from the first bytes: a UTF-8 byte order mark is
		dropped, UTF-16 with a byte order mark is decoded, and anything else is
		read as it is.
	**/
	static function decode(bytes:Bytes):String {
		if (bytes.length >= 3 && bytes.get(0) == 0xEF && bytes.get(1) == 0xBB && bytes.get(2) == 0xBF)
			return bytes.getString(3, bytes.length - 3);
		if (bytes.length >= 2 && bytes.get(0) == 0xFF && bytes.get(1) == 0xFE)
			return decodeUtf16(bytes, true);
		if (bytes.length >= 2 && bytes.get(0) == 0xFE && bytes.get(1) == 0xFF)
			return decodeUtf16(bytes, false);
		return bytes.toString();
	}

	/**
		golang.org/x/text's UTF-16 decoder after the byte order mark: a surrogate
		followed by a trailing surrogate takes both units (a valid pair decodes,
		anything else is U+FFFD), any other surrogate is U+FFFD, and a single
		final byte is U+FFFD.
	**/
	static function decodeUtf16(bytes:Bytes, littleEndian:Bool):String {
		function unit(at:Int):Int {
			return littleEndian ? bytes.get(at) | (bytes.get(at + 1) << 8) : (bytes.get(at) << 8) | bytes.get(at + 1);
		}
		final text = new StringBuf();
		var index = 2;
		while (index < bytes.length) {
			if (index + 1 >= bytes.length) {
				text.addChar(0xFFFD);
				index++;
				continue;
			}
			var code = unit(index);
			var size = 2;
			if (code >= 0xD800 && code <= 0xDFFF && index + 3 < bytes.length) {
				final trailing = unit(index + 2);
				if (trailing >= 0xDC00 && trailing <= 0xDFFF) {
					code = code < 0xDC00 ? 0x10000 + ((code - 0xD800) << 10) + (trailing - 0xDC00) : 0xFFFD;
					size = 4;
				}
			}
			text.addChar(code >= 0xD800 && code <= 0xDFFF ? 0xFFFD : code);
			index += size;
		}
		return text.toString();
	}

	/** gotenv's splitLines: a CR, an LF or a CRLF ends a line, and nothing follows a final line break. */
	static function splitLines(text:String):Array<String> {
		final lines = new Array<String>();
		var start = 0;
		var index = 0;
		while (index < text.length) {
			final character = text.charAt(index);
			if (character != "\r" && character != "\n") {
				index++;
				continue;
			}
			lines.push(text.substring(start, index));
			index += character == "\r" && index + 1 < text.length && text.charAt(index + 1) == "\n" ? 2 : 1;
			start = index;
		}
		if (start < text.length)
			lines.push(text.substring(start));
		return lines;
	}
}
