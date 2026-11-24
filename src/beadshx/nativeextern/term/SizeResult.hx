package beadshx.nativeextern.term;

/** Typed carrier for `term.GetSize` width, height and native error results. */
@:goNative
final class SizeResult {
	public var value1(default, null):Int;
	public var value2(default, null):Int;
	public var value3(default, null):Null<go.NativeError>;

	public function new(value1:Int, value2:Int, value3:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
		this.value3 = value3;
	}
}
