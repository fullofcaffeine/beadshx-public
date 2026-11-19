package beadshx.nativeextern.exec;

/** Exact standard-library process construction; the process runs in the current directory. */
@:go.import("os/exec")
@:go.package("exec")
@:goNative
extern class ExecPkg {
	@:go.name("Command") public static function command(name:String, arguments:haxe.Rest<String>):Cmd;
}
