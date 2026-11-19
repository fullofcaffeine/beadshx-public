package beadshx.nativeextern.strings;

/** Exact standard-library replacer construction. */
@:go.import("strings")
@:go.package("strings")
@:goNative
extern class StringsPkg {
	@:go.name("NewReplacer") public static function newReplacer(oldNew:haxe.Rest<String>):Replacer;
}
