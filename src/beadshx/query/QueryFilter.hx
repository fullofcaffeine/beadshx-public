package beadshx.query;

import beadshx.store.IssueQueryRow;
import beadshx.store.OptionalInt;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.QueryInstant;
import beadshx.store.QueryOptionalBool;
import beadshx.store.QueryStorageRequest.QueryStorageFilter;

/** Applies one Haxe-planned storage filter to a copied native issue row. */
final class QueryFilter {
	public static function matches(filter:QueryStorageFilter, row:IssueQueryRow):Bool {
		final issue = row.item;
		if (filter.status != "" && issue.status != filter.status)
			return false;
		if (filter.excludeStatuses.indexOf(issue.status) >= 0)
			return false;
		if (!matchesInt(filter.priority, issue.priority, EqualInt)
			|| !matchesInt(filter.priorityMin, issue.priority, MinimumInt)
			|| !matchesInt(filter.priorityMax, issue.priority, MaximumInt))
			return false;
		if (filter.issueType != "" && issue.issueType != filter.issueType)
			return false;
		if (filter.excludeTypes.indexOf(issue.issueType) >= 0)
			return false;
		if (filter.assignee != "" && !equalFold(issue.assignee, filter.assignee))
			return false;
		if (filter.noAssignee && issue.assignee != "")
			return false;
		if (!containsAllFold(issue.labels, filter.labels))
			return false;
		if (filter.labelsAny.length > 0 && !containsAnyFold(issue.labels, filter.labelsAny))
			return false;
		if (filter.noLabels && issue.labels.length != 0)
			return false;
		if (!containsFold(issue.title, filter.titleContains)
			|| !containsFold(issue.description, filter.descriptionContains)
			|| !containsFold(issue.notes, filter.notesContains))
			return false;
		if (filter.emptyDescription && issue.description != "")
			return false;
		if (!after(row.created, filter.createdAfter)
			|| !before(row.created, filter.createdBefore)
			|| !after(row.updated, filter.updatedAfter)
			|| !before(row.updated, filter.updatedBefore)
			|| !optionalAfter(row.started, filter.startedAfter)
			|| !optionalBefore(row.started, filter.startedBefore)
			|| !optionalAfter(row.closed, filter.closedAfter)
			|| !optionalBefore(row.closed, filter.closedBefore))
			return false;
		if (filter.ids.length > 0 && filter.ids.indexOf(issue.id) < 0)
			return false;
		if (filter.idPrefix != "" && !StringTools.startsWith(issue.id, filter.idPrefix))
			return false;
		if (filter.specPrefix != "" && !StringTools.startsWith(issue.specId, filter.specPrefix))
			return false;
		if (filter.parentId != "" && issue.parent != filter.parentId)
			return false;
		if (!matchesBool(filter.pinned, row.pinned)
			|| !matchesBool(filter.ephemeral, row.ephemeral)
			|| !matchesBool(filter.template, row.template))
			return false;
		if (filter.moleculeType != "" && issue.moleculeType != filter.moleculeType)
			return false;
		for (entry in filter.metadataFields)
			if (!issue.metadata.topLevelQueryEquals(entry.key, entry.value))
				return false;
		return filter.hasMetadataKey == "" || issue.metadata.hasTopLevelKey(filter.hasMetadataKey);
	}

	static function matchesInt(expected:OptionalInt, actual:Int, comparison:IntFilterComparison):Bool {
		return switch expected {
			case IntAbsent: true;
			case IntPresent(value): switch comparison {
					case EqualInt: actual == value;
					case MinimumInt: actual >= value;
					case MaximumInt: actual <= value;
				};
		};
	}

	static function matchesBool(expected:QueryOptionalBool, actual:Bool):Bool {
		return switch expected {
			case BoolAbsent: true;
			case BoolPresent(value): actual == value;
		};
	}

	static function containsAllFold(actual:Array<String>, expected:Array<String>):Bool {
		for (value in expected)
			if (!arrayContainsFold(actual, value))
				return false;
		return true;
	}

	static function containsAnyFold(actual:Array<String>, expected:Array<String>):Bool {
		for (value in expected)
			if (arrayContainsFold(actual, value))
				return true;
		return false;
	}

	static function arrayContainsFold(actual:Array<String>, expected:String):Bool {
		for (value in actual)
			if (equalFold(value, expected))
				return true;
		return false;
	}

	static inline function containsFold(actual:String, expected:String):Bool {
		return expected == "" || actual.toLowerCase().indexOf(expected.toLowerCase()) >= 0;
	}

	static inline function equalFold(left:String, right:String):Bool {
		return left.toLowerCase() == right.toLowerCase();
	}

	static function after(actual:QueryInstant, boundary:OptionalQueryInstant):Bool {
		return switch boundary {
			case InstantAbsent: true;
			case InstantPresent(value): compareTime(actual, value) > 0;
		};
	}

	static function before(actual:QueryInstant, boundary:OptionalQueryInstant):Bool {
		return switch boundary {
			case InstantAbsent: true;
			case InstantPresent(value): compareTime(actual, value) < 0;
		};
	}

	static function optionalAfter(actual:OptionalQueryInstant, boundary:OptionalQueryInstant):Bool {
		return switch boundary {
			case InstantAbsent: true;
			case InstantPresent(value): switch actual {
					case InstantAbsent: false;
					case InstantPresent(actualValue): compareTime(actualValue, value) > 0;
				};
		};
	}

	static function optionalBefore(actual:OptionalQueryInstant, boundary:OptionalQueryInstant):Bool {
		return switch boundary {
			case InstantAbsent: true;
			case InstantPresent(value): switch actual {
					case InstantAbsent: false;
					case InstantPresent(actualValue): compareTime(actualValue, value) < 0;
				};
		};
	}

	static function compareTime(left:QueryInstant, right:QueryInstant):Int {
		final seconds = compareDecimalIntegers(left.epochSeconds, right.epochSeconds);
		return seconds != 0 ? seconds : left.nanosecond < right.nanosecond ? -1 : left.nanosecond > right.nanosecond ? 1 : 0;
	}

	/** Compare signed decimal seconds without narrowing them to a target Int. */
	static function compareDecimalIntegers(left:String, right:String):Int {
		final leftNegative = StringTools.startsWith(left, "-");
		final rightNegative = StringTools.startsWith(right, "-");
		if (leftNegative != rightNegative)
			return leftNegative ? -1 : 1;
		final leftDigits = normalizedDigits(left, leftNegative);
		final rightDigits = normalizedDigits(right, rightNegative);
		var order = leftDigits.length < rightDigits.length ? -1 : leftDigits.length > rightDigits.length ? 1 : leftDigits < rightDigits ? -1 : leftDigits > rightDigits ? 1 : 0;
		return leftNegative ? -order : order;
	}

	static function normalizedDigits(value:String, negative:Bool):String {
		var index = negative || StringTools.startsWith(value, "+") ? 1 : 0;
		while (index < value.length - 1 && value.charAt(index) == "0")
			index++;
		return value.substr(index);
	}
}

private enum IntFilterComparison {
	EqualInt;
	MinimumInt;
	MaximumInt;
}
