package beadshx.cli;

import beadshx.nativeextern.ansi.AnsiPkg;

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
		The column count of the terminal on stdout, or 0 when it is unknown.

		Why: upstream's Markdown wrap width asks `term.GetSize(int(os.Stdout.Fd()))`.
		`Fd()` returns a Go `uintptr`, and the pinned haxe.go has no typed carrier
		for it yet (haxe_go-5yip), so no typed extern can make that call for every
		OS. What: this build always returns 0, so the wrap width falls back to
		upstream's 80 columns. How: callers treat 0 as "not a terminal"; the README
		lists the difference as a limit until the carrier lands.
	**/
	public function stdoutColumns():Int {
		return 0;
	}

	public function displayWidth(value:String):Int {
		return AnsiPkg.stringWidth(value);
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/terminalfacade")
private extern class NativeTerminalFacade {
	@:go.name("IsStderrTerminal") static function isStderrTerminal():Bool;
	@:go.name("IsStdoutTerminal") static function isStdoutTerminal():Bool;
	@:go.name("RenderMarkdown") static function renderMarkdown(value:String):String;
}
