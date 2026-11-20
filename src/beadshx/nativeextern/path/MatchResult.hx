package beadshx.nativeextern.path;

/** Typed carrier for `path.Match` result and pattern error. */
@:goNative
final class MatchResult {
	public var value1(default, null):Bool;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Bool, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
