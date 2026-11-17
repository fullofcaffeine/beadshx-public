package beadshx.nativeextern.encoding.json;

import beadshx.nativeextern.bytes.Buffer;

/** Explicit standard-library syntax and token-escaping boundary; Haxe retains rendering policy. */
@:go.import("encoding/json")
@:go.package("json")
@:goNative
extern class JsonPkg {
	@:go.name("Compact") public static function compact(destination:Buffer, source:go.NativeSlice<go.NativeByte>):go.NativeError;
	@:go.name("HTMLEscape") public static function htmlEscape(destination:Buffer, source:go.NativeSlice<go.NativeByte>):Void;
}
