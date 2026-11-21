package beadshx.store;

#if (go || go_output)
import beadshx.nativeextern.bytes.Buffer;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.encoding.json.JsonPkg;
#end

/**
	encoding/json's syntax check, the first step of json.Unmarshal.

	Why: upstream reports a malformed metadata.json with Unmarshal's own syntax
	error text. What: that text for some JSON, or null when Go accepts it.
	How: json.Compact runs the same scanner as Unmarshal's well-formedness
	check, so its error is Unmarshal's. The interpreter has no Go scanner and
	reports null, which leaves the decision to the typed parser.
**/
@:goNative
final class GoJsonSyntax {
	public static function syntaxError(raw:String):Null<String> {
		#if (go || go_output)
		final error = JsonPkg.compact(new Buffer(), BytesPkg.newBufferString(raw).bytes());
		return error == null ? null : error.text();
		#else
		return null;
		#end
	}
}
