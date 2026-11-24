package beadshx.cli;

import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;

/** Process output boundary used by handlers and deterministic tests. */
interface OutputPort {
	function writeStdout(value:String):Void;
	function writeStderr(value:String):Void;

	/** Renders stored Markdown with the native terminal's wrapping policy. */
	function renderMarkdown(value:String):String;

	/** Reports whether stdout JSON uses the versioned data envelope. */
	function usesJsonEnvelope():Bool;

	/** Reports whether JSON output needs the legacy terminal migration notice. */
	function shouldEmitJsonDeprecation():Bool;

	/** Reports whether stdout is attached to a terminal. */
	function isStdoutTerminal():Bool;

	/** Reports whether stderr is attached to a terminal. */
	function isStderrTerminal():Bool;

	/** The column count of the terminal on stdout, or 0 when stdout is no terminal or its size cannot be read. */
	function stdoutColumns():Int;

	/** The terminal cells that `value` takes, as upstream's ansi.StringWidth counts them. */
	function displayWidth(value:String):Int;

	/**
		Whether the terminal has a dark background, as upstream's
		`lipgloss.HasDarkBackground(os.Stdin, os.Stdout)` answers when colors are
		on: true when stdin or stdout is no terminal or the terminal does not say.
	**/
	function hasDarkBackground():Bool;

	/** Builds the native style that upstream's internal/ui builds for `spec`. */
	function textStyle(spec:StyleSpec):TextStyle;
}
