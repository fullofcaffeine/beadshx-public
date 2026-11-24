package beadshx.nativeextern.unix;

/** Typed carrier for the `(fd int, err error)` result of `unix.Open`. */
@:goNative
final class OpenResult {
	public var value1(default, null):Int;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Int, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
