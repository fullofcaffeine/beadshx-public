package beadshx.nativeextern.time;

/** Typed carrier for Go's `(time.Time, error)` parse result. */
@:goNative
final class ParseTimeResult {
	public var value1(default, null):Time;
	public var value2(default, null):go.NativeError;

	public function new(value1:Time, value2:go.NativeError) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
