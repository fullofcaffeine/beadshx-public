package beadshx.nativeextern.os;

/** Exact standard-library user directories, file information and process lookup, with their platform rules and errors. */
@:go.import("os")
@:go.package("os")
@:goNative
extern class OsPkg {
	@:go.tupleReturn
	@:go.name("UserHomeDir") public static function userHomeDir():PathResult;

	@:go.tupleReturn
	@:go.name("UserConfigDir") public static function userConfigDir():PathResult;

	@:go.tupleReturn
	@:go.name("Stat") public static function stat(path:String):StatResult;

	@:go.name("IsNotExist") public static function isNotExist(error:go.NativeError):Bool;

	/** The process environment as `key=value` entries, in the process's own order. */
	@:go.name("Environ") public static function environ():go.NativeStringSlice;

	/** On Unix this always succeeds without touching the process; `Process.signal` then probes it. */
	@:go.tupleReturn
	@:go.name("FindProcess") public static function findProcess(pid:Int):FindProcessResult;
}
