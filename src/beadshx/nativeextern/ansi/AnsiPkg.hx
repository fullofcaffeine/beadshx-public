package beadshx.nativeextern.ansi;

/** The exact `charmbracelet/x/ansi` text functions that upstream's show and Markdown renderer use. */
@:go.import("github.com/charmbracelet/x/ansi")
@:go.package("ansi")
@:goNative
extern class AnsiPkg {
	/** The terminal cells of `value` as grapheme clusters: escape sequences count 0, wide characters 2. */
	@:go.name("StringWidth") public static function stringWidth(value:String):Int;

	/** `ansi.Strip(value)`: `value` without its ANSI escape sequences. */
	@:go.name("Strip") public static function strip(value:String):String;
}
