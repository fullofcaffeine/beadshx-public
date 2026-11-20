package beadshx.nativeextern.net;

/** The standard-library `net.Conn` interface; the server probe only closes a connection that opened. */
@:go.import("net")
@:go.package("net")
@:go.name("Conn")
@:goNative
extern interface Conn {
	@:go.name("Close") public function close():go.Error;
}
