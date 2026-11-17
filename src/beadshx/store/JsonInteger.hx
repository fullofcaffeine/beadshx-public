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
		if (value.charCodeAt(index) == 48 && index + 1 < value.length)
			return Failure('native store returned an invalid JSON integer: ${value}');
		while (index < value.length) {
			final code = value.charCodeAt(index);
			if (code < 48 || code > 57)
				return Failure('native store returned an invalid JSON integer: ${value}');
			index++;
		}
		return Success(new JsonInteger(value));
	}

	/** Source Int values are integral; this factory never performs arithmetic. */
	@:from public static function fromInt(value:Int):JsonInteger {
		return new JsonInteger(Std.string(value));
	}

	/** Compare exact signed decimals without narrowing to Int or Float. */
	public function compare(other:JsonInteger):Int {
		final left:String = this;
		final right = other.wireValue();
		final leftNegative = left.charAt(0) == "-" && left != "-0";
		final rightNegative = right.charAt(0) == "-" && right != "-0";
		if (leftNegative != rightNegative)
			return leftNegative ? -1 : 1;
		final leftDigits = left.charAt(0) == "-" ? left.substr(1) : left;
		final rightDigits = right.charAt(0) == "-" ? right.substr(1) : right;
		final order = leftDigits.length < rightDigits.length ? -1 : leftDigits.length > rightDigits.length ? 1 : leftDigits < rightDigits ? -1 : leftDigits > rightDigits ? 1 : 0;
		return leftNegative ? -order : order;
	}

	public inline function wireValue():String {
		return this;
	}
}
