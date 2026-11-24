import beadshx.cli.AgentOutput.fitsMetadataLine;
import beadshx.cli.AgentOutput.isAgentMode;
import beadshx.cli.AgentOutput.markdownWrapWidth;

/**
	Pins upstream's agent mode detection (ui.IsAgentMode), the Markdown wrap
	width (uimd.WrapWidth) and show's metadata line fit (fitsMetadataLine), by
	hand. The terminal widths here cannot reach the parity suite, whose stdout
	is a pipe; parity covers the real runs.
**/
class Main {
	static function main():Void {
		detectionContracts();
		wrapWidthContracts();
		metadataLineContracts();
		Sys.println("agent output Haxe contracts: PASS");
	}

	static function detectionContracts():Void {
		equal(isAgentMode(environment([])), false);
		equal(isAgentMode(environment(["BD_AGENT_MODE" => "1"])), true);
		// Only the exact value 1 counts for BD_AGENT_MODE.
		equal(isAgentMode(environment(["BD_AGENT_MODE" => "true"])), false);
		equal(isAgentMode(environment(["BD_AGENT_MODE" => " 1"])), false);
		equal(isAgentMode(environment(["BD_AGENT_MODE" => "0"])), false);
		// Any non-empty CLAUDE_CODE counts, also 0; an empty one does not.
		equal(isAgentMode(environment(["CLAUDE_CODE" => "0"])), true);
		equal(isAgentMode(environment(["CLAUDE_CODE" => ""])), false);
		equal(isAgentMode(environment(["BD_AGENT_MODE" => "0", "CLAUDE_CODE" => "1"])), true);
	}

	static function wrapWidthContracts():Void {
		equal(markdownWrapWidth(true, 120), 0);
		equal(markdownWrapWidth(true, 0), 0);
		// No terminal, or a terminal that reports 0 columns: 80.
		equal(markdownWrapWidth(false, 0), 80);
		equal(markdownWrapWidth(false, -1), 80);
		equal(markdownWrapWidth(false, 1), 1);
		equal(markdownWrapWidth(false, 72), 72);
		equal(markdownWrapWidth(false, 100), 100);
		equal(markdownWrapWidth(false, 101), 100);
		equal(markdownWrapWidth(false, 240), 100);
	}

	static function metadataLineContracts():Void {
		equal(fitsMetadataLine("Close reason: done", 80, 18), true);
		equal(fitsMetadataLine("x", 80, 80), true);
		equal(fitsMetadataLine("x", 80, 81), false);
		// Agent mode has no width limit, but a line break still never fits.
		equal(fitsMetadataLine("x", 0, 500), true);
		equal(fitsMetadataLine("a\nb", 0, 3), false);
		equal(fitsMetadataLine("a\rb", 0, 3), false);
		equal(fitsMetadataLine("a\nb", 80, 3), false);
	}

	static function environment(values:Map<String, String>):String->String {
		return name -> {
			final value = values.get(name);
			return value == null ? "" : value;
		};
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
