package beadshx.nativeextern.viper;

/** Exact spf13/viper construction of a private registry. */
@:go.import("github.com/spf13/viper")
@:go.package("viper")
@:goNative
extern class ViperPkg {
	@:go.name("New") public static function create():Viper;
}
