package beadshx.cli;

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
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/terminalfacade")
private extern class NativeTerminalFacade {
	@:go.name("IsStderrTerminal") static function isStderrTerminal():Bool;
	@:go.name("IsStdoutTerminal") static function isStdoutTerminal():Bool;
	@:go.name("RenderMarkdown") static function renderMarkdown(value:String):String;
}
