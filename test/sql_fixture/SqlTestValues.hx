/**
	Lossless test-only SQL values; null means SQL NULL, strings retain every byte.
	The class owns the explicit goNative boundary required for native driver values.
 */
@:goNative
class SqlTestValues {
	public static function fromStrings(values:Array<Null<String>>):Array<DriverValue> {
		return [for (raw in values) fromString(raw)];
	}

	static function fromString(raw:Null<String>):DriverValue {
		final cell = new NullableText();
		cell.valid = raw != null;
		if (raw != null)
			cell.text = raw;
		final result = cell.value();
		if (result.error != null)
			throw result.error.text();
		return result.value;
	}
}

/** Go's named empty interface carries only values checked by sql.NullString.Value. */
@:go.import("database/sql/driver") @:go.package("driver") @:go.name("Value")
extern interface DriverValue {}

/** Exported standard-library conversion avoids CSV trimming and NULL sentinels. */
@:go.import("database/sql") @:go.package("sql") @:go.name("NullString") @:go.struct
private extern class NullableText {
	public function new();
	@:go.name("String") public var text:String;
	@:go.name("Valid") public var valid:Bool;
	@:go.name("Value") @:go.tupleReturn @:go.tupleValueResults("0") public function value():ValueResult;
}

private class ValueResult {
	public final value:DriverValue;
	public final error:go.NativeError;

	public function new(value:DriverValue, error:go.NativeError) {
		this.value = value;
		this.error = error;
	}
}
