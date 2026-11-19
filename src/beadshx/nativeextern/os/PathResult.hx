package beadshx.nativeextern.os;

/** Typed carrier for a standard-library `(string, error)` path result. */
@:goNative
class PathResult {
	public var value1(default, null):String;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:String, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
