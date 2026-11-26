import beadshx.cli.TerminalStyles;
import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.cli.TerminalStyles.shouldUseColor;
import beadshx.cli.MarkdownRendering.escapeAngleBrackets;
import beadshx.cli.MarkdownRendering.shouldUseHyperlinks;
import beadshx.cli.MarkdownRendering.stripOsc8Hyperlinks;
import beadshx.cli.MarkdownRendering.unescapeAngleBrackets;

/**
	Pins upstream's color decision (internal/ui/terminal.go:32-64), the style
	of each upstream ui style for each background (styles.go:139-261) and the
	render helpers (styles.go:286-599), by hand. A marker style stands in for
	lipgloss: it prints the spec it was built from. Parity covers the real
	escape sequences, and the pipe cases; a terminal on stdout cannot reach it.
	Also pins the hyperlink decision (terminal.go:66-131) and the text steps
	around glamour in upstream's Markdown renderer (internal/uimd).
**/
final class Main {
	static var failures = 0;

	static function main():Void {
		decisionContracts();
		plainContracts();
		darkContracts();
		lightContracts();
		hyperlinkContracts();
		markdownTextContracts();
		if (failures > 0) {
			Sys.println('terminal styles Haxe contracts: ${failures} failure(s)');
			Sys.exit(1);
		}
		Sys.println("terminal styles Haxe contracts: PASS");
	}

	static function decisionContracts():Void {
		// No variable: a terminal on stdout decides.
		equal(shouldUseColor(environment([]), true), true);
		equal(shouldUseColor(environment([]), false), false);
		// Any non-empty CLICOLOR_FORCE forces colors, also 0; an empty one does not.
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1"]), false), true);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "0"]), false), true);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => ""]), false), false);
		// NO_COLOR, CLICOLOR=0 and BD_GIT_HOOK=1 win over CLICOLOR_FORCE.
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "NO_COLOR" => "1"]), true), false);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "NO_COLOR" => "0"]), true), false);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "NO_COLOR" => ""]), true), true);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "CLICOLOR" => "0"]), true), false);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "CLICOLOR" => "00"]), true), true);
		equal(shouldUseColor(environment(["CLICOLOR" => "1"]), false), false);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "BD_GIT_HOOK" => "1"]), true), false);
		equal(shouldUseColor(environment(["CLICOLOR_FORCE" => "1", "BD_GIT_HOOK" => "true"]), true), true);
		// TERM=dumb, in any case, turns off a terminal's colors, but not forced ones.
		equal(shouldUseColor(environment(["TERM" => "dumb"]), true), false);
		equal(shouldUseColor(environment(["TERM" => "DUMB"]), true), false);
		equal(shouldUseColor(environment(["TERM" => "dumb "]), true), true);
		equal(shouldUseColor(environment(["TERM" => "dumb", "CLICOLOR_FORCE" => "1"]), false), true);
		equal(shouldUseColor(environment(["TERM" => "xterm"]), true), true);
		equal(shouldUseColor(environment(["TERM" => "xterm"]), false), false);
	}

	static function hyperlinkContracts():Void {
		function decide(values:Map<String, String>, terminal:Bool):Bool {
			return shouldUseHyperlinks(environment(values), terminal, decimal);
		}
		// No variable: no hyperlinks, on a terminal or a pipe.
		equal(decide([], true), false);
		equal(decide([], false), false);
		// FORCE_HYPERLINK other than 0 forces them, also on a pipe; 0 and "" do not.
		equal(decide(["FORCE_HYPERLINK" => "1"], false), true);
		equal(decide(["FORCE_HYPERLINK" => "yes"], false), true);
		equal(decide(["FORCE_HYPERLINK" => "0"], false), false);
		equal(decide(["FORCE_HYPERLINK" => "0", "TERM_PROGRAM" => "vscode"], true), true);
		// BD_GIT_HOOK=1, NO_COLOR, CLICOLOR=0 and TERM=dumb win over FORCE_HYPERLINK.
		equal(decide(["FORCE_HYPERLINK" => "1", "BD_GIT_HOOK" => "1"], true), false);
		equal(decide(["FORCE_HYPERLINK" => "1", "NO_COLOR" => "0"], true), false);
		equal(decide(["FORCE_HYPERLINK" => "1", "CLICOLOR" => "0"], true), false);
		equal(decide(["FORCE_HYPERLINK" => "1", "TERM" => "Dumb"], true), false);
		equal(decide(["FORCE_HYPERLINK" => "1", "CLICOLOR_FORCE" => "1"], false), true);
		// On a terminal, the listed marker variables, programs and TERM names allow them; on a pipe nothing does.
		equal(decide(["WT_SESSION" => "x"], true), true);
		equal(decide(["WT_SESSION" => "x"], false), false);
		equal(decide(["KITTY_WINDOW_ID" => "1"], true), true);
		equal(decide(["WEZTERM_EXECUTABLE" => "w"], true), true);
		equal(decide(["KONSOLE_VERSION" => "1"], true), true);
		equal(decide(["DOMTERM" => "1"], true), true);
		equal(decide(["GHOSTTY_RESOURCES_DIR" => "/g"], true), true);
		equal(decide(["TERM_PROGRAM" => "iTerm.app"], true), true);
		equal(decide(["TERM_PROGRAM" => "Apple_Terminal"], true), true);
		equal(decide(["TERM_PROGRAM" => "ghostty"], true), true);
		equal(decide(["TERM_PROGRAM" => "tmux"], true), false);
		equal(decide(["TERM" => "xterm-kitty"], true), true);
		equal(decide(["TERM" => "foot-extra"], true), true);
		equal(decide(["TERM" => "XTERM-GHOSTTY"], true), true);
		equal(decide(["TERM" => "xterm-256color"], true), false);
		// VTE_VERSION allows them from 5000, as Go's Atoi reads it.
		equal(decide(["VTE_VERSION" => "5000"], true), true);
		equal(decide(["VTE_VERSION" => "+6003"], true), true);
		equal(decide(["VTE_VERSION" => "4999"], true), false);
		equal(decide(["VTE_VERSION" => "50.0"], true), false);
		equal(decide(["VTE_VERSION" => "6003", "TERM_PROGRAM" => "tmux"], false), false);
	}

	static function markdownTextContracts():Void {
		// Angle brackets travel through glamour as entities and come back.
		equal(escapeAngleBrackets("a<b> & <c>"), "a&lt;b&gt; & &lt;c&gt;");
		equal(unescapeAngleBrackets("a&lt;b&gt; &amp;lt; &&lt;gt;"), "a<b> &amp;lt; &<gt;");
		equal(unescapeAngleBrackets(escapeAngleBrackets("x <y\n> z")), "x <y\n> z");
		// OSC 8 sequences end at BEL or ESC \; other escapes stay.
		final link = "\x1b]8;id=1;https://example.com\x07docs\x1b]8;;\x07";
		equal(stripOsc8Hyperlinks("\x1b[1mSee\x1b[m " + link + "."), "\x1b[1mSee\x1b[m docs.");
		equal(stripOsc8Hyperlinks("\x1b]8;;https://a\x1b\\A\x1b]8;;\x1b\\"), "A");
		equal(stripOsc8Hyperlinks("\x1b]8;;https://a\x1b[mB\x07C"), "C");
		// A start without an end stays, with everything after it.
		equal(stripOsc8Hyperlinks(link + " \x1b]8;;open"), "docs \x1b]8;;open");
		equal(stripOsc8Hyperlinks("plain"), "plain");
	}

	/** Go's strconv.Atoi for the contracts: an optional sign, then decimal digits only. */
	static function decimal(text:String):Null<Int> {
		return ~/^[+-]?[0-9]+$/.match(text) ? Std.parseInt(StringTools.replace(text, "+", "")) : null;
	}

	static function plainContracts():Void {
		final styles = TerminalStyles.plain(marker);
		// Every style is the empty one; the open and custom icons and an unknown type are never styled.
		equal(styles.renderStatusIcon("open"), "○");
		equal(styles.renderStatusIcon("closed"), "<->✓");
		equal(styles.renderStatusIcon("deferred"), "<->❄");
		equal(styles.renderStatusIcon("review"), "◇");
		equal(styles.renderPriority(0), "<->P0");
		equal(styles.renderPriority(4), "<->P4");
		equal(styles.renderType("bug"), "<->bug");
		equal(styles.renderType("decision"), "decision");
		equal(styles.renderStatus("open"), "<->open");
		equal(styles.renderId("x-1"), "<->x-1");
		equal(styles.renderMuted("m"), "<->m");
		equal(styles.renderClosedLine("l"), "<->l");
		equal(styles.bold.render("b"), "<->b");
		equal(styles.command.render("c"), "<->c");
		equal(styles.renderFail("f"), "<->f");
		equal(styles.renderBold("b"), "<->b");
		equal(styles.statusStyle("closed").render("s"), "<->s");
		equal(styles.statusStyle("open").render("s"), "<->s");
		// Upstream's FailStyle.Bold(true) and PassStyle.Bold(true) stay bold with colors off.
		equal(styles.passBold.render("r"), "<-+bold>r");
		equal(styles.failBold.render("b"), "<-+bold>b");
		equal(styles.renderStatusId("hooked", "x"), "x");
	}

	static function darkContracts():Void {
		final styles = TerminalStyles.colored(true, marker);
		equal(styles.renderStatusIcon("open"), "○");
		equal(styles.renderStatusIcon("in_progress"), "<#ffb454>◐");
		equal(styles.renderStatusIcon("blocked"), "<#f26d78>●");
		equal(styles.renderStatusIcon("closed"), "<#8090a0>✓");
		equal(styles.renderStatusIcon("deferred"), "<#6c7680>❄");
		equal(styles.renderStatusIcon("pinned"), "<#d2a6ff>📌");
		// hooked has a status style but no icon of its own.
		equal(styles.renderStatusIcon("hooked"), "◇");
		equal(styles.renderPriority(0), "<#f07178+bold>P0");
		equal(styles.renderPriority(1), "<#ff8f40>P1");
		equal(styles.renderPriority(2), "<#e6b450>P2");
		equal(styles.renderPriority(3), "<default>P3");
		equal(styles.renderPriority(4), "<default>P4");
		equal(styles.renderPriority(5), "P5");
		equal(styles.renderPriority(-1), "P-1");
		equal(styles.renderType("bug"), "<#f26d78>bug");
		equal(styles.renderType("epic"), "<#d2a6ff>epic");
		equal(styles.renderType("feature"), "<default>feature");
		equal(styles.renderType("task"), "<default>task");
		equal(styles.renderType("chore"), "<default>chore");
		equal(styles.renderType("gate"), "gate");
		equal(styles.renderStatus("in_progress"), "<#ffb454>in_progress");
		equal(styles.renderStatus("blocked"), "<#f26d78>blocked");
		equal(styles.renderStatus("pinned"), "<#d2a6ff>pinned");
		equal(styles.renderStatus("hooked"), "<#59c2ff>hooked");
		equal(styles.renderStatus("closed"), "<#8090a0>closed");
		equal(styles.renderStatus("open"), "<default>open");
		equal(styles.renderStatus("deferred"), "<default>deferred");
		equal(styles.renderId("x-1"), "<default>x-1");
		equal(styles.renderPass("p"), "<#c2d94c>p");
		equal(styles.renderWarn("w"), "<#ffb454>w");
		equal(styles.fail.render("f"), "<#f07178>f");
		equal(styles.renderMuted("m"), "<#6c7680>m");
		equal(styles.renderAccent("a"), "<#59c2ff>a");
		equal(styles.renderClosedLine("l"), "<#8090a0>l");
		equal(styles.category.render("c"), "<#59c2ff+bold>c");
		equal(styles.bold.render("b"), "<-+bold>b");
		equal(styles.command.render("c"), "<#bfbdb6>c");
		equal(styles.renderFail("f"), "<#f07178>f");
		equal(styles.renderBold("b"), "<-+bold>b");
		// ui.GetStatusStyle: deferred is muted, and open, custom and unknown statuses take the empty style.
		equal(styles.statusStyle("in_progress").render("s"), "<#ffb454>s");
		equal(styles.statusStyle("blocked").render("s"), "<#f26d78>s");
		equal(styles.statusStyle("closed").render("s"), "<#8090a0>s");
		equal(styles.statusStyle("deferred").render("s"), "<#6c7680>s");
		equal(styles.statusStyle("pinned").render("s"), "<#d2a6ff>s");
		equal(styles.statusStyle("hooked").render("s"), "<#59c2ff>s");
		equal(styles.statusStyle("open").render("s"), "<->s");
		equal(styles.statusStyle("review").render("s"), "<->s");
		equal(styles.passBold.render("r"), "<#c2d94c+bold>r");
		equal(styles.failBold.render("b"), "<#f07178+bold>b");
		equal(styles.renderStatusId("open", "x"), "<default>x");
		equal(styles.renderStatusId("in_progress", "x"), "<#ffb454>x");
		equal(styles.renderStatusId("blocked", "x"), "<#f26d78>x");
		equal(styles.renderStatusId("closed", "x"), "<#8090a0>x");
		equal(styles.renderStatusId("deferred", "x"), "x");
		equal(styles.renderStatusId("pinned", "x"), "x");
		// A custom status takes its category's icon; a built-in name keeps its own.
		equal(styles.renderStatusIconWithCategory("review", "active"), "○");
		equal(styles.renderStatusIconWithCategory("review", "wip"), "<#ffb454>◐");
		equal(styles.renderStatusIconWithCategory("review", "done"), "<#8090a0>✓");
		equal(styles.renderStatusIconWithCategory("review", "frozen"), "<#6c7680>❄");
		equal(styles.renderStatusIconWithCategory("review", "unspecified"), "◇");
		equal(styles.renderStatusIconWithCategory("blocked", "done"), "<#f26d78>●");
	}

	static function lightContracts():Void {
		final styles = TerminalStyles.colored(false, marker);
		equal(styles.renderStatusIcon("in_progress"), "<#f2ae49>◐");
		equal(styles.renderStatusIcon("blocked"), "<#f07171>●");
		equal(styles.renderStatusIcon("closed"), "<#9099a1>✓");
		equal(styles.renderStatusIcon("deferred"), "<#828c99>❄");
		equal(styles.renderPriority(0), "<#f07171+bold>P0");
		equal(styles.renderPriority(1), "<#ff8f40>P1");
		equal(styles.renderType("bug"), "<#f07171>bug");
		equal(styles.renderStatus("hooked"), "<#59c2ff>hooked");
		equal(styles.renderPass("p"), "<#86b300>p");
		equal(styles.renderWarn("w"), "<#f2ae49>w");
		equal(styles.fail.render("f"), "<#f07171>f");
		equal(styles.renderAccent("a"), "<#399ee6>a");
		equal(styles.category.render("c"), "<#399ee6+bold>c");
		equal(styles.command.render("c"), "<#5c6166>c");
	}

	/** Builds a style that prints its spec before the text: `-` for no foreground, `default` for NoColor{}. */
	static function marker(spec:StyleSpec):TextStyle {
		final foreground = switch spec.foreground {
			case NoForeground: "-";
			case DefaultForeground: "default";
			case HexForeground(hex): hex;
		};
		return new MarkerStyle('<${foreground}${spec.bold ? "+bold" : ""}>');
	}

	static function environment(values:Map<String, String>):String->String {
		return name -> {
			final value = values.get(name);
			return value == null ? "" : value;
		};
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected) {
			failures++;
			Sys.println('expected ${expected}, got ${actual}');
		}
	}
}

private final class MarkerStyle implements TextStyle {
	final prefix:String;

	public function new(prefix:String) {
		this.prefix = prefix;
	}

	public function render(text:String):String {
		return prefix + text;
	}
}
