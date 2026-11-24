package beadshx.nativeextern.strings;

/** Exact standard-library replacer construction and case folding. */
@:go.import("strings")
@:go.package("strings")
@:goNative
extern class StringsPkg {
	@:go.name("NewReplacer") public static function newReplacer(oldNew:haxe.Rest<String>):Replacer;

	/**
		Go's strings.EqualFold: whether `s` and `t` are equal under simple
		Unicode case folding, so `ſ` (U+017F) matches `s` but `İ` (U+0130) does
		not match `i`. Upstream compares some mode words this way, where
		`toLowerCase` (strings.ToLower) differs for those runes.
	**/
	@:go.name("EqualFold") public static function equalFold(s:String, t:String):Bool;
}
