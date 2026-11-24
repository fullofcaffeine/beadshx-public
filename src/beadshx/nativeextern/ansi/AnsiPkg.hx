package beadshx.nativeextern.ansi;

/** The exact `charmbracelet/x/ansi` cell width that upstream's show compares with the wrap width. */
@:go.import("github.com/charmbracelet/x/ansi")
@:go.package("ansi")
@:goNative
extern class AnsiPkg {
	/** The terminal cells of `value` as grapheme clusters: escape sequences count 0, wide characters 2. */
	@:go.name("StringWidth") public static function stringWidth(value:String):Int;
}
