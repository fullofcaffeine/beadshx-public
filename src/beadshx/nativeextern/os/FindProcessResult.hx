package beadshx.nativeextern.os;

/** Typed carrier for `os.FindProcess` handle and native error results. */
@:goNative
final class FindProcessResult {
	public var value1(default, null):Null<Process>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<Process>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
