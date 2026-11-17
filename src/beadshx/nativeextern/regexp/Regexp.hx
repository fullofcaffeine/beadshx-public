package beadshx.nativeextern.regexp;

/** Exact Go regex behavior for compatibility patterns, including ASCII word boundaries. */
@:go.import("regexp")
@:go.name("Regexp")
extern class Regexp {
	@:go.name("MatchString")
	public function matchString(value:String):Bool;
}

@:go.import("regexp")
extern class RegexpPkg {
	@:go.name("MustCompile")
	public static function mustCompile(pattern:String):Regexp;
}
