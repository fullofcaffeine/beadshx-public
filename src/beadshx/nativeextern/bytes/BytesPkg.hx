package beadshx.nativeextern.bytes;

/** Exact standard-library construction keeps a native string-to-byte conversion inside bytes. */
@:go.import("bytes")
@:go.package("bytes")
@:goNative
extern class BytesPkg {
	@:go.name("NewBufferString") public static function newBufferString(raw:String):Buffer;

	/** Reads native process output as text without a Haxe byte loop. */
	@:go.name("NewBuffer") public static function newBuffer(raw:go.NativeSlice<go.NativeByte>):Buffer;
}
