package beadshx.cli;

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
}
