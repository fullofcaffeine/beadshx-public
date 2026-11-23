package beadshx.nativeextern.encoding.json;

import beadshx.nativeextern.bytes.Buffer;

/** Explicit standard-library syntax and token-escaping boundary; Haxe retains rendering policy. */
@:go.import("encoding/json")
@:go.package("json")
@:goNative
extern class JsonPkg {
	@:go.name("Compact") public static function compact(destination:Buffer, source:go.NativeSlice<go.NativeByte>):go.NativeError;
	@:go.name("HTMLEscape") public static function htmlEscape(destination:Buffer, source:go.NativeSlice<go.NativeByte>):Void;

	/**
		Go's `Marshal` of one float64, which Go's `any` parameter accepts: the number text encoding/json
		writes for it. Only NaN and the infinities fail.
	**/
	@:go.tupleReturn
	@:go.name("Marshal") public static function marshalFloat64(value:Float):MarshalResult;
}
