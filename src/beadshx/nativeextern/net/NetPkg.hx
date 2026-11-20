package beadshx.nativeextern.net;

import beadshx.nativeextern.time.Duration;

/** Exact standard-library dialing, so a refused connection reads as the platform's own error text. */
@:go.import("net")
@:go.package("net")
@:goNative
extern class NetPkg {
	@:go.tupleReturn
	@:go.valueArgs("2")
	@:go.name("DialTimeout") public static function dialTimeout(network:String, address:String, timeout:Duration):DialResult;
}
