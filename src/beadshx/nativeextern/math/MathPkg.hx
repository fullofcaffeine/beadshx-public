package beadshx.nativeextern.math;

/** Exact standard-library integer limits. */
@:go.import("math")
@:go.package("math")
@:goNative
extern class MathPkg {
	/**
		`math.MaxUint32`, an untyped Go constant that does not fit a Haxe Int.
		Pass it only straight to a Go `uint32` parameter.
	**/
	@:go.name("MaxUint32") public static var maxUint32(default, never):Int;
}
