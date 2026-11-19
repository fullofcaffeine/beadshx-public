package beadshx.nativeextern.strconv;

/** Typed carrier for `strconv.ParseInt` value and error results. */
@:goNative
class ParseIntResult {
	public var value1(default, null):go.NativeInt64;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:go.NativeInt64, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
