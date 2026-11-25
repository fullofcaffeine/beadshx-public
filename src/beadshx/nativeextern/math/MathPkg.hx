package beadshx.nativeextern.math;

/** Exact standard-library integer limits. */
@:go.import("math")
@:go.package("math")
@:goNative
extern class MathPkg {
	/** `math.MaxUint32`, the largest Go `uint32`, which does not fit a Haxe Int. */
	@:go.name("MaxUint32") public static var maxUint32(default, never):go.NativeUint32;
}
