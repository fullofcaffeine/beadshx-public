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
	A validated JSON value used after an explicit JSON consumer boundary.

	StoredMetadata retains raw storage bytes, including malformed JSON. Its strict
	output path validates a copy before using this value; query and human observers
	can inspect raw metadata without rejecting a storage read. The native constructor
	is reserved for callers that already proved JSON validity.
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
		// Validate before trimming so non-JSON whitespace cannot disappear.
		return switch new TypedJsonParser(raw).parse() {
			case Parsed(_): Success(new JsonValue(value));
			case Invalid: Failure('$context contains invalid JSON');
		};
	}

	/** Decodes a JSON string array without exposing an untyped JSON shape. */
	public static function parseStringArray(raw:String, context:String):StoreResult<Array<String>> {
		return decodeStringArray(raw, context, false);
	}

	/** Match Go's `[]string` JSON decoding when a caller opts into null elements as empty strings. */
	public static function parseStringArrayNullAsEmpty(raw:String, context:String):StoreResult<Array<String>> {
		return decodeStringArray(raw, context, true);
	}

	static function decodeStringArray(raw:String, context:String, nullAsEmpty:Bool):StoreResult<Array<String>> {
		if (StringTools.trim(raw) == "")
			return Success([]);
		// Trimming before validation would accept non-JSON whitespace around arrays.
		return switch new TypedJsonParser(raw).parse() {
			case Parsed(ArrayValue(values)):
				final strings = new Array<String>();
				for (value in values)
					switch value {
						case StringValue(text): strings.push(text);
						case NullValue:
							if (!nullAsEmpty)
								return Failure('$context must be a JSON string array');
							strings.push("");
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

		JSON strings compare by their decoded text; null compares as an empty
		string. Other values compare by their original token spelling, preserving RawMessage
		contract without exposing an untyped JSON object to query policy.
	**/
	public function topLevelQueryEquals(key:String, expected:String):Bool {
		return switch new TypedJsonParser(StringTools.trim(this)).parse() {
			case Parsed(ObjectValue(fields)):
				final field = findField(fields, key);
				if (field == null) false; else switch field.value {
					case StringValue(value): value == expected;
					// Go unmarshals JSON null into a string without changing its zero value.
					case NullValue: expected == "";
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

/** The Go type of one struct field that encoding/json fills. */
enum GoJsonFieldKind {
	GoStringField;
	GoIntField;
	GoBoolField;
}

/** One field of a Go struct, named by its JSON tag. */
typedef GoJsonField = {
	final tag:String;
	final kind:GoJsonFieldKind;
}

/** A Go struct type of string, int and bool fields, named as Go's reflect package names it. */
typedef GoJsonStruct = {
	/** The package name, such as `configfile`. */
	final packageName:String;

	/** The type name, such as `Config`. */
	final name:String;

	final fields:Array<GoJsonField>;
}

/** What json.Unmarshal gives for JSON text and one GoJsonStruct. */
enum GoJsonDecode {
	/** The fields as text by tag: an int in decimal, a bool as `true` or `false`. Absent and null members are left out. */
	GoJsonDecoded(fields:Map<String, String>);

	/** The error text that json.Unmarshal returns. */
	GoJsonFailed(message:String);

	/**
		JSON that Go's scanner accepts and the typed parser rejects, which would
		be a parser defect. The interpreter has no Go scanner, so there every
		syntax error lands here.
	**/
	GoJsonUnsupported;
}

/**
	Go's json.Unmarshal into a slice of pointers to `type`, as upstream reads an
	aggregate such as the counts query's deps_json.

	What: one entry per array element, in order, decoded like decodeGoStruct; a
	null element is null, as Go's nil pointer, and a null document is no
	entries. How: the elements decode one by one from their raw text, and the
	first error stops the decode.
**/
function decodeGoStructArray(raw:String, type:GoJsonStruct):StoreResult<Array<Null<Map<String, String>>>> {
	final syntaxError = GoJsonSyntax.syntaxError(raw);
	if (syntaxError != null)
		return Failure(syntaxError);
	final elements = switch new TypedJsonParser(raw, true).parse() {
		case Parsed(ArrayValue(values)): values;
		case Parsed(NullValue): return Success([]);
		case Parsed(value): return Failure('json: cannot unmarshal ${goJsonKind(value)} into Go value of type []*${type.packageName}.${type.name}');
		case Invalid: return Failure('${type.name} array contains invalid JSON');
	};
	final decoded = new Array<Null<Map<String, String>>>();
	for (element in elements) {
		final members = switch element {
			case ObjectValue(members): members;
			case NullValue:
				decoded.push(null);
				continue;
			case value: return Failure('json: cannot unmarshal ${goJsonKind(value)} into Go value of type ${type.packageName}.${type.name}');
		};
		final fields = new Map<String, String>();
		for (member in members) {
			final field = goStructField(type.fields, member.key);
			if (field == null)
				continue;
			switch [field.kind, member.value] {
				case [_, NullValue]:
				case [GoStringField, StringValue(text)]:
					fields.set(field.tag, text);
				case [GoBoolField, BooleanValue(flag)]:
					fields.set(field.tag, flag ? "true" : "false");
				case [GoIntField, NumberValue(token)]:
					final integer = goInt64Text(token);
					if (integer == null)
						return Failure(goFieldTypeError(type, field, 'number ${token}'));
					fields.set(field.tag, integer);
				case [_, value]:
					return Failure(goFieldTypeError(type, field, goJsonKind(value)));
			}
		}
		decoded.push(fields);
	}
	return Success(decoded);
}

/**
	Go's json.Unmarshal into a struct of string, int and bool fields.

	Why: upstream reads .beads/metadata.json into configfile.Config, and any
	decode error rejects the whole file with json.Unmarshal's error text.
	What: the decoded fields, or that error text. How: Go's own scanner
	checks the syntax first, as Unmarshal does, and gives its exact syntax
	error. Then members apply in document order, duplicates included. A key
	matches a tag exactly or under encoding/json's case folding, and unknown
	keys are ignored. The first type mismatch fails, even when a later
	duplicate would fit, because Unmarshal keeps decoding but returns the first
	error it saved. A mismatch names the field by its tag, whatever the key's
	case. An int must be an integer in the int64 range (Go's int is 64 bits on
	every platform this build supports). A null member, or a null document,
	changes nothing.
**/
function decodeGoStruct(raw:String, type:GoJsonStruct):GoJsonDecode {
	final syntaxError = GoJsonSyntax.syntaxError(raw);
	if (syntaxError != null)
		return GoJsonFailed(syntaxError);
	final decoded = new Map<String, String>();
	final members = switch new TypedJsonParser(raw, true).parse() {
		case Parsed(ObjectValue(members)): members;
		case Parsed(NullValue): return GoJsonDecoded(decoded);
		case Parsed(value): return GoJsonFailed('json: cannot unmarshal ${goJsonKind(value)} into Go value of type ${type.packageName}.${type.name}');
		case Invalid: return GoJsonUnsupported;
	};
	for (member in members) {
		final field = goStructField(type.fields, member.key);
		if (field == null)
			continue;
		switch [field.kind, member.value] {
			case [_, NullValue]:
			case [GoStringField, StringValue(text)]:
				decoded.set(field.tag, text);
			case [GoBoolField, BooleanValue(flag)]:
				decoded.set(field.tag, flag ? "true" : "false");
			case [GoIntField, NumberValue(token)]:
				final integer = goInt64Text(token);
				if (integer == null)
					return GoJsonFailed(goFieldTypeError(type, field, 'number ${token}'));
				decoded.set(field.tag, integer);
			case [_, value]:
				return GoJsonFailed(goFieldTypeError(type, field, goJsonKind(value)));
		}
	}
	return GoJsonDecoded(decoded);
}

/** encoding/json's UnmarshalTypeError text for one struct field; `value` is how Go names the JSON value. */
private function goFieldTypeError(type:GoJsonStruct, field:GoJsonField, value:String):String {
	final fieldType = switch field.kind {
		case GoStringField: "string";
		case GoIntField: "int";
		case GoBoolField: "bool";
	};
	return 'json: cannot unmarshal ${value} into Go struct field ${type.name}.${field.tag} of type ${fieldType}';
}

/** How an encoding/json UnmarshalTypeError names a JSON value that does not fit its Go type. */
private function goJsonKind(value:ParsedJsonValue):String {
	return switch value {
		case ObjectValue(_): "object";
		case ArrayValue(_): "array";
		case StringValue(_): "string";
		case NumberValue(_): "number";
		case BooleanValue(_): "bool";
		case NullValue: "null";
	};
}

/** encoding/json's field lookup: an exact tag first, then one equal under its case folding. */
private function goStructField(fields:Array<GoJsonField>, key:String):Null<GoJsonField> {
	for (field in fields)
		if (field.tag == key)
			return field;
	final folded = goFoldedName(key);
	for (field in fields)
		if (goFoldedName(field.tag) == folded)
			return field;
	return null;
}

/**
	encoding/json's foldName: ASCII letters upper-case, and any other rune
	becomes the smallest rune of its unicode.SimpleFold orbit. Only two runes
	reach ASCII that way, ſ (to S) and the Kelvin sign K (to K); the rest stay as
	they are here, which keeps them unequal to any ASCII name, as in Go.
**/
private function goFoldedName(name:String):String {
	final folded = new StringBuf();
	for (index in 0...name.length) {
		final code:Int = name.charCodeAt(index);
		if (code >= "a".code && code <= "z".code)
			folded.addChar(code - 32);
		else if (code == 0x17F)
			folded.add("S");
		else if (code == 0x212A)
			folded.add("K");
		else
			folded.add(name.charAt(index));
	}
	return folded.toString();
}

/**
	strconv.ParseInt(token, 10, 64) for a valid JSON number, as decimal text,
	or null when Go fails: a fraction, an exponent, or a value outside int64.
**/
private function goInt64Text(token:String):Null<String> {
	final negative = StringTools.startsWith(token, "-");
	final digits = negative ? token.substr(1) : token;
	for (index in 0...digits.length) {
		final code:Int = digits.charCodeAt(index);
		if (code < "0".code || code > "9".code)
			return null;
	}
	// JSON integers have no leading zeros, so equal-length digit strings order like their values.
	final limit = negative ? "9223372036854775808" : "9223372036854775807";
	if (digits.length > limit.length || (digits.length == limit.length && digits > limit))
		return null;
	return digits == "0" ? "0" : token;
}

/** Typed parser for JSON that has already passed native syntax validation. */
private final class TypedJsonParser {
	final source:String;

	/** Keeps every member of an object in document order instead of the last value of each key. */
	final keepDuplicateKeys:Bool;

	var index = 0;
	var failed = false;

	public function new(source:String, keepDuplicateKeys = false) {
		this.source = source;
		this.keepDuplicateKeys = keepDuplicateKeys;
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
			if (!keepDuplicateKeys)
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
				if (source.charCodeAt(index - 1) < 32) {
					failed = true;
					return output.toString();
				}
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
					final code = parseUnicodeCodePoint();
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

	/** Match encoding/json: combine UTF-16 pairs and retain the next escape after an unpaired unit. */
	function parseUnicodeCodePoint():Int {
		final first = parseHexCodeUnit();
		if (first < 0)
			return -1;
		if (first >= 0xDC00 && first <= 0xDFFF)
			return 0xFFFD;
		if (first < 0xD800 || first > 0xDBFF)
			return first;
		final nextEscape = index;
		if (source.substr(index, 2) == "\\u") {
			index += 2;
			final second = parseHexCodeUnit();
			if (second < 0)
				return -1;
			if (second >= 0xDC00 && second <= 0xDFFF)
				return 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00;
			index = nextEscape;
		}
		return 0xFFFD;
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
		final token = source.substring(start, index);
		if (!isJsonNumber(token))
			failed = true;
		return NumberValue(token);
	}

	/** Validate JSON number spelling without converting or narrowing its value. */
	static function isJsonNumber(token:String):Bool {
		var position = token.charAt(0) == "-" ? 1 : 0;
		if (token.charAt(position) == "0") {
			position++;
		} else {
			final first = token.charAt(position);
			if (first < "1" || first > "9")
				return false;
			while (isNumberDigit(token.charAt(position)))
				position++;
		}
		if (token.charAt(position) == ".") {
			position++;
			final fractionStart = position;
			while (isNumberDigit(token.charAt(position)))
				position++;
			if (position == fractionStart)
				return false;
		}
		if (token.charAt(position) == "e" || token.charAt(position) == "E") {
			position++;
			if (token.charAt(position) == "+" || token.charAt(position) == "-")
				position++;
			final exponentStart = position;
			while (isNumberDigit(token.charAt(position)))
				position++;
			if (position == exponentStart)
				return false;
		}
		return position == token.length;
	}

	static inline function isNumberDigit(character:String):Bool {
		return character >= "0" && character <= "9";
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
