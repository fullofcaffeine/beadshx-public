package beadshx.nativeextern.url;

/** Exact standard-library URL parsing, whose error text upstream prints for a malformed remote URL. */
@:go.import("net/url")
@:go.package("url")
@:goNative
extern class UrlPkg {
	@:go.tupleReturn
	@:go.name("Parse") public static function parse(raw:String):ParseUrlResult;
}
