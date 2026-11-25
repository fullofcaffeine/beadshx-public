package beadshx.cli;

import haxe.Json;
import beadshx.store.IssueComment;

/** Upstream commentsMisplacedListCmd, which runs only after the store opens. */
final MISPLACED_COMMENTS_LIST = '"bd comments list" is not valid.\n\nTo list comments on an issue, run:\n  bd comments <issue-id>\n\n'
	+ 'Example:\n  bd comments bd-123\n\nSee: bd comments --help';

/** Upstream `outputJSON(comments)`: an array of Comment structs in field order, or `[]`. */
function renderCommentsJson(comments:Array<IssueComment>):String {
	if (comments.length == 0)
		return "[]\n";
	final lines = ["["];
	for (index in 0...comments.length) {
		final comment = comments[index];
		lines.push("  {");
		lines.push('    "id": ${Json.stringify(comment.id)},');
		lines.push('    "issue_id": ${Json.stringify(comment.issueId)},');
		lines.push('    "author": ${Json.stringify(comment.author)},');
		lines.push('    "text": ${Json.stringify(comment.text)},');
		lines.push('    "created_at": ${Json.stringify(comment.createdAt)}');
		lines.push(index == comments.length - 1 ? "  }" : "  },");
	}
	lines.push("]");
	return lines.join("\n") + "\n";
}

/**
	Upstream formats `CreatedAt` as `2006-01-02 15:04` in the zone the driver scanned it in,
	which is UTC, or in the process's local zone (TZ) for `--local-time`.
**/
function commentTimestamp(createdAt:String, localTime:Bool):String {
	final stored = createdAt.length < 16 ? createdAt : createdAt.substr(0, 10) + " " + createdAt.substr(11, 5);
	if (!localTime)
		return stored;
	final millis = rfc3339Millis(createdAt);
	return millis == null ? stored : Date.fromTime(millis).toString().substr(0, 16);
}

/**
	The instant of a `2006-01-02T15:04:05[.fraction](Z|±07:00)` time in milliseconds,
	the fraction cut to whole milliseconds as Go's `UnixMilli` does, or null.
**/
function rfc3339Millis(value:String):Null<Float> {
	if (value.length < 20 || value.charAt(4) != "-" || value.charAt(7) != "-" || value.charAt(10) != "T" || value.charAt(13) != ":" || value.charAt(16) != ":")
		return null;
	final year = Std.parseInt(value.substr(0, 4));
	final month = Std.parseInt(value.substr(5, 2));
	final day = Std.parseInt(value.substr(8, 2));
	final hour = Std.parseInt(value.substr(11, 2));
	final minute = Std.parseInt(value.substr(14, 2));
	final second = Std.parseInt(value.substr(17, 2));
	if (year == null || month == null || day == null || hour == null || minute == null || second == null)
		return null;
	// A fraction never moves the minute: zone offsets are whole seconds.
	var zone = 19;
	var fractionMillis = 0;
	if (value.charAt(zone) == ".") {
		zone++;
		final start = zone;
		while (zone < value.length && value.charCodeAt(zone) >= "0".code && value.charCodeAt(zone) <= "9".code)
			zone++;
		final digits = zone - start < 3 ? zone - start : 3;
		final millis = Std.parseInt(StringTools.rpad(value.substr(start, digits), "0", 3));
		if (millis != null)
			fractionMillis = millis;
	}
	final designator = value.substr(zone);
	var offsetSeconds = 0;
	if (designator != "Z") {
		if (designator.length != 6 || designator.charAt(3) != ":" || (designator.charAt(0) != "+" && designator.charAt(0) != "-"))
			return null;
		final offsetHours = Std.parseInt(designator.substr(1, 2));
		final offsetMinutes = Std.parseInt(designator.substr(4, 2));
		if (offsetHours == null || offsetMinutes == null)
			return null;
		offsetSeconds = (designator.charAt(0) == "-" ? -1 : 1) * (offsetHours * 3600 + offsetMinutes * 60);
	}
	final seconds = daysFromCivil(year, month, day) * 86400.0 + hour * 3600 + minute * 60 + second - offsetSeconds;
	return seconds * 1000.0 + fractionMillis;
}

/** Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's days_from_civil). */
private function daysFromCivil(year:Int, month:Int, day:Int):Float {
	final shifted = month <= 2 ? year - 1 : year;
	final era = Math.floor(shifted / 400);
	final yearOfEra = shifted - era * 400;
	final dayOfYear = Std.int((153 * (month > 2 ? month - 3 : month + 9) + 2) / 5) + day - 1;
	final dayOfEra = yearOfEra * 365 + Std.int(yearOfEra / 4) - Std.int(yearOfEra / 100) + dayOfYear;
	return era * 146097.0 + dayOfEra - 719468;
}
