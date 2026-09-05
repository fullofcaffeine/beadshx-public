package beadshx.nativeextern.issueops;

/** Typed carrier for the `(IssuePage, error)` result of `Reader.List`. */
@:goNative
final class ReaderListResult {
	public var value1(default, null):IssuePage;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:IssuePage, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
