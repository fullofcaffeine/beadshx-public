package beadshx.nativeextern.strconv;

/** Exact standard-library integer formatting and parsing; no Float or Haxe arithmetic intermediary. */
@:go.import("strconv") @:go.package("strconv") @:goNative
extern class StrconvPkg {
	@:go.name("Itoa") public static function itoa(value:Int):String;
	@:go.name("FormatInt") public static function formatInt(value:go.NativeInt64, base:Int):String;

	/** pflag parses int and int64 flags with `ParseInt(value, 0, 64)`; its error text is the flag message tail. */
	@:go.tupleReturn
	@:go.name("ParseInt") public static function parseInt(value:String, base:Int, bitSize:Int):ParseIntResult;

	/** Go's `%q` for a string. */
	@:go.name("Quote") public static function quote(value:String):String;
}
