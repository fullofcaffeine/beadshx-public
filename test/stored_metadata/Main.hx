import beadshx.store.StoredMetadata;
import beadshx.store.JsonValue;

/** Expectations come from pinned ScanIssueFrom, not the JSON parser's normalization. */
@:access(beadshx.store.StoredMetadata)
class Main {
	static function main():Void {
		outputParserMismatchContract();
		humanObservationContracts();
		controlCharacterContracts();
		unicodeEscapeContracts();
		waiterWhitespaceContracts();
		for (raw in [null, "", "{}"]) {
			final metadata = StoredMetadata.fromSql(raw);
			if (!metadata.isAbsent() || metadata.wireValue() != "")
				throw "SQL omission contract differs";
			switch metadata.toJsonValue("fixture metadata") {
				case Success(value):
					if (!value.isAbsent())
						throw "omitted metadata became present";
				case Failure(message):
					throw message;
			}
		}
		for (testCase in [
			{raw: " { } ", validated: "{ }"},
			{raw: "null", validated: "null"},
			{raw: "42", validated: "42"},
			{raw: "-0", validated: "-0"},
			{raw: "1.50", validated: "1.50"},
			{raw: "1e3", validated: "1e3"},
			{raw: "-2.5E+10", validated: "-2.5E+10"},
			{raw: "1e-9999", validated: "1e-9999"},
			{raw: "90071992547409931234567890", validated: "90071992547409931234567890"},
			{raw: '"text"', validated: '"text"'},
			{raw: "false", validated: "false"},
			{raw: "[1,true,null]", validated: "[1,true,null]"}
		]) {
			final metadata = StoredMetadata.fromSql(testCase.raw);
			assertRetained(metadata, testCase.raw);
			switch metadata.toJsonValue("fixture metadata") {
				case Success(value):
					if (value.wireValue() != testCase.validated || value.isAbsent())
						throw "validated metadata value differs";
				case Failure(message):
					throw message;
			}
			assertRetained(metadata, testCase.raw);
		}
		for (raw in [
			"{",
			"oops",
			"   ",
			"NaN",
			"Infinity",
			"+1",
			"01",
			"1.",
			".1",
			"1e",
			"--1",
			"-",
			"1e+",
			"-01",
			"[01]",
			'{"x":NaN}'
		]) {
			final metadata = StoredMetadata.fromSql(raw);
			assertRetained(metadata, raw);
			switch metadata.toJsonValue("fixture metadata") {
				case Success(_):
					throw 'malformed stored metadata entered validated JSON: $raw';
				case Failure(message):
					if (message != "fixture metadata contains invalid JSON")
						throw "validation failure context differs";
			}
			assertRetained(metadata, raw);
		}
		Sys.println("stored metadata Haxe contracts: PASS");
	}

	/** Pinned ParseJSONStringArray rejects VT/FF around otherwise valid arrays. */
	static function waiterWhitespaceContracts():Void {
		final vt = String.fromCharCode(11);
		final ff = String.fromCharCode(12);
		final failures = new Array<String>();
		for (testCase in [
			{name: "leading VT", raw: vt + '["a"]'},
			{name: "trailing VT", raw: '["a"]' + vt},
			{name: "both VT", raw: vt + '["a"]' + vt},
			{name: "leading FF", raw: ff + '["a"]'},
			{name: "trailing FF", raw: '["a"]' + ff},
			{name: "both FF", raw: ff + '["a"]' + ff},
			{name: "wrapped null element", raw: vt + '[null,"a"]' + ff},
			{name: "mixed outer whitespace", raw: " \t" + vt + '["a"]\r\n'},
			{name: "inner VT", raw: '[' + vt + '"a"]'},
			{name: "inner FF", raw: '["a",' + ff + '"b"]'},
			{name: "number element", raw: '["a",1]'},
			{name: "boolean element", raw: '[true,"a"]'},
			{name: "object element", raw: '["a",{}]'},
			{name: "nested array", raw: '[["a"]]'},
			{name: "null then number", raw: '[null,"a",1]'},
			{name: "whole null fallback", raw: "null"}
		]) {
			switch JsonValue.parseStringArrayNullAsEmpty(testCase.raw, "issue waiters") {
				case Success(_):
					failures.push(testCase.name);
				case Failure(_):
			}
		}
		for (testCase in [
			{raw: '["a","b"]', expected: ["a", "b"]},
			{raw: " \t\r\n[\"a\"]\t\r\n ", expected: ["a"]},
			{raw: '[null,"a"]', expected: ["", "a"]},
			{raw: '[null,null]', expected: ["", ""]},
			{raw: '[""]', expected: [""]},
			{raw: '["\\u000b"]', expected: [vt]},
			{raw: '["\\u000c"]', expected: [ff]},
			{raw: "[]", expected: []},
			{raw: "", expected: []},
			{raw: " \t\r\n", expected: []}
		]) {
			switch JsonValue.parseStringArrayNullAsEmpty(testCase.raw, "issue waiters") {
				case Failure(message):
					throw message;
				case Success(values):
					if (values.length != testCase.expected.length)
						throw "waiter array control length differs";
					for (index in 0...values.length)
						if (values[index] != testCase.expected[index])
							throw "waiter array control value differs";
			}
		}
		switch JsonValue.parseStringArray('[null,"a"]', "strict strings") {
			case Success(_):
				throw "strict string arrays accepted a null element";
			case Failure(_):
		}
		if (failures.length != 0)
			throw "waiter JSON whitespace contract differs: " + failures.join(", ");
	}

	/** A rejected parser result after native acceptance must remain a visible output failure. */
	static function outputParserMismatchContract():Void {
		switch StoredMetadata.requireOutputParser(Failure("synthetic typed-parser rejection")) {
			case Failure(message):
				if (message != "metadata JSON is valid for Go but unsupported by the Haxe parser")
					throw "native/typed parser mismatch was mislabeled";
			case Success(_):
				throw "native acceptance hid a typed-parser mismatch";
		}
		final original = JsonValue.fromValidatedNative('{"x":true}');
		switch StoredMetadata.requireOutputParser(Success(original)) {
			case Success(value):
				if (value.wireValue() != original.wireValue())
					throw "accepted output metadata changed";
			case Failure(message):
				throw message;
		}
	}

	static function humanObservationContracts():Void {
		for (testCase in [
			{
				raw: "{",
				human: "  {",
				present: true,
				count: 0
			},
			{
				raw: " \t\r\n",
				human: "  ",
				present: true,
				count: 0
			},
			{
				raw: " null ",
				human: "",
				present: false,
				count: 0
			},
			{
				raw: " { } ",
				human: "",
				present: true,
				count: 0
			},
			{
				raw: " {} ",
				human: "",
				present: false,
				count: 0
			},
			{
				raw: '{"b":true,"a":1}',
				human: "  a: 1\n  b: true",
				present: true,
				count: 2
			}
		]) {
			final metadata = StoredMetadata.fromSql(testCase.raw);
			if (metadata.renderHumanLines().join("\n") != testCase.human
				|| metadata.hasHumanValue() != testCase.present
				|| metadata.topLevelFieldCount() != testCase.count)
				throw "human metadata observation differs";
			assertRetained(metadata, testCase.raw);
		}
	}

	static function controlCharacterContracts():Void {
		final failures = new Array<String>();
		for (testCase in [
			{name: "raw newline", raw: '"a\nb"', valid: false},
			{name: "raw tab", raw: '"a\tb"', valid: false},
			{name: "raw NUL", raw: '"a' + String.fromCharCode(0) + 'b"', valid: false},
			{name: "escaped newline", raw: '"a\\nb"', valid: true},
			{name: "escaped tab", raw: '"a\\tb"', valid: true},
			{name: "escaped NUL", raw: '"a\\u0000b"', valid: true},
			{name: "outer VT", raw: String.fromCharCode(11) + "{}" + String.fromCharCode(11), valid: false},
			{name: "outer FF", raw: String.fromCharCode(12) + "{}" + String.fromCharCode(12), valid: false},
			{name: "JSON whitespace", raw: " \t\r\n{} \t\r\n", valid: true}
		]) {
			final metadata = StoredMetadata.fromSql(testCase.raw);
			final accepted = switch metadata.toJsonValue("fixture metadata") {
				case Success(_): true;
				case Failure(_): false;
			};
			if (accepted != testCase.valid)
				failures.push(testCase.name);
			assertRetained(metadata, testCase.raw);
		}
		if (failures.length != 0)
			throw "JSON control character contract differs: " + failures.join(", ");
	}

	static function assertRetained(metadata:StoredMetadata, expected:String):Void {
		if (metadata.isAbsent() || metadata.wireValue() != expected)
			throw "stored metadata bytes or presence changed";
	}

	/** Go encoding/json combines UTF-16 pairs and replaces unpaired surrogate units. */
	static function unicodeEscapeContracts():Void {
		final failures = new Array<String>();
		for (testCase in [
			{name: "surrogate pair", raw: '"\\uD83D\\uDE00"', decoded: "😀"},
			{name: "maximum surrogate pair", raw: '"\\uDBFF\\uDFFF"', decoded: "\u{10FFFF}"},
			{name: "lone high surrogate", raw: '"\\uD83D"', decoded: "�"},
			{name: "lone low surrogate", raw: '"\\uDE00"', decoded: "�"},
			{name: "escaped BMP", raw: '"a\\u00E9\\u20AC"', decoded: "aé€"},
			{name: "literal UTF-8", raw: '"aé€😀"', decoded: "aé€😀"},
			{name: "high then BMP", raw: '"\\uD83D\\u0061"', decoded: "�a"},
			{name: "high then newline", raw: '"\\uD83D\\n"', decoded: "�\n"},
			{name: "reversed surrogates", raw: '"\\uDE00\\uD83D"', decoded: "��"},
			{name: "high then pair", raw: '"\\uD83D\\uD83D\\uDE00"', decoded: "�😀"}
		]) {
			final object = '{"x":' + testCase.raw + '}';
			final metadata = StoredMetadata.fromSql(object);
			assertRetained(metadata, object);
			final value = switch metadata.toJsonValue("fixture metadata") {
				case Success(parsed): parsed;
				case Failure(message): throw message;
			};
			if (JsonValue.rawTopLevelString(object, "x") != testCase.decoded
				|| !value.topLevelQueryEquals("x", testCase.decoded)
				|| !JsonValue.fromValidatedNative('{' + testCase.raw + ':true}').hasTopLevelKey(testCase.decoded))
				failures.push(testCase.name);
			switch JsonValue.parseStringArray('[' + testCase.raw + ']', "fixture strings") {
				case Success(strings):
					if (strings.length != 1 || strings[0] != testCase.decoded)
						failures.push(testCase.name + " array");
				case Failure(message):
					throw message;
			}
			assertRetained(metadata, object);
		}
		for (raw in ['"\\uD83D\\u12"', '"\\uD83D\\uZZZZ"', '"\\uD83D\\q"']) {
			switch JsonValue.parse(raw, "fixture metadata") {
				case Success(_):
					failures.push("malformed following escape");
				case Failure(_):
			}
		}
		if (failures.length != 0)
			throw "JSON Unicode escape contract differs: " + failures.join(", ");
	}
}
