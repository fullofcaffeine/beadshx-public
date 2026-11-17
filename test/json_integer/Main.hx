import beadshx.store.JsonInteger;

/** Independent JSON integer grammar checks; wide values must retain exact bytes. */
class Main {
	static function main():Void {
		for (raw in [
			"0",
			"-0",
			"1",
			"-1",
			"9007199254740993",
			"9223372036854775807",
			"-9223372036854775808"
		])
			switch JsonInteger.parse(raw) {
				case Success(value):
					if (value.wireValue() != raw)
						throw 'integer spelling changed: $raw';
				case Failure(message):
					throw 'valid JSON integer rejected: $raw: $message';
			}
		for (raw in ["00", "01", "-00", "-01", "", "-", "+1", " 1", "1 ", "1.0", "1e2", "1a", "١"])
			switch JsonInteger.parse(raw) {
				case Success(_):
					throw 'invalid JSON integer accepted: $raw';
				case Failure(_):
			}
		for (test in [
			{left: "-0", right: "0", order: 0},
			{left: "0", right: "-0", order: 0},
			{left: "-1", right: "0", order: -1},
			{left: "1", right: "-1", order: 1},
			{left: "9", right: "10", order: -1},
			{left: "-9", right: "-10", order: 1},
			{left: "9007199254740993", right: "9007199254740992", order: 1},
			{left: "-9223372036854775808", right: "-9223372036854775807", order: -1}
		]) {
			final left = requireInteger(test.left);
			final right = requireInteger(test.right);
			if (left.compare(right) != test.order || right.compare(left) != -test.order)
				throw 'exact comparison failed: ${test.left}, ${test.right}';
		}
		if (JsonInteger.fromInt(-17).wireValue() != "-17")
			throw "typed source integer conversion changed";
		Sys.println("JSON integer boundary: PASS");
	}

	static function requireInteger(raw:String):JsonInteger {
		return switch JsonInteger.parse(raw) {
			case Success(value): value;
			case Failure(message): throw message;
		};
	}
}
