package beadshx.nativeextern.bytes;

/** Exact standard-library construction keeps a native string-to-byte conversion inside bytes. */
@:go.import("bytes")
@:go.package("bytes")
extern class BytesPkg {
	@:go.name("NewBufferString") public static function newBufferString(raw:String):Buffer;
}
