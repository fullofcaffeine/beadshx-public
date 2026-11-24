package beadshx.nativeextern.errors;

/** Standard-library matching retains wrapped causes and custom Go error matching. */
@:go.import("errors")
extern class Errors {
	@:go.name("AsType")
	@:go.tupleReturn
	public static function asType<T>(error:go.NativeError):ErrorMatch<T>;

	/** `errors.Is`: whether `error` or an error it wraps matches `target`. */
	@:go.name("Is")
	public static function matches(error:go.NativeError, target:go.NativeError):Bool;
}

/** The bool distinguishes a matched typed nil from an unmatched error. */
@:goNative
class ErrorMatch<T> {
	public final value:T;
	public final matched:Bool;

	public function new(value:T, matched:Bool) {
		this.value = value;
		this.matched = matched;
	}
}
