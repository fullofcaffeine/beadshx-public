package beadshx.nativeextern.filepath;

import beadshx.nativeextern.os.PathResult;

/** Exact standard-library path algebra, so config paths compare like upstream's. */
@:go.import("path/filepath")
@:go.package("filepath")
@:goNative
extern class FilepathPkg {
	@:go.name("Clean") public static function clean(path:String):String;
	@:go.name("Join") public static function join(elements:haxe.Rest<String>):String;
	@:go.name("Dir") public static function dir(path:String):String;
	@:go.name("Base") public static function base(path:String):String;
	@:go.name("IsAbs") public static function isAbs(path:String):Bool;

	@:go.tupleReturn
	@:go.name("EvalSymlinks") public static function evalSymlinks(path:String):PathResult;

	/** `filepath.Split`: the path up to and including its last separator, and the rest. */
	@:go.tupleReturn
	@:go.name("Split") public static function split(path:String):SplitResult;

	/** `filepath.Abs`: the path joined to the working directory that `os.Getwd` reports, then cleaned. */
	@:go.tupleReturn
	@:go.name("Abs") public static function abs(path:String):PathResult;
}
