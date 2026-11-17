package beadshx.nativeextern.bytes;

/** A native buffer owns the byte storage passed to encoding/json without a Haxe array conversion. */
@:go.import("bytes")
@:go.package("bytes")
@:go.name("Buffer")
@:go.struct
@:goNative
extern class Buffer {
	public function new();
	@:go.name("Bytes") public function bytes():go.NativeSlice<go.NativeByte>;
	@:go.name("String") public function stringValue():String;
}
