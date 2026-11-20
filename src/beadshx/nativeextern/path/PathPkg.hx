package beadshx.nativeextern.path;

/** Exact standard-library glob matching for slash-separated names. */
@:go.import("path")
@:go.package("path")
@:goNative
extern class PathPkg {
	@:go.tupleReturn
	@:go.name("Match") public static function match(pattern:String, name:String):MatchResult;
}
