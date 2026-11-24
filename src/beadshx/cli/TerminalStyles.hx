package beadshx.cli;

import beadshx.store.JsonInteger;

/**
	Upstream ui.ShouldUseColor (internal/ui/terminal.go:32-64): whether
	upstream's internal/ui styles print colors.

	Why: upstream decides once, in the package init of internal/ui, before its
	pre-run loads `.beads/.env` or reads --no-color, so a caller passes the
	process environment as it was when the process started. What: false when
	BD_GIT_HOOK is exactly `1`, NO_COLOR is not empty or CLICOLOR is exactly
	`0`; then true when CLICOLOR_FORCE is not empty, also `0`; then false when
	TERM is `dumb` in any letter case; otherwise whether stdout is a terminal.
	How: `value` returns a variable's value, or "" when it is unset; upstream's
	os.Getenv does not tell those apart either. Upstream compares TERM with
	strings.EqualFold, and no other rune folds to a letter of `dumb`, so a
	lower-case comparison is exact.
**/
function shouldUseColor(value:String->String, stdoutIsTerminal:Bool):Bool {
	if (value("BD_GIT_HOOK") == "1")
		return false;
	if (value("NO_COLOR") != "")
		return false;
	if (value("CLICOLOR") == "0")
		return false;
	if (value("CLICOLOR_FORCE") != "")
		return true;
	if (value("TERM").toLowerCase() == "dumb")
		return false;
	return stdoutIsTerminal;
}

/** The foreground that one upstream ui style sets. */
enum StyleForeground {
	/** No Foreground call: `lipgloss.NewStyle()` alone, an empty style. */
	NoForeground;

	/**
		`Foreground(lipgloss.NoColor{})`: a set property that prints no color.
		lipgloss still treats the style as set, so it pads the shorter lines of
		a multi-line text to the widest one.
	**/
	DefaultForeground;

	/** `Foreground(lipgloss.Color(hex))` for a `#rrggbb` value: a 24-bit color. */
	HexForeground(hex:String);
}

/** One upstream ui style: `lipgloss.NewStyle()` with an optional foreground and bold. */
typedef StyleSpec = {
	final foreground:StyleForeground;
	final bold:Bool;
}

/** One built style. `render` is lipgloss `Style.Render` of one text. */
interface TextStyle {
	function render(text:String):String;
}

/**
	Upstream internal/ui's styles (internal/ui/styles.go:98-261) and the render
	helpers that the ported views use (styles.go:286-599).

	Why: upstream builds every style once when the process starts: from the
	Ayu palette for a dark or light terminal background when colors are on,
	and as empty styles otherwise; --no-color empties them again
	(DisableColors). Upstream prints the rendered text with fmt, never through
	a lipgloss writer, so a color is always 24-bit, whatever the terminal
	supports. What: one built style for each upstream style, and the helpers.
	How: `style` builds the native lipgloss style for a `StyleSpec`. An empty
	style still turns each tab into four spaces, as lipgloss does.
**/
final class TerminalStyles {
	public final pass:TextStyle;
	public final warn:TextStyle;
	public final fail:TextStyle;
	public final muted:TextStyle;
	public final accent:TextStyle;
	public final id:TextStyle;
	public final statusOpen:TextStyle;
	public final statusInProgress:TextStyle;
	public final statusClosed:TextStyle;
	public final statusBlocked:TextStyle;
	public final statusPinned:TextStyle;
	public final statusHooked:TextStyle;

	/** PriorityP0Style to PriorityP4Style. */
	public final priorities:Array<TextStyle>;

	public final typeBug:TextStyle;
	public final typeFeature:TextStyle;
	public final typeTask:TextStyle;
	public final typeEpic:TextStyle;
	public final typeChore:TextStyle;
	public final category:TextStyle;
	public final bold:TextStyle;
	public final command:TextStyle;

	/** `PassStyle.Bold(true)`: bold also with colors off, where PassStyle is the empty style. */
	public final passBold:TextStyle;

	/** `FailStyle.Bold(true)`: bold also with colors off, where FailStyle is the empty style. */
	public final failBold:TextStyle;

	/** `lipgloss.NewStyle()`: the style that ui.GetStatusStyle returns for open and custom statuses, colors on or off. */
	public final unstyled:TextStyle;

	/** Colors off: every style is `lipgloss.NewStyle()` (styles.go:180-227, and DisableColors at 28-79). */
	public static function plain(style:StyleSpec->TextStyle):TerminalStyles {
		return new TerminalStyles(false, true, style);
	}

	/** Colors on: upstream's initColors(isDark) and initStyles (styles.go:139-177 and 230-261). */
	public static function colored(isDark:Bool, style:StyleSpec->TextStyle):TerminalStyles {
		return new TerminalStyles(true, isDark, style);
	}

	function new(colors:Bool, isDark:Bool, style:StyleSpec->TextStyle) {
		final empty = style({foreground: NoForeground, bold: false});
		unstyled = empty;
		// lipgloss.LightDark(isDark)(light, dark), as a set foreground.
		function hex(light:String, dark:String, bold:Bool = false):TextStyle {
			return colors ? style({foreground: HexForeground(isDark ? dark : light), bold: bold}) : empty;
		}
		final noColor = colors ? style({foreground: DefaultForeground, bold: false}) : empty;
		pass = hex("#86b300", "#c2d94c");
		warn = hex("#f2ae49", "#ffb454");
		fail = hex("#f07171", "#f07178");
		muted = hex("#828c99", "#6c7680");
		accent = hex("#399ee6", "#59c2ff");
		id = noColor;
		statusOpen = noColor;
		statusInProgress = hex("#f2ae49", "#ffb454");
		statusClosed = hex("#9099a1", "#8090a0");
		statusBlocked = hex("#f07171", "#f26d78");
		statusPinned = hex("#d2a6ff", "#d2a6ff");
		statusHooked = hex("#59c2ff", "#59c2ff");
		priorities = [
			hex("#f07171", "#f07178", true),
			hex("#ff8f40", "#ff8f40"),
			hex("#e6b450", "#e6b450"),
			noColor,
			noColor
		];
		typeBug = hex("#f07171", "#f26d78");
		typeFeature = noColor;
		typeTask = noColor;
		typeEpic = hex("#d2a6ff", "#d2a6ff");
		typeChore = noColor;
		category = hex("#399ee6", "#59c2ff", true);
		bold = colors ? style({foreground: NoForeground, bold: true}) : empty;
		command = hex("#5c6166", "#bfbdb6");
		final boldOnly = style({foreground: NoForeground, bold: true});
		passBold = colors ? hex("#86b300", "#c2d94c", true) : boldOnly;
		failBold = colors ? hex("#f07171", "#f07178", true) : boldOnly;
	}

	/**
		ui.RenderStatusIcon (styles.go:289-306): the status icon of `status`,
		colored for in_progress, blocked, closed, deferred and pinned. An open
		or custom status's icon is never styled.
	**/
	public function renderStatusIcon(status:String):String {
		return switch status {
			case "open": "○";
			case "in_progress": statusInProgress.render("◐");
			case "blocked": statusBlocked.render("●");
			case "closed": statusClosed.render("✓");
			case "deferred": muted.render("❄");
			case "pinned": statusPinned.render("📌");
			case _: "◇";
		};
	}

	/**
		ui.RenderStatusIconWithCategory (styles.go:309-338): a built-in status
		keeps its own icon; any other status takes the icon of its category, and
		an unknown category the custom diamond.
	**/
	public function renderStatusIconWithCategory(status:String, category:String):String {
		return switch status {
			case "open" | "in_progress" | "blocked" | "closed" | "deferred" | "pinned": renderStatusIcon(status);
			case _:
				switch category {
					case "active": "○";
					case "wip": statusInProgress.render("◐");
					case "done": statusClosed.render("✓");
					case "frozen": muted.render("❄");
					case _: "◇";
				}
		};
	}

	/** ui.RenderPass (styles.go:428-430). */
	public function renderPass(text:String):String {
		return pass.render(text);
	}

	/** ui.RenderWarn (styles.go:433-435). */
	public function renderWarn(text:String):String {
		return warn.render(text);
	}

	/** ui.RenderFail (styles.go:438-440). */
	public function renderFail(text:String):String {
		return fail.render(text);
	}

	/** ui.RenderMuted (styles.go:443-445). */
	public function renderMuted(text:String):String {
		return muted.render(text);
	}

	/** ui.RenderAccent (styles.go:448-450). */
	public function renderAccent(text:String):String {
		return accent.render(text);
	}

	/** ui.RenderID (styles.go:490-492). */
	public function renderId(issueId:String):String {
		return id.render(issueId);
	}

	/** ui.RenderStatus (styles.go:496-511): any status but the five named ones takes the open style. */
	public function renderStatus(status:String):String {
		return switch status {
			case "in_progress": statusInProgress.render(status);
			case "blocked": statusBlocked.render(status);
			case "pinned": statusPinned.render(status);
			case "hooked": statusHooked.render(status);
			case "closed": statusClosed.render(status);
			case _: statusOpen.render(status);
		};
	}

	/** ui.RenderPriority (styles.go:517-533): `P<n>`, styled for 0 to 4 and printed as it is otherwise. */
	public function renderPriority(priority:JsonInteger):String {
		final label = 'P${priority.wireValue()}';
		return switch priority.wireValue() {
			case "0": priorities[0].render(label);
			case "1": priorities[1].render(label);
			case "2": priorities[2].render(label);
			case "3": priorities[3].render(label);
			case "4": priorities[4].render(label);
			case _: label;
		};
	}

	/** ui.RenderType (styles.go:544-559): a type without its own style is printed as it is. */
	public function renderType(issueType:String):String {
		return switch issueType {
			case "bug": typeBug.render(issueType);
			case "feature": typeFeature.render(issueType);
			case "task": typeTask.render(issueType);
			case "epic": typeEpic.render(issueType);
			case "chore": typeChore.render(issueType);
			case _: issueType;
		};
	}

	/**
		ui.GetStatusStyle (styles.go:395-412): the style of `status`. Unlike
		`renderStatus`, deferred takes the muted style, and open and every
		other status take the empty `unstyled` style, which pads no lines.
	**/
	public function statusStyle(status:String):TextStyle {
		return switch status {
			case "in_progress": statusInProgress;
			case "blocked": statusBlocked;
			case "closed": statusClosed;
			case "deferred": muted;
			case "pinned": statusPinned;
			case "hooked": statusHooked;
			case _: unstyled;
		};
	}

	/**
		The ID of an issue in its status style, as upstream's dep list, dep tree
		and refs views pick it: open, in_progress, blocked and closed take
		their status style, and any other status prints `text` as it is.
	**/
	public function renderStatusId(status:String, text:String):String {
		return switch status {
			case "open": statusOpen.render(text);
			case "in_progress": statusInProgress.render(text);
			case "blocked": statusBlocked.render(text);
			case "closed": statusClosed.render(text);
			case _: text;
		};
	}

	/** ui.RenderBold (styles.go:602-604). */
	public function renderBold(text:String):String {
		return bold.render(text);
	}

	/** ui.RenderClosedLine (styles.go:597-599): the whole line in the closed style. */
	public function renderClosedLine(line:String):String {
		return statusClosed.render(line);
	}
}
