package beadshx.nativeextern.url;

/** The parsed `*url.URL` fields that upstream's remote URL checks read. */
@:go.import("net/url")
@:go.package("url")
@:go.name("URL")
@:go.struct
extern class Url {
	@:go.name("Host") public var host:String;
	@:go.name("Path") public var path:String;
}
