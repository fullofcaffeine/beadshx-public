package beadshx.nativeextern.time;

/** Typed carrier for Go's `(time.Duration, error)` result. */
@:goNative
final class ParseDurationResult {
	public var value1(default, null):Duration;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Duration, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
