package beadshx.nativeextern.os;

/** Exact standard-library user directories, with their platform rules and errors. */
@:go.import("os")
@:go.package("os")
@:goNative
extern class OsPkg {
	@:go.tupleReturn
	@:go.name("UserHomeDir") public static function userHomeDir():PathResult;

	@:go.tupleReturn
	@:go.name("UserConfigDir") public static function userConfigDir():PathResult;
}
