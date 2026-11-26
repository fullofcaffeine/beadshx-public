package beadshx.cli;

/**
	Upstream ui.ShouldUseHyperlinks (internal/ui/terminal.go:66-131): whether
	upstream's Markdown renderer keeps the OSC 8 hyperlinks that glamour writes.

	Why: OSC 8 support does not follow from ANSI color support, so upstream
	decides it apart from colors, each time it renders, after its pre-run has
	loaded `.beads/.env` into the process environment. What: false when
	BD_GIT_HOOK is exactly `1`, NO_COLOR is not empty, CLICOLOR is exactly `0`
	or TERM is `dumb` in any letter case; then true when FORCE_HYPERLINK is
	neither empty nor `0`; then false when stdout is no terminal; then true for
	the terminals that upstream lists by marker variable, TERM_PROGRAM or TERM;
	then, when VTE_VERSION is set, whether it is a version from 5000; otherwise
	false. How: `value` returns a variable's value, or "" when it is unset.
	`decimal` is Go's strconv.Atoi: the int that a text spells, or null when
	Atoi fails.
**/
function shouldUseHyperlinks(value:String->String, stdoutIsTerminal:Bool, decimal:String->Null<Int>):Bool {
	if (value("BD_GIT_HOOK") == "1")
		return false;
	if (value("NO_COLOR") != "")
		return false;
	if (value("CLICOLOR") == "0")
		return false;
	if (value("TERM").toLowerCase() == "dumb")
		return false;
	final force = value("FORCE_HYPERLINK");
	if (force != "" && force != "0")
		return true;
	if (!stdoutIsTerminal)
		return false;
	final markers = [
		"WT_SESSION",
		"KITTY_WINDOW_ID",
		"WEZTERM_EXECUTABLE",
		"KONSOLE_VERSION",
		"DOMTERM",
		"GHOSTTY_RESOURCES_DIR"
	];
	for (marker in markers)
		if (value(marker) != "")
			return true;
	if (["iterm.app", "wezterm", "vscode", "apple_terminal", "tabby", "hyper", "ghostty"].contains(value("TERM_PROGRAM").toLowerCase()))
		return true;
	final termName = value("TERM").toLowerCase();
	for (name in ["xterm-kitty", "wezterm", "foot", "contour", "ghostty"])
		if (termName.indexOf(name) >= 0)
			return true;
	final vte = value("VTE_VERSION");
	if (vte != "") {
		final version = decimal(vte);
		return version != null && version >= 5000;
	}
	return false;
}

/**
	Upstream uimd's escapeAngleBrackets: `text` with each `<` and `>` as the
	entity `&lt;` or `&gt;`, so that glamour's Markdown parser never reads a
	tag-shaped span of issue text as raw HTML, which its renderer would drop.
**/
function escapeAngleBrackets(text:String):String {
	return StringTools.replace(StringTools.replace(text, "<", "&lt;"), ">", "&gt;");
}

/**
	Upstream uimd's unescapeAngleBrackets: the rendered `text` with each `&lt;`
	and `&gt;` back as `<` and `>`. Glamour leaves the entities of the escaped
	text as they are. The two entities cannot overlap, and neither replacement
	makes the other entity, so two passes equal upstream's one strings.Replacer.
**/
function unescapeAngleBrackets(text:String):String {
	return StringTools.replace(StringTools.replace(text, "&lt;", "<"), "&gt;", ">");
}

/**
	Upstream uimd's stripOSC8Hyperlinks: `text` without its OSC 8 hyperlink
	sequences, with every other escape sequence, such as an SGR color, kept.

	Each sequence starts with `ESC ] 8 ;` and ends at the first BEL or
	`ESC \` after it. A start with no end stays, and so does everything after
	it, as in upstream's byte loop.
**/
function stripOsc8Hyperlinks(text:String):String {
	final start = "\x1b]8;";
	if (text.indexOf(start) < 0)
		return text;
	final stripped = new StringBuf();
	var position = 0;
	while (true) {
		final found = text.indexOf(start, position);
		if (found < 0)
			break;
		final end = oscSequenceEnd(text, found + start.length);
		if (end < 0)
			break;
		stripped.add(text.substring(position, found));
		position = end;
	}
	stripped.add(text.substring(position));
	return stripped.toString();
}

/** Upstream uimd's oscSequenceEnd: the index after the first BEL or `ESC \` from `from`, or -1 when there is none. */
private function oscSequenceEnd(text:String, from:Int):Int {
	final bell = text.indexOf("\x07", from);
	final stringTerminator = text.indexOf("\x1b\\", from);
	if (bell >= 0 && (stringTerminator < 0 || bell < stringTerminator))
		return bell + 1;
	return stringTerminator >= 0 ? stringTerminator + 2 : -1;
}
