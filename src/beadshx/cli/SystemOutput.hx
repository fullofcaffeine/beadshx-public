package beadshx.cli;

import beadshx.cli.AgentOutput.isAgentMode;
import beadshx.cli.AgentOutput.markdownWrapWidth;
import beadshx.cli.MarkdownRendering.escapeAngleBrackets;
import beadshx.cli.MarkdownRendering.shouldUseHyperlinks;
import beadshx.cli.MarkdownRendering.stripOsc8Hyperlinks;
import beadshx.cli.MarkdownRendering.unescapeAngleBrackets;
import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.cli.TerminalStyles.shouldUseColor;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.nativeextern.ansi.AnsiPkg;
import beadshx.nativeextern.glamour.GlamourPkg;
import beadshx.nativeextern.lipgloss.LipglossPkg;
import beadshx.nativeextern.os.File;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.term.TermPkg;

/** Owns the narrow process-stream effect for the native executable. */
@:goNative
final class SystemOutput implements OutputPort {
	public function new() {}

	public function writeStdout(value:String):Void {
		Sys.print(value);
	}

	public function writeStderr(value:String):Void {
		Sys.stderr().writeString(value);
	}

	/**
		Upstream uimd.RenderMarkdown (internal/uimd/markdown.go:43-96): stored
		issue text rendered by glamour for the terminal.

		Why: upstream renders each body section this way, and decides agent mode,
		colors and hyperlinks from the process environment each time, after its
		pre-run has loaded `.beads/.env`. What: the text as stored in agent mode;
		otherwise glamour's output at upstream's wrap width, with the dark style
		that GLAMOUR_STYLE can change when colors are on, or the plain `notty`
		style, whose tables, lists and wrapping still help, when they are off.
		OSC 8 hyperlinks stay only when upstream's hyperlink check allows them,
		and with neither colors nor hyperlinks no escape sequence stays. The text
		as stored again when glamour fails. How: angle brackets travel as HTML
		entities through glamour, so that it never reads issue text as raw HTML
		and drops it, and they come back after rendering.
	**/
	public function renderMarkdown(value:String):String {
		final wrapWidth = markdownWrapWidth(isAgentMode(environmentValue), stdoutColumns());
		if (wrapWidth == 0)
			return value;
		final terminal = isStdoutTerminal();
		final useAnsi = shouldUseColor(environmentValue, terminal);
		final useHyperlinks = shouldUseHyperlinks(environmentValue, terminal, decimal);
		final created = useAnsi ? GlamourPkg.newTermRenderer(GlamourPkg.withWordWrap(wrapWidth), GlamourPkg.withPreservedNewLines(),
			GlamourPkg.withTableWrap(false), GlamourPkg.withEnvironmentConfig(),
			GlamourPkg.withChromaFormatter("terminal256")) : GlamourPkg.newTermRenderer(GlamourPkg.withWordWrap(wrapWidth),
				GlamourPkg.withPreservedNewLines(), GlamourPkg.withTableWrap(false), GlamourPkg.withStandardStyle("notty"));
		final renderer = created.value1;
		if (created.value2 != null || renderer == null)
			return value;
		final rendered = renderer.render(escapeAngleBrackets(value));
		if (rendered.value2 != null)
			return value;
		var text = unescapeAngleBrackets(rendered.value1);
		if (!useHyperlinks)
			text = stripOsc8Hyperlinks(text);
		if (!useAnsi && !useHyperlinks)
			text = AnsiPkg.strip(text);
		return text;
	}

	public function usesJsonEnvelope():Bool {
		return Sys.getEnv("BD_JSON_ENVELOPE") == "1";
	}

	public function shouldEmitJsonDeprecation():Bool {
		return !usesJsonEnvelope() && isStderrTerminal();
	}

	public function isStdoutTerminal():Bool {
		return isTerminal(OsPkg.stdout);
	}

	public function isStderrTerminal():Bool {
		return isTerminal(OsPkg.stderr);
	}

	/**
		The column count of the terminal on stdout, or 0 when it is no terminal.

		Why: upstream's Markdown wrap width (internal/uimd WrapWidth) asks
		`term.GetSize(int(os.Stdout.Fd()))`. What: the width that call returns, or
		0 when it fails. How: `Fd()` returns a Go `uintptr`, which crosses the
		extern boundary as `go.NativeUintptr`; its explicit `toInt` is upstream's
		`int(...)` conversion, so the call is exact on Unix and on Windows.
	**/
	public function stdoutColumns():Int {
		final size = TermPkg.getSize(go.NativeUintptr.toInt(OsPkg.stdout.fd()));
		return size.value3 == null ? size.value1 : 0;
	}

	public function displayWidth(value:String):Int {
		return AnsiPkg.stringWidth(value);
	}

	public function hasDarkBackground():Bool {
		return LipglossPkg.hasDarkBackground(OsPkg.stdin, OsPkg.stdout);
	}

	public function textStyle(spec:StyleSpec):TextStyle {
		return new LipglossTextStyle(spec);
	}

	/**
		Upstream ui.IsTerminal and ui.IsStderrTerminal:
		`term.IsTerminal(int(file.Fd()))`. A nil `*os.File` has no terminal; its
		Go `Fd` gives the invalid descriptor, which is no terminal either.
	**/
	static function isTerminal(file:Null<File>):Bool {
		return file != null && TermPkg.isTerminal(go.NativeUintptr.toInt(file.fd()));
	}

	/** Go's strconv.Atoi: the int that `text` spells, or null when Atoi fails. */
	static function decimal(text:String):Null<Int> {
		final parsed = StrconvPkg.atoi(text);
		return parsed.value2 == null ? parsed.value1 : null;
	}
}
