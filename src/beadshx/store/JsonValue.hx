package beadshx.store;

import haxe.Json;

private typedef JsonField = {
	final key:String;
	final value:ParsedJsonValue;
	final raw:String;
}

private enum ParsedJsonValue {
	ObjectValue(fields:Array<JsonField>);
	ArrayValue(values:Array<ParsedJsonValue>);
	StringValue(value:String);
	NumberValue(token:String);
	BooleanValue(value:Bool);
	NullValue;
}

private enum JsonParseResult {
	Parsed(value:ParsedJsonValue);
	Invalid;
}

/**
	A validated JSON value copied from the native metadata boundary.

	The Go facade rejects invalid bytes with encoding/json before it exposes this
	value. Keeping the constructor here avoids parsing into Dynamic in domain code
	while still preserving arbitrary compatibility metadata byte for byte.
**/
abstract JsonValue(String) {
	private inline function new(value:String) {
		this = value;
	}

	public static inline function fromValidatedNative(value:String):JsonValue {
		return new JsonValue(value);
	}

	/** Validates arbitrary JSON before it enters Haxe-owned domain values. */
	public static function parse(raw:String, context:String):StoreResult<JsonValue> {
		final value = StringTools.trim(raw);
		return switch new TypedJsonParser(value).parse() {
			case Parsed(_): Success(new JsonValue(value));
			case Invalid: Failure('$context contains invalid JSON');
		};
	}

	/** Decodes a JSON string array without exposing an untyped JSON shape. */
	public static function parseStringArray(raw:String, context:String):StoreResult<Array<String>> {
		if (StringTools.trim(raw) == "")
			return Success([]);
		return switch new TypedJsonParser(StringTools.trim(raw)).parse() {
			case Parsed(ArrayValue(values)):
				final strings = new Array<String>();
				for (value in values)
					switch value {
						case StringValue(text): strings.push(text);
						case _: return Failure('$context must be a JSON string array');
					}
				Success(strings);
			case Parsed(_): Failure('$context must be a JSON string array');
			case Invalid: Failure('$context contains invalid JSON');
		};
	}

	public inline function isAbsent():Bool {
		return this == "";
	}

	public inline function wireValue():String {
		return this;
	}

	/** Reads one string field from untrusted JSON without exposing Dynamic. */
	public static function rawTopLevelStringEquals(raw:String, key:String, expected:String):Bool {
		return switch new TypedJsonParser(StringTools.trim(raw)).parse() {
			case Parsed(ObjectValue(fields)): final field = findField(fields, key); field != null && switch field.value {
					case StringValue(value): value == expected;
					case _: false;
				};
			case Parsed(_) | Invalid: false;
		};
	}

	/** Returns one decoded top-level string without exposing the parsed JSON shape. */
	public static function rawTopLevelString(raw:String, key:String):Null<String> {
		return switch new TypedJsonParser(StringTools.trim(raw)).parse() {
			case Parsed(ObjectValue(fields)):
				final field = findField(fields, key);
				field == null ? null : switch field.value {
					case StringValue(value): value;
					case _: null;
				};
			case Parsed(_) | Invalid: null;
		};
	}

	/**
		Formats the top-level metadata object for human `show` output.

		Why: public metadata can contain arbitrary validated JSON, but untyped JSON
		must not enter command policy. What: keys are sorted and nested values are
		compacted like the pinned Go formatter. How: a small recursive parser keeps
		the value typed after the native boundary has validated its syntax.
	**/
	public function renderHumanLines():Array<String> {
		final trimmed = StringTools.trim(this);
		if (trimmed == "" || trimmed == "{}" || trimmed == "null")
			return [];
		return switch new TypedJsonParser(trimmed).parse() {
			case Parsed(ObjectValue(fields)):
				fields.sort(compareFields);
				[for (field in fields) '  ${field.key}: ${renderHumanValue(field.value)}'];
			case Parsed(_): ["  " + trimmed];
			case Invalid: ["  " + trimmed];
		};
	}

	/** Formats validated JSON with the same two-space structural layout as Go. */
	public function renderIndented(baseIndent:String, indentUnit:String):String {
		final output = new StringBuf();
		var depth = 0;
		var inString = false;
		var escaped = false;
		var index = 0;
		while (index < this.length) {
			final character = this.charAt(index);
			if (inString) {
				output.add(character);
				if (escaped)
					escaped = false;
				else if (character == "\\")
					escaped = true;
				else if (character == '"')
					inString = false;
				index++;
				continue;
			}
			switch character {
				case '"':
					inString = true;
					output.add(character);
				case "{" | "[":
					output.add(character);
					final close = character == "{" ? "}" : "]";
					if (nextSignificant(index + 1) != close) {
						depth++;
						addLineIndent(output, baseIndent, indentUnit, depth);
					}
				case "}" | "]":
					final open = character == "}" ? "{" : "[";
					if (previousSignificant(index - 1) != open) {
						depth--;
						addLineIndent(output, baseIndent, indentUnit, depth);
					}
					output.add(character);
				case ",":
					output.add(character);
					addLineIndent(output, baseIndent, indentUnit, depth);
				case ":":
					output.add(": ");
				case " " | "\t" | "\r" | "\n":
				case _:
					output.add(character);
			}
			index++;
		}
		return output.toString();
	}

	/** Formats validated JSON after recursively sorting object keys. */
	public function renderSortedIndented(baseIndent:String, indentUnit:String):String {
		return switch new TypedJsonParser(StringTools.trim(this)).parse() {
			case Parsed(value): renderPrettySorted(value, baseIndent, indentUnit, 0);
			case Invalid: renderIndented(baseIndent, indentUnit);
		};
	}

	/** Counts top-level object fields without exposing the parsed JSON shape. */
	public function topLevelFieldCount():Int {
		return switch new TypedJsonParser(StringTools.trim(this)).parse() {
			case Parsed(ObjectValue(fields)): fields.length;
			case Parsed(_) | Invalid: 0;
		};
	}

	/** Reports whether validated metadata owns one exact top-level key. */
	public function hasTopLevelKey(key:String):Bool {
		return switch new TypedJsonParser(StringTools.trim(this)).parse() {
			case Parsed(ObjectValue(fields)): findField(fields, key) != null;
			case Parsed(_) | Invalid: false;
		};
	}

	/**
		Applies the pinned query comparison to one top-level metadata value.

		JSON strings compare by their decoded text. Other JSON values compare by
		their original token spelling, which preserves the upstream RawMessage
		contract without exposing an untyped JSON object to query policy.
	**/
	public function topLevelQueryEquals(key:String, expected:String):Bool {
		return switch new TypedJsonParser(StringTools.trim(this)).parse() {
			case Parsed(ObjectValue(fields)):
				final field = findField(fields, key);
				if (field == null) false; else switch field.value {
					case StringValue(value): value == expected;
					case _: trimQuotes(field.raw) == expected;
				}
			case Parsed(_) | Invalid: false;
		};
	}

	function nextSignificant(start:Int):String {
		var index = start;
		while (index < this.length) {
			final character = this.charAt(index);
			if (character != " " && character != "\t" && character != "\r" && character != "\n")
				return character;
			index++;
		}
		return "";
	}

	function previousSignificant(start:Int):String {
		var index = start;
		while (index >= 0) {
			final character = this.charAt(index);
			if (character != " " && character != "\t" && character != "\r" && character != "\n")
				return character;
			index--;
		}
		return "";
	}

	static function addLineIndent(output:StringBuf, baseIndent:String, indentUnit:String, depth:Int):Void {
		output.add("\n");
		output.add(baseIndent);
		for (_ in 0...depth)
			output.add(indentUnit);
	}

	static function compareFields(left:JsonField, right:JsonField):Int {
		return left.key < right.key ? -1 : left.key == right.key ? 0 : 1;
	}

	static function findField(fields:Array<JsonField>, key:String):Null<JsonField> {
		for (field in fields)
			if (field.key == key)
				return field;
		return null;
	}

	static function trimQuotes(value:String):String {
		var start = 0;
		var end = value.length;
		while (start < end && value.charAt(start) == '"')
			start++;
		while (end > start && value.charAt(end - 1) == '"')
			end--;
		return value.substring(start, end);
	}

	static function renderHumanValue(value:ParsedJsonValue):String {
		return switch value {
			case StringValue(text): text;
			case NumberValue(token): token;
			case BooleanValue(flag): flag ? "true" : "false";
			case NullValue: "null";
			case ObjectValue(_) | ArrayValue(_): renderCompact(value);
		};
	}

	static function renderCompact(value:ParsedJsonValue):String {
		return switch value {
			case ObjectValue(fields):
				fields.sort(compareFields);
				"{" + [
					for (field in fields)
						Json.stringify(field.key) + ":" + renderCompact(field.value)
				].join(",") + "}";
			case ArrayValue(values): "[" + [for (item in values) renderCompact(item)].join(",") + "]";
			case StringValue(text): Json.stringify(text);
			case NumberValue(token): token;
			case BooleanValue(flag): flag ? "true" : "false";
			case NullValue: "null";
		};
	}

	static function renderPrettySorted(value:ParsedJsonValue, baseIndent:String, indentUnit:String, depth:Int):String {
		return switch value {
			case ObjectValue(fields):
				fields.sort(compareFields);
				if (fields.length == 0) "{}"; else {
					final lines = ["{"];
					for (index in 0...fields.length) {
						final field = fields[index];
						final suffix = index == fields.length - 1 ? "" : ",";
						lines.push(indent(baseIndent, indentUnit, depth + 1)
							+ Json.stringify(field.key)
							+ ": "
							+ renderPrettySorted(field.value, baseIndent, indentUnit, depth + 1)
							+ suffix);
					}
					lines.push(indent(baseIndent, indentUnit, depth) + "}");
					lines.join("\n");
				}
			case ArrayValue(values):
				if (values.length == 0) "[]"; else {
					final lines = ["["];
					for (index in 0...values.length) {
						final suffix = index == values.length - 1 ? "" : ",";
						lines.push(indent(baseIndent, indentUnit, depth + 1) + renderPrettySorted(values[index], baseIndent, indentUnit, depth + 1) + suffix);
					}
					lines.push(indent(baseIndent, indentUnit, depth) + "]");
					lines.join("\n");
				}
			case StringValue(text): Json.stringify(text);
			case NumberValue(token): token;
			case BooleanValue(flag): flag ? "true" : "false";
			case NullValue: "null";
		};
	}

	static function indent(baseIndent:String, indentUnit:String, depth:Int):String {
		var value = baseIndent;
		for (_ in 0...depth)
			value += indentUnit;
		return value;
	}
}

/** Typed parser for JSON that has already passed native syntax validation. */
private final class TypedJsonParser {
	final source:String;
	var index = 0;
	var failed = false;

	public function new(source:String) {
		this.source = source;
	}

	public function parse():JsonParseResult {
		final value = parseValue();
		skipWhitespace();
		return failed || index != source.length ? Invalid : Parsed(value);
	}

	function parseValue():ParsedJsonValue {
		skipWhitespace();
		if (index >= source.length) {
			failed = true;
			return NullValue;
		}
		return switch source.charAt(index) {
			case "{": parseObject();
			case "[": parseArray();
			case '"': StringValue(parseString());
			case "t": consumeLiteral("true", BooleanValue(true));
			case "f": consumeLiteral("false", BooleanValue(false));
			case "n": consumeLiteral("null", NullValue);
			case _: parseNumber();
		};
	}

	function parseObject():ParsedJsonValue {
		index++;
		final fields = new Array<JsonField>();
		skipWhitespace();
		if (consumeIf("}"))
			return ObjectValue(fields);
		while (!failed) {
			skipWhitespace();
			if (!consumeIf('"')) {
				failed = true;
				break;
			}
			index--;
			final key = parseString();
			skipWhitespace();
			if (!consumeIf(":")) {
				failed = true;
				break;
			}
			skipWhitespace();
			final valueStart = index;
			final value = parseValue();
			final raw = source.substring(valueStart, index);
			var replaced = false;
			for (fieldIndex in 0...fields.length) {
				if (fields[fieldIndex].key == key) {
					fields[fieldIndex] = {key: key, value: value, raw: raw};
					replaced = true;
					break;
				}
			}
			if (!replaced)
				fields.push({key: key, value: value, raw: raw});
			skipWhitespace();
			if (consumeIf("}"))
				break;
			if (!consumeIf(",")) {
				failed = true;
				break;
			}
		}
		return ObjectValue(fields);
	}

	function parseArray():ParsedJsonValue {
		index++;
		final values = new Array<ParsedJsonValue>();
		skipWhitespace();
		if (consumeIf("]"))
			return ArrayValue(values);
		while (!failed) {
			values.push(parseValue());
			skipWhitespace();
			if (consumeIf("]"))
				break;
			if (!consumeIf(",")) {
				failed = true;
				break;
			}
		}
		return ArrayValue(values);
	}

	function parseString():String {
		if (!consumeIf('"')) {
			failed = true;
			return "";
		}
		final output = new StringBuf();
		while (index < source.length) {
			final character = source.charAt(index++);
			if (character == '"')
				return output.toString();
			if (character != "\\") {
				output.add(character);
				continue;
			}
			if (index >= source.length)
				break;
			final escape = source.charAt(index++);
			switch escape {
				case '"' | "\\" | "/":
					output.add(escape);
				case "b":
					output.add(String.fromCharCode(8));
				case "f":
					output.add(String.fromCharCode(12));
				case "n":
					output.add("\n");
				case "r":
					output.add("\r");
				case "t":
					output.add("\t");
				case "u":
					final code = parseHexCodeUnit();
					if (code >= 0)
						output.add(String.fromCharCode(code));
				case _:
					failed = true;
					return output.toString();
			}
		}
		failed = true;
		return output.toString();
	}

	function parseHexCodeUnit():Int {
		if (index + 4 > source.length) {
			failed = true;
			return -1;
		}
		var value = 0;
		for (_ in 0...4) {
			final code = source.charCodeAt(index++);
			final digit = code >= 48
				&& code <= 57 ? code - 48 : code >= 65 && code <= 70 ? code - 55 : code >= 97 && code <= 102 ? code - 87 : -1;
			if (digit < 0) {
				failed = true;
				return -1;
			}
			value = value * 16 + digit;
		}
		return value;
	}

	function parseNumber():ParsedJsonValue {
		final start = index;
		while (index < source.length) {
			final character = source.charAt(index);
			if (character == "," || character == "]" || character == "}" || isWhitespace(character))
				break;
			index++;
		}
		if (start == index)
			failed = true;
		return NumberValue(source.substring(start, index));
	}

	function consumeLiteral(token:String, value:ParsedJsonValue):ParsedJsonValue {
		if (source.substr(index, token.length) != token)
			failed = true;
		else
			index += token.length;
		return value;
	}

	function consumeIf(character:String):Bool {
		if (index >= source.length || source.charAt(index) != character)
			return false;
		index++;
		return true;
	}

	function skipWhitespace():Void {
		while (index < source.length && isWhitespace(source.charAt(index)))
			index++;
	}

	static function isWhitespace(character:String):Bool {
		return character == " " || character == "\t" || character == "\r" || character == "\n";
	}
}
