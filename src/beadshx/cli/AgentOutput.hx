package beadshx.cli;

/**
	Upstream ui.IsAgentMode: whether output is for an AI agent.

	Why: upstream reads the two variables each time it renders, after its
	pre-run has loaded `.beads/.env` into the process environment, so either
	variable counts from that file too. What: true when BD_AGENT_MODE is
	exactly `1` or CLAUDE_CODE has any non-empty value. How: `value` returns a
	variable's value, or "" when it is unset.
**/
function isAgentMode(value:String->String):Bool {
	return value("BD_AGENT_MODE") == "1" || value("CLAUDE_CODE") != "";
}

/**
	Upstream uimd.WrapWidth: the column count that upstream wraps Markdown body
	text to, or 0 in agent mode, where the text is printed as stored.

	Outside agent mode it is the column count of the terminal on stdout, 80 when
	stdout is no terminal or reports 0 columns, and at most 100.
	`terminalColumns` is that column count, or 0 when it cannot be read.
**/
function markdownWrapWidth(agentMode:Bool, terminalColumns:Int):Int {
	if (agentMode)
		return 0;
	final width = terminalColumns > 0 ? terminalColumns : 80;
	return width > 100 ? 100 : width;
}

/**
	Upstream fitsMetadataLine in show: whether `line` stays on one metadata line
	instead of becoming a rendered section.

	A line with a line feed or carriage return never fits. Any other line fits
	when `wrapWidth` is 0 (agent mode), or when its `displayWidth`, the terminal
	cells that upstream's ansi.StringWidth counts for it, is at most `wrapWidth`.
**/
function fitsMetadataLine(line:String, wrapWidth:Int, displayWidth:Int):Bool {
	if (line.indexOf("\n") >= 0 || line.indexOf("\r") >= 0)
		return false;
	return wrapWidth == 0 || displayWidth <= wrapWidth;
}
