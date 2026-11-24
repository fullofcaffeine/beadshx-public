package beadshx.nativeextern.lipgloss;

import beadshx.nativeextern.color.Color;

/**
	A lipgloss v2 `Style` value: the subset that upstream's internal/ui sets
	and renders with.

	Each setter returns a changed copy, as in Go. `render` writes one SGR
	sequence per line of the text, pads shorter lines to the widest one when
	any property is set, and turns each tab into four spaces even for an empty
	style. It never lowers a 24-bit color to the terminal's profile.
**/
@:go.import("charm.land/lipgloss/v2")
@:go.package("lipgloss")
@:go.name("Style")
@:go.struct
@:goNative
extern class Style {
	@:go.valueReturn
	@:go.name("Foreground") public function foreground(color:Color):Style;

	@:go.valueReturn
	@:go.name("Bold") public function bold(value:Bool):Style;

	@:go.name("Render") public function render(text:haxe.Rest<String>):String;
}
