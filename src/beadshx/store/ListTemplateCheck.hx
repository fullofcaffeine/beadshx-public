package beadshx.store;

/**
	How a value that Haxe gives a `list --format` template compares with the Go value that
	upstream gives it.

	Why: upstream executes the template on a `map[string]interface{}` whose `Type` is a
	types.DependencyType and whose `Issue` and `Dependency` are `*types.Issue` and
	`*types.Dependency` (cmd/bd/list_output.go:134-140). Haxe builds the same root as a native
	`map[string]any` (go.NativeAnyMap), so a struct becomes a nested map and a named or time
	value becomes a plain Go value. Each kind names the template uses that still agree.
**/
enum TemplateValueKind {
	/** The Go type and value that upstream has: a string, an int or a bool. Every use agrees. */
	SameValue;

	/** A `[]string` that upstream leaves nil when it has no element, and Haxe's is empty: only `%#v` differs. */
	StringList;

	/**
		A Go string where upstream has a named string type, such as types.Status. Its text, its
		length and comparisons agree. `%T`, a verb other than v, s, q, x and X, and the methods of
		the named type differ.
	**/
	NamedString;

	/**
		The text of upstream's time.Time `String()`. Printing it, also with printf's v, s, q, x and
		X verbs without the `#` flag, agrees. Comparisons, `len`, `%#v` and the time methods differ.
	**/
	TimeText;
}

/** The fields of upstream's types.Issue that Haxe gives a template, by their Go names. */
enum abstract IssueTemplateField(String) to String {
	var ID = "ID";
	var Title = "Title";
	var Description = "Description";
	var Design = "Design";
	var AcceptanceCriteria = "AcceptanceCriteria";
	var Notes = "Notes";
	var SpecID = "SpecID";
	var Status = "Status";
	var Priority = "Priority";
	var IssueType = "IssueType";
	var IsBlocked = "IsBlocked";
	var Assignee = "Assignee";
	var Owner = "Owner";
	var CreatedAt = "CreatedAt";
	var CreatedBy = "CreatedBy";
	var UpdatedAt = "UpdatedAt";
	var CloseReason = "CloseReason";
	var ClosedBySession = "ClosedBySession";
	var LeaseGrantedNode = "LeaseGrantedNode";
	var SourceSystem = "SourceSystem";
	var CompactionLevel = "CompactionLevel";
	var OriginalSize = "OriginalSize";
	var Labels = "Labels";
	var Sender = "Sender";
	var Ephemeral = "Ephemeral";
	var NoHistory = "NoHistory";
	var WispType = "WispType";
	var StorageClass = "StorageClass";
	var Pinned = "Pinned";
	var IsTemplate = "IsTemplate";
	var AwaitType = "AwaitType";
	var AwaitID = "AwaitID";
	var Waiters = "Waiters";
	var SourceFormula = "SourceFormula";
	var SourceLocation = "SourceLocation";
	var MolType = "MolType";
	var WorkType = "WorkType";
	var EventKind = "EventKind";
	var Actor = "Actor";
	var Target = "Target";
	var Payload = "Payload";

	/** The method `(*Issue).IsCompound`, which a template calls like a field: `len(BondedFrom) > 0`. */
	var IsCompound = "IsCompound";
}

/** The fields of upstream's types.Dependency that Haxe gives a template, by their Go names. */
enum abstract DependencyTemplateField(String) to String {
	var ID = "ID";
	var IssueID = "IssueID";
	var DependsOnID = "DependsOnID";
	var Type = "Type";
	var CreatedAt = "CreatedAt";
	var CreatedBy = "CreatedBy";
	var Metadata = "Metadata";
	var ThreadID = "ThreadID";
}

/** Every Issue field of the template data. The native renderer sets each one. */
function issueTemplateFields():Array<IssueTemplateField> {
	return [
		ID,
		Title,
		Description,
		Design,
		AcceptanceCriteria,
		Notes,
		SpecID,
		Status,
		Priority,
		IssueType,
		IsBlocked,
		Assignee,
		Owner,
		CreatedAt,
		CreatedBy,
		UpdatedAt,
		CloseReason,
		ClosedBySession,
		LeaseGrantedNode,
		SourceSystem,
		CompactionLevel,
		OriginalSize,
		Labels,
		Sender,
		Ephemeral,
		NoHistory,
		WispType,
		StorageClass,
		Pinned,
		IsTemplate,
		AwaitType,
		AwaitID,
		Waiters,
		SourceFormula,
		SourceLocation,
		MolType,
		WorkType,
		EventKind,
		Actor,
		Target,
		Payload,
		IsCompound
	];
}

/** Every Dependency field of the template data. The native renderer sets each one. */
function dependencyTemplateFields():Array<DependencyTemplateField> {
	return [ID, IssueID, DependsOnID, Type, CreatedAt, CreatedBy, Metadata, ThreadID];
}

/** How an Issue field compares with upstream's (see TemplateValueKind). */
function issueFieldKind(field:IssueTemplateField):TemplateValueKind {
	return switch field {
		case Status | IssueType | WispType | StorageClass | MolType | WorkType: NamedString;
		case CreatedAt | UpdatedAt: TimeText;
		case Labels | Waiters: StringList;
		case ID | Title | Description | Design | AcceptanceCriteria | Notes | SpecID | Priority | IsBlocked | Assignee | Owner | CreatedBy | CloseReason |
			ClosedBySession | LeaseGrantedNode | SourceSystem | CompactionLevel | OriginalSize | Sender | Ephemeral | NoHistory | Pinned | IsTemplate |
			AwaitType | AwaitID | SourceFormula | SourceLocation | EventKind | Actor | Target | Payload | IsCompound: SameValue;
	};
}

/** How a Dependency field compares with upstream's (see TemplateValueKind). */
function dependencyFieldKind(field:DependencyTemplateField):TemplateValueKind {
	return switch field {
		case Type: NamedString;
		case CreatedAt: TimeText;
		case ID | IssueID | DependsOnID | CreatedBy | Metadata | ThreadID: SameValue;
	};
}

/**
	Whether Haxe's template data renders `source` exactly as upstream's Go data does.

	Why: some template uses see that Haxe's data is a map of plain Go values and not upstream's
	Go structs (see TemplateValueKind), such as `{{printf "%T" .Type}}`, `{{.Issue}}`,
	`{{.Issue.Nope}}` or `{{.Issue.CreatedAt.Year}}`. The native store renders those with
	upstream's types instead.
	What: true when every action reads only the fields above, in uses that agree for their kind.
	A template that fails to parse also gives the same error on both paths.
	How: a scanner for a subset of text/template's syntax (text/template/parse/lex.go) and a
	walk that tracks the kind of dot, of each variable and of each value. Anything outside the
	subset, such as comments, nested templates, char and float constants, or functions other
	than printf, print, println, eq, ne, lt, le, gt, ge, and, or, not, len and index, gives false.
	For a template that Go parses, the subset reads each accepted action as Go does.
**/
function templateMatchesUpstream(source:String):Bool {
	final tokens = scanTemplate(source);
	if (tokens == null)
		return false;
	return try {
		new TemplateWalk(tokens).walkTemplate();
		true;
	} catch (unsupported:UnsupportedTemplate) {
		false;
	}
}

/** One token of the subset that scanTemplate reads. */
private enum TemplateToken {
	/** Text outside the actions; its content does not matter. */
	TemplateText;

	/** `{{` or `{{- `. */
	OpenAction;

	/** `}}` or ` -}}`. */
	CloseAction;

	/** Spaces, tabs and line breaks inside an action. */
	ActionSpace;

	/** `.Name`; `.A.B` is two adjacent tokens. */
	FieldName(name:String);

	/** A lone `.`. */
	DotValue;

	/** `$` or `$name`. */
	VariableName(name:String);

	/** A function name or a keyword. */
	Word(name:String);

	/** A quoted string; `value` is null when it holds an escape that the walk does not decode. */
	StringConstant(value:Null<String>);

	/** A decimal integer. */
	NumberConstant;

	/** `true` or `false`. */
	BoolConstant;

	PipeSymbol;
	OpenParen;
	CloseParen;
	DeclareSymbol;
	AssignSymbol;
	CommaSymbol;
	EndOfTemplate;
}

/**
	The tokens of `source`, or null when it leaves the subset. The rules follow
	text/template/parse/lex.go for the tokens that the subset keeps.
**/
private function scanTemplate(source:String):Null<Array<TemplateToken>> {
	final tokens = new Array<TemplateToken>();
	final length = source.length;
	var position = 0;
	while (position < length) {
		final open = source.indexOf("{{", position);
		if (open < 0) {
			tokens.push(TemplateText);
			break;
		}
		if (open > position)
			tokens.push(TemplateText);
		position = open + 2;
		// A left trim marker is `-` and one space character.
		if (position + 1 < length && code(source, position) == "-".code && isTemplateSpace(code(source, position + 1)))
			position += 2;
		if (source.substr(position, 2) == "/*")
			return null;
		tokens.push(OpenAction);
		var closed = false;
		while (!closed) {
			if (position >= length)
				return null;
			if (source.substr(position, 2) == "}}") {
				position += 2;
				tokens.push(CloseAction);
				closed = true;
				continue;
			}
			final character = code(source, position);
			if (isTemplateSpace(character)) {
				while (position < length && isTemplateSpace(code(source, position)))
					position++;
				// A right trim marker is one space character and `-` before `}}`.
				if (source.substr(position, 3) == "-}}") {
					position += 3;
					tokens.push(CloseAction);
					closed = true;
				} else
					tokens.push(ActionSpace);
				continue;
			}
			switch character {
				case ":".code:
					if (code(source, position + 1) != "=".code)
						return null;
					tokens.push(DeclareSymbol);
					position += 2;
				case "=".code:
					tokens.push(AssignSymbol);
					position++;
				case "|".code:
					tokens.push(PipeSymbol);
					position++;
				case "(".code:
					tokens.push(OpenParen);
					position++;
				case ")".code:
					tokens.push(CloseParen);
					position++;
				case ",".code:
					tokens.push(CommaSymbol);
					position++;
				case "\"".code:
					var end = position + 1;
					var escaped = false;
					while (true) {
						if (end >= length)
							return null;
						final next = code(source, end);
						if (next == "\\".code) {
							if (end + 1 >= length || code(source, end + 1) == "\n".code)
								return null;
							escaped = true;
							end += 2;
							continue;
						}
						if (next == "\n".code)
							return null;
						if (next == "\"".code)
							break;
						end++;
					}
					tokens.push(StringConstant(escaped ? null : source.substring(position + 1, end)));
					position = end + 1;
				case "`".code:
					final end = source.indexOf("`", position + 1);
					if (end < 0)
						return null;
					// strconv.Unquote drops carriage returns from a raw string.
					tokens.push(StringConstant(source.substring(position + 1, end).split("\r").join("")));
					position = end + 1;
				case "$".code:
					final end = alphanumericEnd(source, position + 1);
					if (!atTerminator(source, end))
						return null;
					tokens.push(VariableName(source.substring(position, end)));
					position = end;
				case ".".code:
					if (isDigit(code(source, position + 1)))
						return null;
					final end = alphanumericEnd(source, position + 1);
					if (!atTerminator(source, end))
						return null;
					tokens.push(end == position + 1 ? DotValue : FieldName(source.substring(position + 1, end)));
					position = end;
				case "-".code | "0".code | "1".code | "2".code | "3".code | "4".code | "5".code | "6".code | "7".code | "8".code | "9".code:
					var end = character == "-".code ? position + 1 : position;
					if (!isDigit(code(source, end)))
						return null;
					while (isDigit(code(source, end)))
						end++;
					final after = code(source, end);
					if (isAlphanumeric(after) || after == ".".code || after == "+".code || after == "-".code)
						return null;
					tokens.push(NumberConstant);
					position = end;
				case _ if (isLetter(character)):
					final end = alphanumericEnd(source, position);
					if (!atTerminator(source, end))
						return null;
					final word = source.substring(position, end);
					tokens.push(word == "true" || word == "false" ? BoolConstant : Word(word));
					position = end;
				case _:
					return null;
			}
		}
	}
	tokens.push(EndOfTemplate);
	return tokens;
}

/** The code unit at `position`, or -1 past the end. */
private function code(source:String, position:Int):Int {
	return position < source.length ? StringTools.fastCodeAt(source, position) : -1;
}

private function isTemplateSpace(character:Int):Bool {
	return character == " ".code || character == "\t".code || character == "\r".code || character == "\n".code;
}

private function isDigit(character:Int):Bool {
	return character >= "0".code && character <= "9".code;
}

/** An ASCII letter or `_`. Go also accepts other Unicode letters, which leave the subset. */
private function isLetter(character:Int):Bool {
	return (character >= "a".code && character <= "z".code) || (character >= "A".code && character <= "Z".code) || character == "_".code;
}

private function isAlphanumeric(character:Int):Bool {
	return isLetter(character) || isDigit(character);
}

private function alphanumericEnd(source:String, position:Int):Int {
	var end = position;
	while (isAlphanumeric(code(source, end)))
		end++;
	return end;
}

/** lex.go's atTerminator: what may follow a field, a variable or a word. */
private function atTerminator(source:String, position:Int):Bool {
	final character = code(source, position);
	return character == -1 || isTemplateSpace(character) || character == ".".code || character == ",".code || character == "|".code
		|| character == ":".code || character == ")".code || character == "(".code || source.substr(position, 2) == "}}";
}

/** A template use that the subset leaves to the native store. */
private class UnsupportedTemplate extends haxe.Exception {}

/**
	What a template value is: a value of one of the TemplateValueKind kinds, or the data root.
	The constructors have no arguments, so `==` compares them.
**/
private enum TemplateValue {
	PlainValue;
	ListValue;
	NamedValue;
	TimeValue;

	/** The root map (`.` at the top, or `$`): only `len` reads it, since its five keys agree. */
	RootValue;
}

private function kindValue(kind:TemplateValueKind):TemplateValue {
	return switch kind {
		case SameValue: PlainValue;
		case StringList: ListValue;
		case NamedString: NamedValue;
		case TimeText: TimeValue;
	};
}

/** What one operand of a command is. */
private enum TemplateOperand {
	FunctionWord(name:String);
	ArgumentValue(value:TemplateValue, format:FormatText);
}

/** The text of a string constant, which printf's format needs. */
private enum FormatText {
	NotConstant;
	ConstantText(value:String);
	UndecodedText;
}

/** The value of a command or pipeline and, for a lone string constant, its text. */
private typedef PipelineResult = {
	final value:TemplateValue;
	final format:FormatText;
	final declarations:Array<String>;
}

/** How a list of actions ends. */
private enum ListEnd {
	ListAtTemplateEnd;
	ListAtEnd;
	ListAtElse;
	ListAtElseIf;
}

/**
	Walks the tokens as text/template/parse/parse.go reads them and checks each use against the
	kind of its value. Variables live in nested scopes: a control's pipeline declarations stay
	visible in its lists, except range's, whose values in the else list are not elements.
**/
private final class TemplateWalk {
	final tokens:Array<TemplateToken>;
	var position = 0;
	final scopes = new Array<Map<String, TemplateValue>>();

	public function new(tokens:Array<TemplateToken>) {
		this.tokens = tokens;
	}

	public function walkTemplate():Void {
		if (walkList(RootValue) != ListAtTemplateEnd)
			throw unsupportedUse();
	}

	function walkList(dot:TemplateValue):ListEnd {
		scopes.push(new Map());
		while (true) {
			switch next() {
				case EndOfTemplate:
					scopes.pop();
					return ListAtTemplateEnd;
				case TemplateText:
				case OpenAction:
					skipSpace();
					switch peek() {
						case Word("if"):
							position++;
							walkIf(dot);
						case Word("range"):
							position++;
							walkRange(dot);
						case Word("with"):
							position++;
							walkWith(dot);
						case Word("end"):
							position++;
							expectClose();
							scopes.pop();
							return ListAtEnd;
						case Word("else"):
							position++;
							skipSpace();
							switch next() {
								case CloseAction:
									scopes.pop();
									return ListAtElse;
								case Word("if"):
									scopes.pop();
									return ListAtElseIf;
								case _:
									throw unsupportedUse();
							}
						case _:
							walkAction(dot);
					}
				case _:
					throw unsupportedUse();
			}
		}
	}

	function walkIf(dot:TemplateValue):Void {
		scopes.push(new Map());
		final condition = walkPipeline(dot, 1, CloseAction);
		declare(condition.declarations, known(condition.value));
		switch walkList(dot) {
			case ListAtEnd:
			case ListAtElse:
				if (walkList(dot) != ListAtEnd)
					throw unsupportedUse();
			case ListAtElseIf:
				// `{{else if}}` is an if in the else list that shares this if's `{{end}}`.
				walkIf(dot);
			case ListAtTemplateEnd:
				throw unsupportedUse();
		}
		scopes.pop();
	}

	function walkRange(dot:TemplateValue):Void {
		scopes.push(new Map());
		final range = walkPipeline(dot, 2, CloseAction);
		final element = switch range.value {
			case PlainValue | ListValue: PlainValue;
			case _: throw unsupportedUse();
		};
		declare(range.declarations, element);
		final bodyEnd = walkList(element);
		scopes.pop();
		switch bodyEnd {
			case ListAtEnd:
			case ListAtElse:
				if (walkList(dot) != ListAtEnd)
					throw unsupportedUse();
			case ListAtElseIf | ListAtTemplateEnd:
				throw unsupportedUse();
		}
	}

	function walkWith(dot:TemplateValue):Void {
		scopes.push(new Map());
		final with = walkPipeline(dot, 1, CloseAction);
		final value = known(with.value);
		declare(with.declarations, value);
		switch walkList(value) {
			case ListAtEnd:
			case ListAtElse:
				if (walkList(dot) != ListAtEnd)
					throw unsupportedUse();
			case ListAtElseIf | ListAtTemplateEnd:
				throw unsupportedUse();
		}
		scopes.pop();
	}

	/** An action prints its pipeline's value; one that declares a variable prints nothing. */
	function walkAction(dot:TemplateValue):Void {
		final action = walkPipeline(dot, 1, CloseAction);
		if (action.declarations.length > 0)
			declare(action.declarations, action.value);
		else
			known(action.value);
	}

	/**
		parse.go's pipeline: optional declarations (`$x :=`, and `$i, $e :=` for range), then
		commands joined by `|`, up to `close`. An assignment (`$x =`) leaves the subset.
	**/
	function walkPipeline(dot:TemplateValue, maximumDeclarations:Int, close:TemplateToken):PipelineResult {
		skipSpace();
		final declarations = new Array<String>();
		while (true) {
			final start = position;
			switch next() {
				case VariableName(name) if (name != "$"):
					skipSpace();
					switch next() {
						case DeclareSymbol:
							declarations.push(name);
						case CommaSymbol if (maximumDeclarations == 2 && declarations.length == 0):
							declarations.push(name);
							skipSpace();
							continue;
						case AssignSymbol | CommaSymbol:
							throw unsupportedUse();
						case _:
							position = start;
					}
				case _:
					position = start;
			}
			break;
		}
		// After `$i,` only `$e :=` keeps both declarations as Go reads them.
		if (declarations.length == 1 && position > 0 && tokens[position - 1] != DeclareSymbol)
			throw unsupportedUse();
		if (declarations.length > maximumDeclarations)
			throw unsupportedUse();
		var result:Null<PipelineResult> = null;
		while (true) {
			result = walkCommand(dot, result);
			skipSpace();
			final token = next();
			if (token == PipeSymbol)
				continue;
			if (token != close)
				throw unsupportedUse();
			break;
		}
		return {value: result.value, format: result.format, declarations: declarations};
	}

	/**
		parse.go's command. A command that starts with a function word calls it, with the piped
		value as its last argument. Any other command is one operand without piped input: a field
		with arguments fails upstream with a message that names the struct field.
	**/
	function walkCommand(dot:TemplateValue, piped:Null<PipelineResult>):PipelineResult {
		skipSpace();
		final operands = new Array<TemplateOperand>();
		while (true) {
			operands.push(walkOperand(dot));
			skipSpace();
			switch peek() {
				case PipeSymbol | CloseAction | CloseParen:
					break;
				case _:
			}
		}
		return switch operands[0] {
			case FunctionWord(name):
				final arguments = new Array<PipelineResult>();
				for (index in 1...operands.length)
					switch operands[index] {
						case ArgumentValue(value, format):
							arguments.push({value: value, format: format, declarations: []});
						case FunctionWord(_):
							throw unsupportedUse();
					}
				if (piped != null)
					arguments.push(piped);
				{value: callFunction(name, arguments), format: NotConstant, declarations: []};
			case ArgumentValue(value, format):
				if (operands.length != 1 || piped != null)
					throw unsupportedUse();
				{value: value, format: format, declarations: []};
		};
	}

	function walkOperand(dot:TemplateValue):TemplateOperand {
		return switch next() {
			case Word(name):
				if (isKeyword(name))
					throw unsupportedUse();
				refuseChain();
				FunctionWord(name);
			case BoolConstant | NumberConstant:
				refuseChain();
				ArgumentValue(PlainValue, NotConstant);
			case StringConstant(value):
				refuseChain();
				ArgumentValue(PlainValue, value == null ? UndecodedText : ConstantText(value));
			case DotValue:
				refuseChain();
				ArgumentValue(dot, NotConstant);
			case FieldName(name):
				final path = [name].concat(chainedFields());
				ArgumentValue(resolveField(dot, path), NotConstant);
			case VariableName("$"):
				final path = chainedFields();
				ArgumentValue(path.length == 0 ? RootValue : resolveField(RootValue, path), NotConstant);
			case VariableName(name):
				refuseChain();
				ArgumentValue(lookup(name), NotConstant);
			case OpenParen:
				final inner = walkPipeline(dot, 0, CloseParen);
				refuseChain();
				ArgumentValue(inner.value, NotConstant);
			case _:
				throw unsupportedUse();
		};
	}

	/**
		A field path from the root: the two strings, the named Type, and one field of Issue or
		Dependency. A missing root key prints `<no value>` on both paths, since both roots are maps.
	**/
	function resolveField(base:TemplateValue, path:Array<String>):TemplateValue {
		if (base != RootValue)
			throw unsupportedUse();
		return switch path {
			case ["IssueID"] | ["DependsOnID"]: PlainValue;
			case ["Type"]: NamedValue;
			case ["Issue", name]:
				final field = issueTemplateFields().filter(field -> (field : String) == name);
				field.length == 1 ? kindValue(issueFieldKind(field[0])) : throw unsupportedUse();
			case ["Dependency", name]:
				final field = dependencyTemplateFields().filter(field -> (field : String) == name);
				field.length == 1 ? kindValue(dependencyFieldKind(field[0])) : throw unsupportedUse();
			case [name] if (name != "Issue" && name != "Dependency"): PlainValue;
			case _: throw unsupportedUse();
		};
	}

	/**
		The builtin functions of the subset (text/template/funcs.go). Each argument kind must give
		the same result on both paths: comparisons read string and int kinds, `len` reads the
		text of a named string, and printf's verbs must agree for each argument.
	**/
	function callFunction(name:String, arguments:Array<PipelineResult>):TemplateValue {
		final kinds = arguments.map(argument -> argument.value);
		function each(allowed:Array<TemplateValue>):Void {
			for (kind in kinds)
				if (!allowed.contains(kind))
					throw unsupportedUse();
		}
		switch name {
			case "printf":
				if (kinds.filter(kind -> kind != PlainValue).length == 0)
					return PlainValue;
				switch arguments[0].format {
					case ConstantText(format):
						if (!printfAgrees(format, kinds.slice(1))) throw unsupportedUse();
					case NotConstant | UndecodedText:
						throw unsupportedUse();
				}
				return PlainValue;
			case "print" | "println":
				each([PlainValue, ListValue, NamedValue]);
				return PlainValue;
			case "eq" | "ne" | "lt" | "le" | "gt" | "ge":
				each([PlainValue, NamedValue]);
				return PlainValue;
			case "and" | "or":
				var joined = PlainValue;
				for (index in 0...kinds.length) {
					final kind = known(kinds[index]);
					joined = index == 0 ? kind : join(joined, kind);
				}
				return joined;
			case "not":
				for (kind in kinds)
					known(kind);
				return PlainValue;
			case "len":
				each([PlainValue, ListValue, NamedValue, RootValue]);
				return PlainValue;
			case "index":
				if (kinds.length == 0)
					return PlainValue;
				if (kinds[0] != PlainValue && kinds[0] != ListValue)
					throw unsupportedUse();
				for (index in 1...kinds.length)
					if (kinds[index] != PlainValue)
						throw unsupportedUse();
				return kinds.length == 1 ? kinds[0] : PlainValue;
			case _:
				throw unsupportedUse();
		}
	}

	function declare(names:Array<String>, value:TemplateValue):Void {
		for (name in names)
			scopes[scopes.length - 1].set(name, value);
	}

	function lookup(name:String):TemplateValue {
		var index = scopes.length - 1;
		while (index >= 0) {
			final value = scopes[index].get(name);
			if (value != null)
				return value;
			index--;
		}
		throw unsupportedUse();
	}

	function chainedFields():Array<String> {
		final fields = new Array<String>();
		while (true)
			switch peek() {
				case FieldName(name):
					position++;
					fields.push(name);
				case _:
					return fields;
			}
	}

	/** A field after a constant, a function word, `.`, a variable or a parenthesized pipeline. */
	function refuseChain():Void {
		switch peek() {
			case FieldName(_):
				throw unsupportedUse();
			case _:
		}
	}

	function expectClose():Void {
		skipSpace();
		if (next() != CloseAction)
			throw unsupportedUse();
	}

	function skipSpace():Void {
		while (peek() == ActionSpace)
			position++;
	}

	function peek():TemplateToken {
		return position < tokens.length ? tokens[position] : EndOfTemplate;
	}

	function next():TemplateToken {
		final token = peek();
		position++;
		return token;
	}
}

/** parse.go's keywords; `break` and `continue` are keywords inside range. */
private function isKeyword(word:String):Bool {
	return [
		"block",
		"break",
		"continue",
		"define",
		"else",
		"end",
		"if",
		"nil",
		"range",
		"template",
		"with"
	].contains(word);
}

/** A value that can be printed, tested for truth or passed to `and`, `or` and `not`: not the root. */
private function known(value:TemplateValue):TemplateValue {
	if (value == RootValue)
		throw unsupportedUse();
	return value;
}

/**
	The kind of a value that `and` or `or` returns, one of its arguments: a kind whose agreeing
	uses agree for both. A string or int and a named string agree as a named string; any other
	pair agrees only where a time text does, whose uses agree for every kind.
**/
private function join(left:TemplateValue, right:TemplateValue):TemplateValue {
	if (left == right)
		return left;
	final plain = [PlainValue, NamedValue];
	return plain.contains(left) && plain.contains(right) ? NamedValue : TimeValue;
}

/**
	Whether fmt's Sprintf prints the same text for Haxe's arguments as for upstream's. The
	format follows fmt's doPrintf: flags, width and precision, then a verb that takes the next
	argument (`%%` takes none). Argument indexes, `*` and widths of more than six digits leave
	the subset. A verb past the last
	argument prints `%!v(MISSING)` on both paths; an argument past the last verb prints its Go
	type, so it must be a SameValue.
**/
private function printfAgrees(format:String, arguments:Array<TemplateValue>):Bool {
	var argument = 0;
	var position = 0;
	final length = format.length;
	while (position < length) {
		if (code(format, position) != "%".code) {
			position++;
			continue;
		}
		position++;
		var sharp = false;
		while (position < length) {
			final flag = code(format, position);
			if (flag == "#".code)
				sharp = true;
			else if (flag != "0".code && flag != "+".code && flag != "-".code && flag != " ".code)
				break;
			position++;
		}
		final widthStart = position;
		while (isDigit(code(format, position)))
			position++;
		// fmt's parsenum gives up on a number above 1e6 and then prints `%!(NOVERB)`.
		if (position - widthStart > 6)
			return false;
		// fmt reads a precision only when a character follows the `.`; else `.` is the verb.
		if (code(format, position) == ".".code && position + 1 < length) {
			position++;
			final precisionStart = position;
			while (isDigit(code(format, position)))
				position++;
			if (position - precisionStart > 6)
				return false;
		}
		final verb = code(format, position);
		if (verb == "[".code || verb == "*".code)
			return false;
		if (verb == -1)
			break;
		position++;
		if (verb == "%".code)
			continue;
		if (argument >= arguments.length)
			continue;
		if (!verbAgrees(arguments[argument], sharp, verb))
			return false;
		argument++;
	}
	while (argument < arguments.length) {
		if (arguments[argument] != PlainValue)
			return false;
		argument++;
	}
	return true;
}

/**
	A named string prints its text for v, s, q, x and X, and fmt's bad-verb text names its Go
	type for any other verb. A time prints its String() text for those verbs, except that `%#v`
	prints its GoString(). A nil and an empty `[]string` differ only for `%#v`.
**/
private function verbAgrees(value:TemplateValue, sharp:Bool, verb:Int):Bool {
	final textVerb = verb == "v".code || verb == "s".code || verb == "q".code || verb == "x".code || verb == "X".code;
	return switch value {
		case PlainValue: true;
		case ListValue: !(sharp && verb == "v".code);
		case NamedValue: textVerb;
		case TimeValue: textVerb && !sharp;
		case RootValue: false;
	};
}

private function unsupportedUse():UnsupportedTemplate {
	return new UnsupportedTemplate("template use outside the exact subset");
}
