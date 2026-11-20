package beadshx.nativeextern.url;

/** Typed carrier for `url.Parse` value and native error results. */
@:goNative
final class ParseUrlResult {
	public var value1(default, null):Null<Url>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<Url>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
