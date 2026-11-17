package beadshx.nativeextern.strconv;

/** Exact standard-library integer formatting; no Float or Haxe arithmetic intermediary. */
@:go.import("strconv") @:go.package("strconv") @:goNative
extern class StrconvPkg {
	@:go.name("Itoa") public static function itoa(value:Int):String;
	@:go.name("FormatInt") public static function formatInt(value:go.NativeInt64, base:Int):String;
}
