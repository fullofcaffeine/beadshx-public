package beadshx.nativeextern.issueops;

/** Typed carrier for the `(EdgeReadResult, error)` result. */
@:goNative
final class EdgeReaderResult {
	public var value1(default, null):EdgeReadResult;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:EdgeReadResult, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
