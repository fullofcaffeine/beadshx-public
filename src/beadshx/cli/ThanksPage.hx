package beadshx.cli;

import beadshx.cli.TerminalStyles.CoreColor;
import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.cli.TerminalStyles.coreForeground;
import haxe.io.Bytes;

/** One human contributor to beads and their commit count. */
typedef ThanksContributor = {
	final name:String;
	final commits:Int;
}

/**
	Upstream's thank-you page, which `bd info --thanks` prints
	(cmd/bd/thanks.go).

	Why: upstream prints a fixed page of the human contributors to beads, in
	a double-line box, featured names in columns and the rest wrapped.
	What: the page as upstream prints it with `fmt`. Upstream sorts its
	contributor map by commit count with an unstable sort, so contributors
	with the same count come out in a random order in each run; this page
	keeps the order of upstream's source for them.
	How: upstream builds its text styles from internal/ui's core colors once,
	when the process starts, so `--no-color` does not change them; it builds
	the box style when it renders, after `--no-color`. So the caller passes
	both color choices. Widths count bytes where upstream uses `len`, and
	runes where it pads with `%-*s`.
**/
final class ThanksPage {
	/** Upstream `topN`: the contributors that the page features in columns. */
	static inline final FEATURED = 20;

	/** The columns of the featured contributors. */
	static inline final COLUMNS = 4;

	/** Upstream's widest column name, in bytes; a longer name is cut to 17 bytes and `...`. */
	static inline final MAX_NAME_WIDTH = 20;

	/** The two spaces before each featured row and each wrapped line. */
	static inline final INDENT = "  ";

	/** Upstream `beadsContributors`, in the order of its source. */
	static final contributors:Array<ThanksContributor> = [
		{name: "Steve Yegge", commits: 2959},
		{name: "matt wilkie", commits: 64},
		{name: "Ryan Snodgrass", commits: 43},
		{name: "Travis Cline", commits: 9},
		{name: "David Laing", commits: 7},
		{name: "Ryan Newton", commits: 6},
		{name: "Joshua Shanks", commits: 6},
		{name: "Daan van Etten", commits: 5},
		{name: "Augustinas Malinauskas", commits: 4},
		{name: "Matteo Landi", commits: 4},
		{name: "Baishampayan Ghose", commits: 4},
		{name: "Charles P. Cross", commits: 4},
		{name: "Abhinav Gupta", commits: 3},
		{name: "Brian Williams", commits: 3},
		{name: "Marco Del Pin", commits: 3},
		{name: "Willi Ballenthin", commits: 3},
		{name: "Ben Lovell", commits: 2},
		{name: "Ben Madore", commits: 2},
		{name: "Dane Bertram", commits: 2},
		{name: "Dennis Schön", commits: 2},
		{name: "Troy Gaines", commits: 2},
		{name: "Zoe Gagnon", commits: 2},
		{name: "Peter Schilling", commits: 2},
		{name: "Adam Spiers", commits: 1},
		{name: "Aodhan Hayter", commits: 1},
		{name: "Assim Elhammouti", commits: 1},
		{name: "Bryce Roche", commits: 1},
		{name: "Caleb Leak", commits: 1},
		{name: "David Birks", commits: 1},
		{name: "Dean Giberson", commits: 1},
		{name: "Eli", commits: 1},
		{name: "Graeme Foster", commits: 1},
		{name: "Gurdas Nijor", commits: 1},
		{name: "Jimmy Stridh", commits: 1},
		{name: "Joel Klabo", commits: 1},
		{name: "Johannes Zillmann", commits: 1},
		{name: "John Lam", commits: 1},
		{name: "Jonathan Berger", commits: 1},
		{name: "Joshua Park", commits: 1},
		{name: "Juan Vargas", commits: 1},
		{name: "Kasper Zutterman", commits: 1},
		{name: "Kris Hansen", commits: 1},
		{name: "Logan Thomas", commits: 1},
		{name: "Lon Lundgren", commits: 1},
		{name: "Mark Wotton", commits: 1},
		{name: "Markus Flür", commits: 1},
		{name: "Michael Shuffett", commits: 1},
		{name: "Midworld Kim", commits: 1},
		{name: "Nikolai Prokoschenko", commits: 1},
		{name: "Peter Loron", commits: 1},
		{name: "Rod Davenport", commits: 1},
		{name: "Serhii", commits: 1},
		{name: "Shaun Cutts", commits: 1},
		{name: "Sophie Smithburg", commits: 1},
		{name: "Tim Haasdyk", commits: 1},
		{name: "Travis Lyons", commits: 1},
		{name: "Yaakov Nemoy", commits: 1},
		{name: "Yunsik Kim", commits: 1},
		{name: "Zachary Rosen", commits: 1},
	];

	/**
		The page, from upstream `printThanksPage`. `style` builds a native
		style. `startColors` is internal/ui's color choice when the process
		started, `colors` the choice after `--no-color`, and `isDark` the
		terminal background.
	**/
	public static function render(style:StyleSpec->TextStyle, startColors:Bool, colors:Bool, isDark:Bool):String {
		function styled(color:CoreColor, bold:Bool):TextStyle {
			return style({foreground: coreForeground(color, startColors, isDark), bold: bold});
		}
		final title = styled(WarnColor, true);
		final subtitle = styled(MutedColor, false);
		final section = styled(AccentColor, true);
		final name = styled(PassColor, false);
		final dim = styled(MutedColor, false);
		final border = style({foreground: coreForeground(MutedColor, colors, isDark), bold: false});
		final names = sortedNames();
		final featuredCount = names.length < FEATURED ? names.length : FEATURED;
		final featured = names.slice(0, featuredCount);
		final additional = names.slice(featuredCount);
		// Upstream adds 4 for the indent.
		final contentWidth = columnsWidth(featured) + 4;
		final page = new StringBuf();
		page.add("\n");
		page.add(box(contentWidth - 4, border, [
			{text: "THANK YOU!", style: title},
			{text: "", style: null},
			{text: "To all the humans who contributed to beads", style: subtitle}
		]));
		page.add("\n");
		page.add(section.render(INDENT + "Featured Contributors") + "\n\n");
		page.add(columns(featured, name));
		if (additional.length > 0) {
			page.add("\n");
			page.add(section.render(INDENT + "Additional Contributors") + "\n\n");
			page.add(wrappedList(additional, contentWidth, dim));
		}
		page.add("\n");
		return page.toString();
	}

	/** Upstream `getContributorsSorted`: the names by commit count, highest first; a stable sort keeps the source order of ties. */
	static function sortedNames():Array<String> {
		final sorted = contributors.copy();
		for (index in 1...sorted.length) {
			final current = sorted[index];
			var at = index;
			while (at > 0 && sorted[at - 1].commits < current.commits) {
				sorted[at] = sorted[at - 1];
				at--;
			}
			sorted[at] = current;
		}
		return [for (contributor in sorted) contributor.name];
	}

	/**
		Upstream `thanksBoxStyle(width).Render(header)`: a double border,
		padding of one line and four columns, the lines centered, `width`
		columns wide with the border. Lipgloss puts the odd column of a gap
		on the right.
	**/
	static function box(width:Int, border:TextStyle, lines:Array<{text:String, style:Null<TextStyle>}>):String {
		final inner = width - 2;
		final textWidth = inner - 8;
		final edge = border.render("║");
		final blank = edge + spaces(inner) + edge + "\n";
		final rendered = new StringBuf();
		rendered.add(border.render("╔" + repeat("═", inner) + "╗") + "\n");
		rendered.add(blank);
		for (line in lines) {
			final gap = textWidth - runeCount(line.text);
			final left = gap >> 1;
			final text = line.style == null ? line.text : line.style.render(line.text);
			rendered.add(edge + spaces(4 + left) + text + spaces(gap - left + 4) + edge + "\n");
		}
		rendered.add(blank);
		rendered.add(border.render("╚" + repeat("═", inner) + "╝") + "\n");
		return rendered.toString();
	}

	/** Upstream `calculateColumnsWidth`. */
	static function columnsWidth(names:Array<String>):Int {
		return names.length == 0 ? 0 : (widestName(names) + 2) * COLUMNS;
	}

	/** Upstream `printThanksColumns`: the names in rows, left to right, each padded to the column width. */
	static function columns(names:Array<String>, style:TextStyle):String {
		if (names.length == 0)
			return "";
		final columnWidth = widestName(names) + 2;
		final rendered = new StringBuf();
		var index = 0;
		while (index < names.length) {
			rendered.add(INDENT);
			var column = 0;
			while (column < COLUMNS && index + column < names.length) {
				var cell = names[index + column];
				if (byteLength(cell) > MAX_NAME_WIDTH)
					cell = Bytes.ofString(cell).sub(0, MAX_NAME_WIDTH - 3).toString() + "...";
				rendered.add(style.render(cell + spaces(columnWidth - runeCount(cell))));
				column++;
			}
			rendered.add("\n");
			index += COLUMNS;
		}
		return rendered.toString();
	}

	/** Upstream `printThanksWrappedList` without a label: the names joined by `, `, wrapped before a name that would pass `maxWidth` bytes. */
	static function wrappedList(names:Array<String>, maxWidth:Int, style:TextStyle):String {
		final rendered = new StringBuf();
		rendered.add(INDENT);
		var lineLength = INDENT.length;
		for (index in 0...names.length) {
			final entry = names[index] + (index == names.length - 1 ? "" : ", ");
			final entryLength = byteLength(entry);
			if (lineLength + entryLength > maxWidth && lineLength > INDENT.length) {
				rendered.add("\n" + INDENT);
				lineLength = INDENT.length;
			}
			rendered.add(style.render(entry));
			lineLength += entryLength;
		}
		rendered.add("\n");
		return rendered.toString();
	}

	/** The widest name in bytes, at most `MAX_NAME_WIDTH`. */
	static function widestName(names:Array<String>):Int {
		var widest = 0;
		for (name in names) {
			final length = byteLength(name);
			if (length > widest)
				widest = length;
		}
		return widest > MAX_NAME_WIDTH ? MAX_NAME_WIDTH : widest;
	}

	/** Go's `len` of a string: its UTF-8 bytes. */
	static function byteLength(text:String):Int {
		return Bytes.ofString(text).length;
	}

	/** The runes of `text`, which Go's `%-*s` pads by: its UTF-8 bytes that start a character. */
	static function runeCount(text:String):Int {
		final bytes = Bytes.ofString(text);
		var count = 0;
		for (index in 0...bytes.length)
			if (bytes.get(index) & 0xC0 != 0x80)
				count++;
		return count;
	}

	static function spaces(count:Int):String {
		return repeat(" ", count);
	}

	static function repeat(text:String, count:Int):String {
		final repeated = new StringBuf();
		for (_ in 0...count)
			repeated.add(text);
		return repeated.toString();
	}
}
