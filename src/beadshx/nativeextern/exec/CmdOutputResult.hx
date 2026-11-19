package beadshx.nativeextern.exec;

/** Typed carrier for `(*exec.Cmd).Output` bytes and error results. */
@:goNative
class CmdOutputResult {
	public var value1(default, null):go.NativeSlice<go.NativeByte>;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:go.NativeSlice<go.NativeByte>, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
