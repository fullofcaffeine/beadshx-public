package beadshx.cli;

import beadshx.store.SchemaSkew.SchemaSkewWarning;

/**
	The command's output, which writes a held schema skew warning first.

	Why: with BD_IGNORE_SCHEMA_SKEW=1 upstream prints its warning when the
	pre-run opens the store, before any output of the command. The embedded
	check here holds that warning until the command writes (see
	`SchemaSkewWarning`), so a native facade open that warns by itself does
	not print it twice.
	What: every write, and `flushHeldWarning` at the end of the command, first
	writes the held warning on stderr. Everything else goes to `streams`.
**/
final class SchemaSkewWarningOutput implements OutputPort {
	final streams:OutputPort;

	public function new(streams:OutputPort) {
		this.streams = streams;
	}

	public function flushHeldWarning():Void {
		final warning = SchemaSkewWarning.take();
		if (warning != null)
			streams.writeStderr(warning);
	}

	public function writeStdout(value:String):Void {
		flushHeldWarning();
		streams.writeStdout(value);
	}

	public function writeStderr(value:String):Void {
		flushHeldWarning();
		streams.writeStderr(value);
	}

	public function renderMarkdown(value:String):String {
		return streams.renderMarkdown(value);
	}

	public function usesJsonEnvelope():Bool {
		return streams.usesJsonEnvelope();
	}

	public function shouldEmitJsonDeprecation():Bool {
		return streams.shouldEmitJsonDeprecation();
	}

	public function isStdoutTerminal():Bool {
		return streams.isStdoutTerminal();
	}

	public function isStderrTerminal():Bool {
		return streams.isStderrTerminal();
	}
}
