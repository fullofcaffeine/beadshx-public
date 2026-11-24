package beadshx.nativeextern.windows;

/**
	Typed carrier for the `(fd Handle, err error)` result of `windows.Open`.
	It names `windows.Handle`, so it exists only in Windows builds.
**/
@:goBuildConstraint("windows")
@:goNative
final class HandleResult {
	public var value1(default, null):Handle;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Handle, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
