package beadshx.nativeextern.os;

/** Typed carrier for `os.Stat` file information and native error results. */
@:goNative
final class StatResult {
	public var value1(default, null):Null<FileInfo>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<FileInfo>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
