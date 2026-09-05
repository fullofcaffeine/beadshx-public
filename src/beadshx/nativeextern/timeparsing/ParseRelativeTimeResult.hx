package beadshx.nativeextern.timeparsing;

import beadshx.nativeextern.time.Time;

/** Typed carrier for Go's `(time.Time, error)` result. */
@:goNative
final class ParseRelativeTimeResult {
	public var value1(default, null):Time;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Time, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
