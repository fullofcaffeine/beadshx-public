package beadshx.query;

import beadshx.query.QueryPlan.QueryPagePolicy;
import beadshx.query.QueryPlan.QueryPredicateExpression;
import beadshx.store.IssueQueryRow;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.QueryInstant;

private typedef IndexedQueryRow = {
	final row:IssueQueryRow;
	final originalIndex:Int;
}

/** One Haxe-owned query page after predicate selection and display ordering. */
typedef QueryPageResult = {
	final rows:Array<IssueQueryRow>;
	final hasMore:Bool;
}

/** Applies the pinned stable display order, offset, and limit to candidates. */
final class QueryPage {
	public static function exactPage(rows:Array<IssueQueryRow>, sourceHasMore:Bool):QueryPageResult {
		return {rows: rows, hasMore: sourceHasMore};
	}

	public static function predicatePage(candidates:Array<IssueQueryRow>, predicate:QueryPredicateExpression, page:QueryPagePolicy):QueryPageResult {
		final matches = [
			for (candidate in candidates)
				if (QueryPredicate.matches(predicate, candidate)) candidate
		];
		return finish(matches, page, false);
	}

	public static function finish(rows:Array<IssueQueryRow>, page:QueryPagePolicy, sourceHasMore:Bool):QueryPageResult {
		final ordered = stableOrder(rows, page.sortBy, page.reverse);
		final start = page.offset >= ordered.length ? ordered.length : page.offset;
		var end = ordered.length;
		var hasMore = sourceHasMore;
		if (page.limit > 0 && end - start > page.limit) {
			end = start + page.limit;
			hasMore = true;
		}
		return {rows: ordered.slice(start, end), hasMore: hasMore};
	}

	static function stableOrder(rows:Array<IssueQueryRow>, sortBy:String, reverse:Bool):Array<IssueQueryRow> {
		if (sortBy == "")
			return rows.copy();
		final indexed = new Array<IndexedQueryRow>();
		for (index in 0...rows.length)
			indexed.push({row: rows[index], originalIndex: index});
		indexed.sort((left, right) -> compareIndexed(left, right, sortBy, reverse));
		return [for (entry in indexed) entry.row];
	}

	static function compareIndexed(left:IndexedQueryRow, right:IndexedQueryRow, sortBy:String, reverse:Bool):Int {
		final order = compareRows(left.row, right.row, sortBy);
		final directed = reverse ? -order : order;
		return directed == 0 ? compareInts(left.originalIndex, right.originalIndex) : directed;
	}

	static function compareRows(left:IssueQueryRow, right:IssueQueryRow, sortBy:String):Int {
		return switch sortBy {
			case "priority": compareInts(left.item.priority, right.item.priority);
			case "created": -compareInstants(left.created, right.created);
			case "updated": -compareInstants(left.updated, right.updated);
			case "closed": compareClosed(left.closed, right.closed);
			case "status": compareStrings(left.item.status, right.item.status);
			case "id": naturalCompareIds(left.item.id, right.item.id);
			case "title": compareStrings(left.item.title.toLowerCase(), right.item.title.toLowerCase());
			case "type": compareStrings(left.item.issueType, right.item.issueType);
			case "assignee": compareStrings(left.item.assignee, right.item.assignee);
			case _: 0;
		};
	}

	static function compareClosed(left:OptionalQueryInstant, right:OptionalQueryInstant):Int {
		return switch [left, right] {
			case [InstantAbsent, InstantAbsent]: 0;
			case [InstantAbsent, InstantPresent(_)]: 1;
			case [InstantPresent(_), InstantAbsent]: -1;
			case [InstantPresent(leftValue), InstantPresent(rightValue)]: -compareInstants(leftValue, rightValue);
		};
	}

	static function compareInstants(left:QueryInstant, right:QueryInstant):Int {
		final seconds = compareDecimalIntegers(left.epochSeconds, right.epochSeconds);
		return seconds == 0 ? compareInts(left.nanosecond, right.nanosecond) : seconds;
	}

	/** Numeric-aware comparison for dot- and dash-separated issue-ID segments. */
	static function naturalCompareIds(left:String, right:String):Int {
		final leftSegments = splitId(left);
		final rightSegments = splitId(right);
		final shared = leftSegments.length < rightSegments.length ? leftSegments.length : rightSegments.length;
		for (index in 0...shared) {
			final leftPart = leftSegments[index];
			final rightPart = rightSegments[index];
			if (leftPart == rightPart)
				continue;
			if (isDigits(leftPart) && isDigits(rightPart)) {
				final order = compareUnsignedDecimal(leftPart, rightPart);
				if (order != 0)
					return order;
				continue;
			}
			return compareStrings(leftPart, rightPart);
		}
		return compareInts(leftSegments.length, rightSegments.length);
	}

	static function splitId(value:String):Array<String> {
		final segments = new Array<String>();
		var start = 0;
		for (index in 0...value.length) {
			final character = value.charAt(index);
			if (character == "." || character == "-") {
				if (index > start)
					segments.push(value.substring(start, index));
				start = index + 1;
			}
		}
		if (start < value.length)
			segments.push(value.substr(start));
		return segments;
	}

	static function isDigits(value:String):Bool {
		if (value == "")
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			if (code < 48 || code > 57)
				return false;
		}
		return true;
	}

	static function compareUnsignedDecimal(left:String, right:String):Int {
		final leftDigits = trimLeadingZeros(left);
		final rightDigits = trimLeadingZeros(right);
		return leftDigits.length < rightDigits.length ? -1 : leftDigits.length > rightDigits.length ? 1 : compareStrings(leftDigits, rightDigits);
	}

	static function trimLeadingZeros(value:String):String {
		var index = 0;
		while (index < value.length - 1 && value.charAt(index) == "0")
			index++;
		return value.substr(index);
	}

	static function compareDecimalIntegers(left:String, right:String):Int {
		final leftNegative = StringTools.startsWith(left, "-");
		final rightNegative = StringTools.startsWith(right, "-");
		if (leftNegative != rightNegative)
			return leftNegative ? -1 : 1;
		final leftDigits = trimLeadingZeros(left.substr(leftNegative || StringTools.startsWith(left, "+") ? 1 : 0));
		final rightDigits = trimLeadingZeros(right.substr(rightNegative || StringTools.startsWith(right, "+") ? 1 : 0));
		final order = leftDigits.length < rightDigits.length ? -1 : leftDigits.length > rightDigits.length ? 1 : compareStrings(leftDigits, rightDigits);
		return leftNegative ? -order : order;
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}

	static inline function compareInts(left:Int, right:Int):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}
}
