package beadshx.store;

#if (go || go_output)
import beadshx.nativeextern.bytes.Buffer;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.encoding.json.JsonPkg;
#end

/**
	Raw issue metadata retained by the pinned SQL scanner before JSON validation.

	SQL reads accept malformed JSON and preserve its bytes. This value keeps that
	storage contract separate from JsonValue's validated invariant. Only NULL,
	exact empty text and exact `{}` are absent; whitespace is never normalized here.

	The Go output helpers use standard-library syntax validation and escaping.
	Haxe owns metadata presence, query behavior and rendering policy.
**/
@:goNative
abstract StoredMetadata(String) {
	private inline function new(raw:String) {
		this = raw;
	}

	/** Map one nullable SQL cell using ScanIssueFrom's exact omission rules. */
	public static function fromSql(raw:Null<String>):StoredMetadata {
		return new StoredMetadata(raw == null || raw == "" || raw == "{}" ? "" : raw);
	}

	public inline function isAbsent():Bool {
		return this == "";
	}

	/** Observe retained text without parsing, trimming or rendering it. */
	public inline function wireValue():String {
		return this;
	}

	/** Validate a copy for JSON consumers; failure leaves retained bytes intact. */
	public function toJsonValue(context:String):StoreResult<JsonValue> {
		return this == "" ? Success(JsonValue.fromValidatedNative("")) : JsonValue.parse(this, context);
	}

	/** Malformed or non-object metadata is a non-match, as in the pinned query evaluator. */
	public function topLevelQueryEquals(key:String, expected:String):Bool {
		return switch toJsonValue("metadata") {
			case Success(value): value.topLevelQueryEquals(key, expected);
			case Failure(_): false;
		};
	}

	public function hasTopLevelKey(key:String):Bool {
		return switch toJsonValue("metadata") {
			case Success(value): value.hasTopLevelKey(key);
			case Failure(_): false;
		};
	}

	public function topLevelFieldCount():Int {
		return switch toJsonValue("metadata") {
			case Success(value): value.topLevelFieldCount();
			case Failure(_): 0;
		};
	}

	/** Human list output omits empty objects and null without changing stored presence. */
	public function hasHumanValue():Bool {
		final trimmed = StringTools.trim(this);
		return this != "" && trimmed != "{}" && trimmed != "null";
	}

	/** Human inspection remains available even when stored JSON is malformed. */
	public function renderHumanLines():Array<String> {
		return switch toJsonValue("metadata") {
			case Success(value): value.renderHumanLines();
			case Failure(_): ["  " + StringTools.trim(this)];
		};
	}

	/** JSON output validates a copy and never changes or silently drops stored bytes. */
	public function renderIndented(baseIndent:String, indentUnit:String):StoreResult<String> {
		return switch outputJsonValue() {
			case Success(value): Success(escapeJsonOutput(value.renderIndented(baseIndent, indentUnit)));
			case Failure(message): Failure(message);
		};
	}

	public function renderSortedIndented(baseIndent:String, indentUnit:String):StoreResult<String> {
		return switch outputJsonValue() {
			case Success(value): Success(escapeJsonOutput(value.renderSortedIndented(baseIndent, indentUnit)));
			case Failure(message): Failure(message);
		};
	}

	/**
		Use encoding/json at the Go output boundary for exact RawMessage syntax errors.

		The compiler recognizes go and go_output; the canonical HXML uses go_output.
		The interpreter keeps the pure parser model for query and formatting contracts;
		it does not qualify native diagnostics or HTML escaping. Native acceptance must
		also pass the typed parser before either renderer can use the value.
	**/
	function outputJsonValue():StoreResult<JsonValue> {
		#if (go || go_output)
		if (this != "") {
			final source:go.NativeSlice<go.NativeByte> = BytesPkg.newBufferString(this).bytes();
			final error = JsonPkg.compact(new Buffer(), source);
			if (error != null)
				return Failure('json: error calling MarshalJSON for type json.RawMessage: ${error.text()}');
		}
		return requireOutputParser(toJsonValue("metadata"));
		#else
		return toJsonValue("metadata");
		#end
	}

	/** Never hide a typed-parser mismatch after native syntax acceptance. */
	static function requireOutputParser(result:StoreResult<JsonValue>):StoreResult<JsonValue> {
		return switch result {
			case Success(value): Success(value);
			case Failure(_): Failure("metadata JSON is valid for Go but unsupported by the Haxe parser");
		};
	}

	/** Escape only the complete metadata token, preserving its formatting and raw tokens. */
	static function escapeJsonOutput(rendered:String):String {
		#if (go || go_output)
		final source:go.NativeSlice<go.NativeByte> = BytesPkg.newBufferString(rendered).bytes();
		final output = new Buffer();
		JsonPkg.htmlEscape(output, source);
		return output.stringValue();
		#else
		return rendered;
		#end
	}
}
