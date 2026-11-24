package beadshx.nativeextern.filepath;

/** Typed carrier for the `(dir, file string)` result of `filepath.Split`. */
@:goNative
final class SplitResult {
	public var value1(default, null):String;
	public var value2(default, null):String;

	public function new(value1:String, value2:String) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
