import go.Result;

/**
 * Models one narrow, typed native parsing boundary.
 *
 * Why: the dependency inventory needs one complete Haxe-to-Go tracer before
 * broader storage and lifecycle facades exist. What: this extern binds one
 * stable Go function and converts `(int, error)` into `Result<Int>`. How:
 * haxe.go emits the import and value-error adapter from typed metadata.
 */
@:go.import("strconv")
extern class NativeNumberFacade {
	@:go.name("Atoi")
	@:go.valueError
	public static function parse(value:String):Result<Int>;
}

/** Proves typed native success and error outcomes at runtime. */
@:goNative
class Main {
	static function main():Void {
		final valid = NativeNumberFacade.parse("42");
		final invalid = NativeNumberFacade.parse("not-a-number");
		Sys.println('value=${valid.unwrap()}');
		Sys.println('invalid=${invalid.isErr()}');
	}
}
