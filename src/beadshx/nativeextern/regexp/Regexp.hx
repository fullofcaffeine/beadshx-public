package beadshx.nativeextern.regexp;

/** Exact Go regex behavior for compatibility patterns, including ASCII word boundaries. */
@:go.import("regexp")
@:go.name("Regexp")
extern class Regexp {
	@:go.name("MatchString")
	public function matchString(value:String):Bool;

	/** The leftmost match and its groups, with "" for a group that took no part; empty when nothing matches. */
	@:go.name("FindStringSubmatch")
	public function findStringSubmatch(value:String):go.NativeStringSlice;
}

@:go.import("regexp")
extern class RegexpPkg {
	@:go.name("MustCompile")
	public static function mustCompile(pattern:String):Regexp;
}
