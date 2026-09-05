package beadshx.store;

/**
	Exact JSON integer spelling for native values wider than Haxe's Int.

	The native boundary supplies base-10 text because revision tokens can exceed
	the safe integer range of JavaScript-compatible JSON number helpers. Parsing
	validates the protocol spelling once; renderers can then emit it unquoted.
**/
abstract JsonInteger(String) {
	private inline function new(value:String) {
		this = value;
	}

	public static function parse(value:String):StoreResult<JsonInteger> {
		if (value == "")
			return Failure("native store returned an empty JSON integer");
		var index = value.charCodeAt(0) == 45 ? 1 : 0;
		if (index == value.length)
			return Failure('native store returned an invalid JSON integer: ${value}');
		while (index < value.length) {
			final code = value.charCodeAt(index);
			if (code < 48 || code > 57)
				return Failure('native store returned an invalid JSON integer: ${value}');
			index++;
		}
		return Success(new JsonInteger(value));
	}

	public inline function wireValue():String {
		return this;
	}
}
