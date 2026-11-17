package beadshx.nativeextern.errors;

/** Standard-library matching retains wrapped causes and custom Go error matching. */
@:go.import("errors")
extern class Errors {
	@:go.name("AsType")
	@:go.tupleReturn
	public static function asType<T>(error:go.NativeError):ErrorMatch<T>;
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
