package beadshx.query;

import haxe.io.Bytes;

private enum QueryTokenKind {
	End;
	Identifier;
	QuotedString;
	Number;
	Duration;
	Equals;
	NotEquals;
	Less;
	LessOrEqual;
	Greater;
	GreaterOrEqual;
	AndKeyword;
	OrKeyword;
	NotKeyword;
	LeftParenthesis;
	RightParenthesis;
	Comma;
}

private typedef QueryToken = {
	final kind:QueryTokenKind;
	final value:String;
	final position:Int;
}

/** Closed comparison operators admitted by the pinned Beads query language. */
enum QueryComparisonOperator {
	Equal;
	NotEqual;
	LessThan;
	LessThanOrEqual;
	GreaterThan;
	GreaterThanOrEqual;
}

/** The lexical value kind retained for later typed query evaluation. */
enum QueryValueKind {
	IdentifierValue;
	StringValue;
	NumberValue;
	DurationValue;
}

/** Recursive, fully typed syntax tree for one Beads query expression. */
enum QueryExpression {
	Comparison(field:String, comparison:QueryComparisonOperator, value:String, valueKind:QueryValueKind);
	And(left:QueryExpression, right:QueryExpression);
	Or(left:QueryExpression, right:QueryExpression);
	Not(operand:QueryExpression);
}

/** Parsing keeps a compatible diagnostic distinct from a valid syntax tree. */
enum QuerySyntaxResult {
	Parsed(expression:QueryExpression);
	Invalid(message:String);
}

/**
	Haxe-owned lexer, parser, and canonical AST rendering for `bd query`.

	The lexer intentionally reads UTF-8 one byte at a time because the pinned Go
	implementation does. This preserves both its byte offsets and its observable
	text handling. The parser owns precedence and field-name normalization.
	Metadata key suffixes remain case-sensitive because they name JSON object keys.
**/
final class QuerySyntax {
	public static function parse(source:String):QuerySyntaxResult {
		final parser = new QueryParser(source);
		return parser.parse();
	}

	public static function render(expression:QueryExpression):String {
		return switch expression {
			case Comparison(field, comparison, value, _): field + renderOperator(comparison) + value;
			case And(left, right): '(${render(left)} AND ${render(right)})';
			case Or(left, right): '(${render(left)} OR ${render(right)})';
			case Not(operand): 'NOT ${render(operand)}';
		};
	}

	static function renderOperator(comparison:QueryComparisonOperator):String {
		return switch comparison {
			case Equal: "=";
			case NotEqual: "!=";
			case LessThan: "<";
			case LessThanOrEqual: "<=";
			case GreaterThan: ">";
			case GreaterThanOrEqual: ">=";
		};
	}
}

private final class QueryParser {
	final lexer:QueryLexer;
	var current:QueryToken = {kind: End, value: "", position: 0};
	var failure = "";

	public function new(source:String) {
		lexer = new QueryLexer(source);
	}

	public function parse():QuerySyntaxResult {
		advance();
		if (failure != "")
			return Invalid(failure);
		if (current.kind == End)
			return Invalid("empty query");
		final expression = parseOr();
		if (failure != "")
			return Invalid(failure);
		if (current.kind != End)
			return Invalid('unexpected token "${current.value}" at position ${current.position} (expected end of query)');
		return Parsed(expression);
	}

	function parseOr():QueryExpression {
		var left = parseAnd();
		while (failure == "" && current.kind == OrKeyword) {
			advance();
			left = Or(left, parseAnd());
		}
		return left;
	}

	function parseAnd():QueryExpression {
		var left = parseNot();
		while (failure == "" && current.kind == AndKeyword) {
			advance();
			left = And(left, parseNot());
		}
		return left;
	}

	function parseNot():QueryExpression {
		if (current.kind == NotKeyword) {
			advance();
			return Not(parseNot());
		}
		return parsePrimary();
	}

	function parsePrimary():QueryExpression {
		if (current.kind == LeftParenthesis) {
			advance();
			final expression = parseOr();
			if (failure != "")
				return expression;
			if (current.kind != RightParenthesis) {
				failure = "expected ')' at position " + current.position + ", got " + tokenName(current.kind);
				return expression;
			}
			advance();
			return expression;
		}
		return parseComparison();
	}

	function parseComparison():QueryExpression {
		if (current.kind != Identifier) {
			failure = "expected field name at position " + current.position + ", got " + tokenName(current.kind);
			return placeholder();
		}
		final originalField = current.value;
		var field = originalField.toLowerCase();
		if (StringTools.startsWith(field, "metadata.") && field.length > 9)
			field = "metadata." + originalField.substr(9);
		advance();
		if (failure != "")
			return placeholder();
		final comparison = switch current.kind {
			case Equals: Equal;
			case NotEquals: NotEqual;
			case Less: LessThan;
			case LessOrEqual: LessThanOrEqual;
			case Greater: GreaterThan;
			case GreaterOrEqual: GreaterThanOrEqual;
			case _:
				failure = "expected comparison operator at position " + current.position + ", got " + tokenName(current.kind);
				Equal;
		};
		if (failure != "")
			return placeholder();
		advance();
		if (failure != "")
			return placeholder();
		final valueKind = switch current.kind {
			case Identifier: IdentifierValue;
			case QuotedString: StringValue;
			case Number: NumberValue;
			case Duration: DurationValue;
			case _:
				failure = "expected value at position " + current.position + ", got " + tokenName(current.kind);
				IdentifierValue;
		};
		if (failure != "")
			return placeholder();
		final value = current.value;
		advance();
		return Comparison(field, comparison, value, valueKind);
	}

	function advance():Void {
		switch lexer.nextToken() {
			case Lexed(token):
				current = token;
			case LexFailure(message):
				failure = message;
		}
	}

	static function placeholder():QueryExpression {
		return Comparison("", Equal, "", IdentifierValue);
	}

	static function tokenName(kind:QueryTokenKind):String {
		return switch kind {
			case End: "EOF";
			case Identifier: "IDENT";
			case QuotedString: "STRING";
			case Number: "NUMBER";
			case Duration: "DURATION";
			case Equals: "=";
			case NotEquals: "!=";
			case Less: "<";
			case LessOrEqual: "<=";
			case Greater: ">";
			case GreaterOrEqual: ">=";
			case AndKeyword: "AND";
			case OrKeyword: "OR";
			case NotKeyword: "NOT";
			case LeftParenthesis: "(";
			case RightParenthesis: ")";
			case Comma: ",";
		};
	}
}

private enum QueryLexResult {
	Lexed(token:QueryToken);
	LexFailure(message:String);
}

private final class QueryLexer {
	static final letter = new EReg("^\\p{L}$", "u");
	static final number = new EReg("^\\p{N}$", "u");
	static final separator = new EReg("^\\p{Z}$", "u");

	final source:Bytes;
	var position = 0;

	public function new(source:String) {
		this.source = Bytes.ofString(source);
	}

	public function nextToken():QueryLexResult {
		skipWhitespace();
		final start = position;
		if (atEnd())
			return Lexed(token(End, "", start));
		final character = take();
		return switch character {
			case "(": Lexed(token(LeftParenthesis, character, start));
			case ")": Lexed(token(RightParenthesis, character, start));
			case ",": Lexed(token(Comma, character, start));
			case "=": Lexed(token(Equals, character, start));
			case "!":
				if (peek() == "=") {
					take();
					Lexed(token(NotEquals, "!=", start));
				} else LexFailure("unexpected character '!' at position " + start + " (did you mean '!=' or 'NOT'?)");
			case "<":
				if (peek() == "=") {
					take();
					Lexed(token(LessOrEqual, "<=", start));
				} else Lexed(token(Less, "<", start));
			case ">":
				if (peek() == "=") {
					take();
					Lexed(token(GreaterOrEqual, ">=", start));
				} else Lexed(token(Greater, ">", start));
			case '"' | "'": readQuoted(character, start);
			case _:
				if (isDigit(character) || character == "-" || character == "+") {
					position--;
					readNumberOrDuration(start);
				} else if (isIdentifierStart(character)) {
					position--;
					readIdentifier(start);
				} else LexFailure('unexpected character ${quoteCharacter(character)} at position ${start}');
		};
	}

	function readQuoted(quote:String, start:Int):QueryLexResult {
		final value = new StringBuf();
		while (!atEnd()) {
			final character = take();
			if (character == quote)
				return Lexed(token(QuotedString, value.toString(), start));
			if (character != "\\") {
				value.add(character);
				continue;
			}
			if (atEnd())
				return LexFailure("unterminated escape sequence at position " + (position - 1));
			final escaped = take();
			value.add(switch escaped {
				case "n": "\n";
				case "t": "\t";
				case "\\": "\\";
				case '"': '"';
				case "'": "'";
				case _: escaped;
			});
		}
		return LexFailure("unterminated string starting at position " + start);
	}

	function readNumberOrDuration(start:Int):QueryLexResult {
		final value = new StringBuf();
		var hadSign = false;
		var character = take();
		if (character == "-" || character == "+") {
			hadSign = true;
			value.add(character);
			if (atEnd())
				return LexFailure("expected digit at position " + position);
			character = take();
		}
		if (!isDigit(character)) {
			position--;
			return LexFailure("expected digit at position " + position);
		}
		value.add(character);
		while (!atEnd() && isDigit(peek()))
			value.add(take());
		if (!atEnd() && isDurationSuffix(peek())) {
			final suffix = take();
			if (atEnd() || !isIdentifierCharacter(peek())) {
				value.add(suffix);
				return Lexed(token(Duration, value.toString(), start));
			}
			position--;
		}
		if (!hadSign && !atEnd() && isIdentifierCharacter(peek())) {
			position = start;
			return readIdentifier(start);
		}
		return Lexed(token(Number, value.toString(), start));
	}

	function readIdentifier(start:Int):QueryLexResult {
		final value = new StringBuf();
		while (!atEnd() && isIdentifierCharacter(peek()))
			value.add(take());
		final text = value.toString();
		return switch text.toUpperCase() {
			case "AND": Lexed(token(AndKeyword, text, start));
			case "OR": Lexed(token(OrKeyword, text, start));
			case "NOT": Lexed(token(NotKeyword, text, start));
			case _: Lexed(token(Identifier, text, start));
		};
	}

	function skipWhitespace():Void {
		while (!atEnd() && isWhitespace(peek()))
			take();
	}

	inline function atEnd():Bool {
		return position >= source.length;
	}

	inline function peek():String {
		return atEnd() ? "" : String.fromCharCode(source.get(position));
	}

	inline function take():String {
		return String.fromCharCode(source.get(position++));
	}

	static inline function token(kind:QueryTokenKind, value:String, position:Int):QueryToken {
		return {kind: kind, value: value, position: position};
	}

	static function isWhitespace(character:String):Bool {
		if (character == "")
			return false;
		final code = character.charCodeAt(0);
		return (code >= 9 && code <= 13) || code == 0x85 || separator.match(character);
	}

	static function quoteCharacter(character:String):String {
		final escaped = switch character {
			case "\\": "\\\\";
			case "'": "\\'";
			case "\n": "\\n";
			case "\r": "\\r";
			case "\t": "\\t";
			case _: character;
		};
		return "'" + escaped + "'";
	}

	static function isDigit(character:String):Bool {
		return character != "" && number.match(character);
	}

	static function isIdentifierStart(character:String):Bool {
		return character == "_" || (character != "" && letter.match(character));
	}

	static function isIdentifierCharacter(character:String):Bool {
		return isIdentifierStart(character) || isDigit(character) || character == "-" || character == "." || character == ":" || character == "/";
	}

	static function isDurationSuffix(character:String):Bool {
		return switch character {
			case "h" | "d" | "w" | "m" | "y" | "H" | "D" | "W" | "M" | "Y": true;
			case _: false;
		};
	}
}
