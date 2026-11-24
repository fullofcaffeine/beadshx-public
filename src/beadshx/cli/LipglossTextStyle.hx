package beadshx.cli;

import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.nativeextern.lipgloss.LipglossPkg;
import beadshx.nativeextern.lipgloss.Style;

/**
	A `StyleSpec` built as the lipgloss v2 style that upstream's internal/ui
	builds, so its output is upstream's byte for byte.

	`DefaultForeground` passes `lipgloss.Color("")`, which is the
	`lipgloss.NoColor{}` value that upstream sets.
**/
@:goNative
final class LipglossTextStyle implements TextStyle {
	final style:Style;

	public function new(spec:StyleSpec) {
		var built = LipglossPkg.newStyle();
		switch spec.foreground {
			case NoForeground:
			case DefaultForeground:
				built = built.foreground(LipglossPkg.color(""));
			case HexForeground(hex):
				built = built.foreground(LipglossPkg.color(hex));
		}
		if (spec.bold)
			built = built.bold(true);
		style = built;
	}

	public function render(text:String):String {
		return style.render(text);
	}
}
