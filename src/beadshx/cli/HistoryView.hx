package beadshx.cli;

import haxe.Json;
import beadshx.cli.StatusIcon.statusIcon;
import beadshx.store.IssueHistory.HistoryIssue;
import beadshx.store.IssueHistory.IssueEvent;
import beadshx.store.IssueHistory.IssueHistoryEntry;

/** Upstream runHistory's text layout, after `--limit` cut the entries; colors are off. */
function renderHistoryText(issueId:String, history:Array<IssueHistoryEntry>):String {
	if (history.length == 0)
		return 'No history found for issue ${issueId}\n';
	final lines = ["", '📜 History for ${issueId} (${history.length} entries)', ""];
	for (index in 0...history.length) {
		final entry:IssueHistoryEntry = history[index];
		final issue:HistoryIssue = entry.issue;
		lines.push('${entry.commitHash.substr(0, 8)} ${entry.commitDateText}');
		lines.push('  Author: ${entry.committer}');
		lines.push('  ${statusIcon(issue.status)} ${issue.id}: ${issue.title} [P${issue.priority} - ${issue.status}]');
		if (index < history.length - 1)
			lines.push("");
	}
	return lines.join("\n") + "\n\n";
}

/**
	Upstream `outputJSON(history)`: HistoryEntry has no JSON tags, so its fields print by Go name,
	and the Issue prints only the fields HistoryInTx fills. No entry prints `null`.
**/
function renderHistoryJson(history:Array<IssueHistoryEntry>):String {
	if (history.length == 0)
		return "null\n";
	final lines = ["["];
	for (index in 0...history.length) {
		final entry:IssueHistoryEntry = history[index];
		lines.push("  {");
		lines.push('    "CommitHash": ${Json.stringify(entry.commitHash)},');
		lines.push('    "Committer": ${Json.stringify(entry.committer)},');
		lines.push('    "CommitDate": ${Json.stringify(entry.commitDate)},');
		lines.push('    "Issue": {');
		final fields = historyIssueFields(entry.issue);
		for (fieldIndex in 0...fields.length)
			lines.push('      ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
		lines.push("    }");
		lines.push(index == history.length - 1 ? "  }" : "  },");
	}
	lines.push("]");
	return lines.join("\n") + "\n";
}

/** The Issue struct's field order and `omitempty` rules, over the fields HistoryInTx fills. */
private function historyIssueFields(issue:HistoryIssue):Array<String> {
	final fields = ['"id": ${Json.stringify(issue.id)}', '"title": ${Json.stringify(issue.title)}'];
	function text(name:String, value:String):Void {
		if (value != "")
			fields.push('"${name}": ${Json.stringify(value)}');
	}
	text("description", issue.description);
	text("design", issue.design);
	text("acceptance_criteria", issue.acceptanceCriteria);
	text("notes", issue.notes);
	text("status", issue.status);
	fields.push('"priority": ${issue.priority}');
	text("issue_type", issue.issueType);
	text("assignee", issue.assignee);
	text("owner", issue.owner);
	switch issue.estimatedMinutes {
		case IntegerAbsent:
		case IntegerPresent(value):
			fields.push('"estimated_minutes": ${value}');
	}
	fields.push('"created_at": ${Json.stringify(issue.createdAt)}');
	text("created_by", issue.createdBy);
	fields.push('"updated_at": ${Json.stringify(issue.updatedAt)}');
	text("closed_at", issue.closedAt);
	text("close_reason", issue.closeReason);
	if (issue.pinned)
		fields.push('"pinned": true');
	text("mol_type", issue.moleculeType);
	return fields;
}

/** Upstream printHistoryEvents; an empty or NULL value leaves its line out. */
function renderHistoryEventsText(issueId:String, events:Array<IssueEvent>):String {
	if (events.length == 0)
		return 'No history events found for issue ${issueId}\n';
	final lines = ["", '📜 History events for ${issueId} (${events.length} entries)', ""];
	for (index in 0...events.length) {
		final event:IssueEvent = events[index];
		lines.push('${event.createdAtText} ${event.eventType} by ${event.actor}');
		if (event.oldValue != null && event.oldValue != "")
			lines.push('  Old: ${event.oldValue}');
		if (event.newValue != null && event.newValue != "")
			lines.push('  New: ${event.newValue}');
		if (event.comment != null && event.comment != "")
			lines.push('  Comment: ${event.comment}');
		if (index < events.length - 1)
			lines.push("");
	}
	return lines.join("\n") + "\n\n";
}

/** Upstream `outputJSON(events)`: a NULL value leaves its field out, and no event prints `null`. */
function renderHistoryEventsJson(events:Array<IssueEvent>):String {
	if (events.length == 0)
		return "null\n";
	final lines = ["["];
	for (index in 0...events.length) {
		final event:IssueEvent = events[index];
		final fields = [
			'"id": ${Json.stringify(event.id)}',
			'"issue_id": ${Json.stringify(event.issueId)}',
			'"event_type": ${Json.stringify(event.eventType)}',
			'"actor": ${Json.stringify(event.actor)}'
		];
		if (event.oldValue != null)
			fields.push('"old_value": ${Json.stringify(event.oldValue)}');
		if (event.newValue != null)
			fields.push('"new_value": ${Json.stringify(event.newValue)}');
		if (event.comment != null)
			fields.push('"comment": ${Json.stringify(event.comment)}');
		fields.push('"created_at": ${Json.stringify(event.createdAt)}');
		lines.push("  {");
		for (fieldIndex in 0...fields.length)
			lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
		lines.push(index == events.length - 1 ? "  }" : "  },");
	}
	lines.push("]");
	return lines.join("\n") + "\n";
}
