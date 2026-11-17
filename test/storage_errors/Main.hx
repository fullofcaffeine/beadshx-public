import beadshx.store.DatabaseErrors.isTableNotExist;
import go.NativeError;

@:go.import("github.com/go-sql-driver/mysql") @:go.name("MySQLError") @:go.struct
extern class TestMySqlError {
	public function new();
	@:go.name("Number") public var number:Int;
	@:go.name("Message") public var message:String;
}

@:go.import("errors")
extern class TestErrors {
	@:go.name("New") public static function create(message:String):NativeError;
}

@:go.import("fmt")
extern class TestFormat {
	@:go.name("Errorf") public static function wrapMysql(format:String, error:TestMySqlError):NativeError;
	@:go.name("Errorf") public static function wrapError(format:String, error:NativeError):NativeError;
}

/** Independent classification contract; all errors are synthetic and no database opens. */
@:goNative
class Main {
	static function main():Void {
		check(null, false, "nil");
		for (message in [
			"table 'issues' doesn't exist",
			"TABLE `issues` DOES NOT EXIST",
			"read: Table 'db.issues' Doesn't Exist",
			"error 1146"
		]) {
			check(TestErrors.create(message), true, message);
			check(TestFormat.wrapError("context: %w", TestErrors.create(message)), message != "TABLE `issues` DOES NOT EXIST", "wrapped " + message);
		}
		for (message in [
			"column 'id' doesn't exist",
			"schema 'db' does not exist",
			"connection refused",
			"prefix table issues does not exist",
			"table 'issues' does not existence"
		])
			check(TestErrors.create(message), false, message);
		final missing = new TestMySqlError();
		missing.number = 1146;
		missing.message = "opaque driver detail";
		check(TestFormat.wrapMysql("%w", missing), true, "typed code");
		check(TestFormat.wrapError("outer: %w", TestFormat.wrapMysql("inner: %w", missing)), true, "nested typed code");
		final other = new TestMySqlError();
		other.number = 1105;
		other.message = "error 1146: table 'issues' does not exist";
		check(TestFormat.wrapMysql("%w", other), false, "typed code wins over misleading text");
		Sys.println("Haxe database error classification: PASS");
	}

	static function check(error:NativeError, expected:Bool, label:String):Void {
		if (isTableNotExist(error) != expected)
			throw 'classification mismatch: $label';
	}
}
