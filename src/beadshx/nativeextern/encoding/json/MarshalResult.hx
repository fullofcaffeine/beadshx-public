package beadshx.nativeextern.encoding.json;

/** Typed carrier for `json.Marshal` bytes and native error results. */
@:goNative
final class MarshalResult {
	public var value1(default, null):go.NativeSlice<go.NativeByte>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:go.NativeSlice<go.NativeByte>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
