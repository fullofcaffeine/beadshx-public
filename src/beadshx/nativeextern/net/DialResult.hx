package beadshx.nativeextern.net;

/** Typed carrier for `net.DialTimeout` connection and native error results. */
@:goNative
final class DialResult {
	public var value1(default, null):Null<Conn>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<Conn>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
