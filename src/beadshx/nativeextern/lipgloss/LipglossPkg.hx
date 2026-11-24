package beadshx.nativeextern.lipgloss;

import beadshx.nativeextern.color.Color;
import beadshx.nativeextern.os.File;

/** The lipgloss v2 package functions that upstream's internal/ui builds its styles with. */
@:go.import("charm.land/lipgloss/v2")
@:go.package("lipgloss")
@:goNative
extern class LipglossPkg {
	/** `lipgloss.NewStyle()`: a style with no property set. */
	@:go.valueReturn
	@:go.name("NewStyle") public static function newStyle():Style;

	/**
		`lipgloss.Color(value)`: the RGB color of a `#rrggbb` or `#rgb` value,
		an ANSI color for a number, and `lipgloss.NoColor{}` for anything else,
		such as "".
	**/
	@:go.name("Color") public static function color(value:String):Color;

	/**
		`lipgloss.HasDarkBackground(input, output)`: asks the terminal for its
		background color, and answers true when it cannot, as when input or
		output is no terminal.

		The Go parameters are `term.File` interfaces. The extern narrows them to
		`*os.File`, the one concrete type passed, and the Go compiler still
		checks that it implements the interface.
	**/
	@:go.name("HasDarkBackground") public static function hasDarkBackground(input:File, output:File):Bool;
}
