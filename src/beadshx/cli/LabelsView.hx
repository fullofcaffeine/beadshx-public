package beadshx.cli;

import haxe.Json;
import haxe.io.Bytes;
import beadshx.store.IssueListItem;

/**
	Upstream `bd label list-all` on a proxied server counts the labels of a bead that
	sits in the wisps table without being ephemeral (`--no-history`) from the durable
	`labels` table. The shared search read reports that bead's `wisp_labels` rows, so
	this route waits for its own reader.
**/
final LABEL_LIST_ALL_ROUTE_UNAVAILABLE = "label list-all is not available yet for proxied workspaces in this build";

/** One label and the number of issues that carry it. */
typedef LabelCount = {
	final label:String;
	final count:Int;
}

/** Upstream countLabelsAcrossIssues, then `sort.Strings`: every label once, in byte order, with its issue count. */
function countLabels(issues:Array<IssueListItem>):Array<LabelCount> {
	final counts = new Map<String, Int>();
	final labels = new Array<String>();
	for (issue in issues)
		for (label in issue.labels) {
			final seen = counts.get(label);
			if (seen == null)
				labels.push(label);
			counts.set(label, seen == null ? 1 : seen + 1);
		}
	// haxe.go compares strings as Go does, byte by byte.
	labels.sort((left, right) -> left < right ? -1 : left == right ? 0 : 1);
	final result = new Array<LabelCount>();
	for (label in labels) {
		final count = counts.get(label);
		result.push({label: label, count: count == null ? 0 : count});
	}
	return result;
}

/** Upstream `bd label list`: the issue's labels, in the detail read's order. */
function renderIssueLabelsHuman(issueId:String, labels:Array<String>):String {
	if (labels.length == 0)
		return '\n${issueId} has no labels\n';
	final rendered = new StringBuf();
	rendered.add('\n🏷 Labels for ${issueId}:\n');
	for (label in labels)
		rendered.add('  - ${label}\n');
	rendered.add("\n");
	return rendered.toString();
}

/** Upstream `outputJSON(labels)`: a string array, or `[]` for none. */
function renderIssueLabelsJson(labels:Array<String>):String {
	if (labels.length == 0)
		return "[]\n";
	final lines = new Array<String>();
	for (label in labels)
		lines.push('  ${Json.stringify(label)}');
	return "[\n" + lines.join(",\n") + "\n]\n";
}

/** Upstream `bd label list-all`: each name padded to the longest name, measured in bytes like Go's `len`. */
function renderLabelCountsHuman(counts:Array<LabelCount>):String {
	if (counts.length == 0)
		return "\nNo labels found in database\n";
	var width = 0;
	for (entry in counts) {
		final length = Bytes.ofString(entry.label).length;
		if (length > width)
			width = length;
	}
	final rendered = new StringBuf();
	rendered.add('\n🏷 All labels (${counts.length} unique):\n');
	for (entry in counts) {
		rendered.add('  ${entry.label}');
		for (_ in Bytes.ofString(entry.label).length...width)
			rendered.add(" ");
		rendered.add('  (${entry.count} issues)\n');
	}
	rendered.add("\n");
	return rendered.toString();
}

/** Upstream `outputJSON([]labelInfo)`: `{"label", "count"}` objects, or `[]` for none. */
function renderLabelCountsJson(counts:Array<LabelCount>):String {
	if (counts.length == 0)
		return "[]\n";
	final lines = ["["];
	for (index in 0...counts.length) {
		final entry = counts[index];
		lines.push("  {");
		lines.push('    "label": ${Json.stringify(entry.label)},');
		lines.push('    "count": ${entry.count}');
		lines.push(index == counts.length - 1 ? "  }" : "  },");
	}
	lines.push("]");
	return lines.join("\n") + "\n";
}
