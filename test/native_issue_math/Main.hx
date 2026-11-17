import beadshx.store.JsonInteger;
import beadshx.store.NativeIssueMath.comparePriorityMerged;
import beadshx.store.NativeIssueMath.compactionSavingsLine;
import beadshx.store.NativeIssueMath.parseSigned64;
import beadshx.store.NativeIssueMath.CompactionSavingsInput;
import beadshx.store.StoreResult;
import haxe.Int64;

class Main {
	static function integer(text:String):JsonInteger {
		return switch JsonInteger.parse(text) {
			case Success(value): value;
			case Failure(message): throw message;
		};
	}

	static function expectString(name:String, result:StoreResult<String>, expected:String):Void {
		switch result {
			case Success(actual):
				if (actual != expected)
					throw '$name: expected $expected, received $actual';
			case Failure(message):
				throw '$name: unexpected failure $message';
		}
	}

	static function expectSavings(name:String, input:CompactionSavingsInput, expected:String):Void {
		expectString(name, compactionSavingsLine(input), expected);
	}

	static function expectComparison(name:String, left:String, right:String, expected:Int):Void {
		switch comparePriorityMerged(integer(left), integer(right)) {
			case Success(actual):
				if (actual != expected)
					throw '$name: expected $expected, received $actual';
			case Failure(message):
				throw '$name: unexpected failure $message';
		}
	}

	static function expectRejected(name:String, text:String):Void {
		switch parseSigned64(integer(text)) {
			case Success(value):
				throw '$name: unexpectedly parsed ${Int64.toStr(value)}';
			case Failure(_):
		}
	}

	static function main():Void {
		for (pair in [
			["0", "0"],
			["-0", "0"],
			["9223372036854775807", "9223372036854775807"],
			["-9223372036854775808", "-9223372036854775808"]
		]) {
			switch parseSigned64(integer(pair[0])) {
				case Success(value):
					if (Int64.toStr(value) != pair[1])
						throw 'parse ${pair[0]}';
				case Failure(message):
					throw message;
			}
		}
		expectRejected("positive overflow", "9223372036854775808");
		expectRejected("negative overflow", "-9223372036854775809");
		expectRejected("unbounded integer", "123456789012345678901234567890");
		expectComparison("ordinary ascending", "0", "4", -1);
		expectComparison("ordinary descending", "4", "0", 1);
		expectComparison("equal negative zero", "-0", "0", 0);
		expectComparison("wrapped maximum minus minimum", "9223372036854775807", "-9223372036854775808", -1);
		expectComparison("wrapped minimum minus maximum", "-9223372036854775808", "9223372036854775807", 1);

		expectSavings("not compacted", {
			level: integer("0"),
			original: integer("200"),
			description: "",
			design: "",
			notes: "",
			acceptance: ""
		}, "");
		expectSavings("zero original", {
			level: integer("1"),
			original: integer("0"),
			description: "",
			design: "",
			notes: "",
			acceptance: ""
		}, "");
		expectSavings("negative original", {
			level: integer("1"),
			original: integer("-1"),
			description: "",
			design: "",
			notes: "",
			acceptance: ""
		}, "");
		expectSavings("no savings", {
			level: integer("1"),
			original: integer("2"),
			description: "é",
			design: "",
			notes: "",
			acceptance: ""
		}, "");
		expectSavings("negative savings", {
			level: integer("1"),
			original: integer("1"),
			description: "é",
			design: "",
			notes: "",
			acceptance: ""
		}, "");
		expectSavings("negative level still counts", {
			level: integer("-1"),
			original: integer("200"),
			description: "",
			design: "",
			notes: "",
			acceptance: ""
		}, "📊 200 → 0 bytes (100% reduction)");
		expectSavings("description bytes", {
			level: integer("1"),
			original: integer("4"),
			description: "é",
			design: "",
			notes: "",
			acceptance: ""
		}, "📊 4 → 2 bytes (50% reduction)");
		expectSavings("design bytes", {
			level: integer("1"),
			original: integer("4"),
			description: "",
			design: "é",
			notes: "",
			acceptance: ""
		}, "📊 4 → 2 bytes (50% reduction)");
		expectSavings("notes bytes", {
			level: integer("1"),
			original: integer("4"),
			description: "",
			design: "",
			notes: "é",
			acceptance: ""
		}, "📊 4 → 2 bytes (50% reduction)");
		expectSavings("acceptance bytes", {
			level: integer("1"),
			original: integer("4"),
			description: "",
			design: "",
			notes: "",
			acceptance: "é"
		}, "📊 4 → 2 bytes (50% reduction)");
		expectSavings("half percent down", {
			level: integer("1"),
			original: integer("200"),
			description: StringTools.rpad("", "x", 199),
			design: "",
			notes: "",
			acceptance: ""
		}, "📊 200 → 199 bytes (0% reduction)");
		expectSavings("half percent up", {
			level: integer("1"),
			original: integer("200"),
			description: StringTools.rpad("", "x", 197),
			design: "",
			notes: "",
			acceptance: ""
		}, "📊 200 → 197 bytes (2% reduction)");
		expectSavings("exact wide decimal", {
			level: integer("1"),
			original: integer("9007199254740993"),
			description: "x",
			design: "",
			notes: "",
			acceptance: ""
		}, "📊 9007199254740993 → 1 bytes (100% reduction)");
		Sys.println("Native issue math: PASS");
	}
}
