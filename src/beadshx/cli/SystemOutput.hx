package beadshx.cli;

import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.nativeextern.ansi.AnsiPkg;
import beadshx.nativeextern.lipgloss.LipglossPkg;
import beadshx.nativeextern.os.OsPkg;
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

	public function renderMarkdown(value:String):String {
		return NativeTerminalFacade.renderMarkdown(value);
	}

	public function usesJsonEnvelope():Bool {
		return Sys.getEnv("BD_JSON_ENVELOPE") == "1";
	}

	public function shouldEmitJsonDeprecation():Bool {
		return !usesJsonEnvelope() && NativeTerminalFacade.isStderrTerminal();
	}

	public function isStdoutTerminal():Bool {
		return NativeTerminalFacade.isStdoutTerminal();
	}

	public function isStderrTerminal():Bool {
		return NativeTerminalFacade.isStderrTerminal();
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
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/terminalfacade")
private extern class NativeTerminalFacade {
	@:go.name("IsStderrTerminal") static function isStderrTerminal():Bool;
	@:go.name("IsStdoutTerminal") static function isStdoutTerminal():Bool;
	@:go.name("RenderMarkdown") static function renderMarkdown(value:String):String;
}
