package beadshx.query;

import beadshx.query.QueryPlan.QueryFlagField;
import beadshx.query.QueryPlan.QueryPredicateExpression;
import beadshx.query.QueryPlan.QueryPredicateTest;
import beadshx.query.QueryPlan.QueryTimeField;
import beadshx.query.QuerySyntax.QueryComparisonOperator;
import beadshx.store.IssueQueryRow;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.QueryInstant;

/** Evaluates a semantically validated query predicate against typed rows. */
final class QueryPredicate {
	public static function matches(expression:QueryPredicateExpression, row:IssueQueryRow):Bool {
		return switch expression {
			case PredicateComparison(test): matchesTest(test, row);
			case PredicateAnd(left, right): matches(left, row) && matches(right, row);
			case PredicateOr(left, right): matches(left, row) || matches(right, row);
			case PredicateNot(operand): !matches(operand, row);
		};
	}

	static function matchesTest(test:QueryPredicateTest, row:IssueQueryRow):Bool {
		final issue = row.item;
		return switch test {
			case StatusTest(comparison, value): compareEquality(issue.status == value, comparison);
			case PriorityTest(comparison, value): compareOrder(compareInts(issue.priority, value), comparison);
			case IssueTypeTest(comparison, value): compareEquality(issue.issueType == value, comparison);
			case AssigneeTest(comparison, value, none):
				compareEquality(none ? issue.assignee == "" : equalFold(issue.assignee, value), comparison);
			case OwnerTest(comparison, value): compareEquality(equalFold(issue.owner, value), comparison);
			case LabelTest(comparison, value, none):
				compareEquality(none ? issue.labels.length == 0 : containsFold(issue.labels, value), comparison);
			case TitleTest(comparison, value): compareEquality(issue.title.toLowerCase().indexOf(value) >= 0, comparison);
			case DescriptionTest(comparison, value, none):
				compareEquality(none ? issue.description == "" : issue.description.toLowerCase().indexOf(value.toLowerCase()) >= 0, comparison);
			case NotesTest(comparison, value): compareEquality(issue.notes.toLowerCase().indexOf(value) >= 0, comparison);
			case TimeTest(field, comparison, value): compareRowTime(row, field, comparison, value);
			case IdTest(comparison, value, wildcard): compareIdentity(issue.id, comparison, value, wildcard);
			case SpecTest(comparison, value, wildcard): compareIdentity(issue.specId, comparison, value, wildcard);
			case FlagTest(field, comparison, value): compareEquality(flagValue(row, field) == value, comparison);
			case MetadataTest(key, value): issue.metadata.topLevelQueryEquals(key, value);
			case HasMetadataKeyTest(key): issue.metadata.hasTopLevelKey(key);
		};
	}

	static function compareRowTime(row:IssueQueryRow, field:QueryTimeField, comparison:QueryComparisonOperator, target:QueryInstant):Bool {
		return switch field {
			case CreatedTime: compareTime(row.created, target, comparison);
			case UpdatedTime: compareTime(row.updated, target, comparison);
			case StartedTime: compareOptionalTime(row.started, target, comparison);
			case ClosedTime: compareOptionalTime(row.closed, target, comparison);
		};
	}

	static function compareOptionalTime(actual:OptionalQueryInstant, target:QueryInstant, comparison:QueryComparisonOperator):Bool {
		return switch actual {
			case InstantAbsent: false;
			case InstantPresent(value): compareTime(value, target, comparison);
		};
	}

	static function compareTime(actual:QueryInstant, target:QueryInstant, comparison:QueryComparisonOperator):Bool {
		if (comparison == Equal || comparison == NotEqual) {
			final sameDay = actual.year == target.year && actual.month == target.month && actual.day == target.day;
			return comparison == Equal ? sameDay : !sameDay;
		}
		final seconds = compareDecimalIntegers(actual.epochSeconds, target.epochSeconds);
		final order = seconds == 0 ? compareInts(actual.nanosecond, target.nanosecond) : seconds;
		return compareOrder(order, comparison);
	}

	static function compareIdentity(actual:String, comparison:QueryComparisonOperator, expected:String, wildcard:Bool):Bool {
		final matches = wildcard ? StringTools.startsWith(actual, expected.substr(0, expected.length - 1)) : actual == expected;
		return compareEquality(matches, comparison);
	}

	static function flagValue(row:IssueQueryRow, field:QueryFlagField):Bool {
		return switch field {
			case PinnedFlag: row.pinned;
			case EphemeralFlag: row.ephemeral;
			case TemplateFlag: row.template;
		};
	}

	static function containsFold(values:Array<String>, expected:String):Bool {
		for (value in values)
			if (equalFold(value, expected))
				return true;
		return false;
	}

	static inline function equalFold(left:String, right:String):Bool {
		return left.toLowerCase() == right.toLowerCase();
	}

	static function compareEquality(matches:Bool, comparison:QueryComparisonOperator):Bool {
		return comparison == Equal ? matches : comparison == NotEqual ? !matches : false;
	}

	static function compareOrder(order:Int, comparison:QueryComparisonOperator):Bool {
		return switch comparison {
			case Equal: order == 0;
			case NotEqual: order != 0;
			case LessThan: order < 0;
			case LessThanOrEqual: order <= 0;
			case GreaterThan: order > 0;
			case GreaterThanOrEqual: order >= 0;
		};
	}

	static inline function compareInts(left:Int, right:Int):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}

	/** Compares signed base-10 integers without narrowing native Unix seconds. */
	static function compareDecimalIntegers(left:String, right:String):Int {
		final leftNegative = StringTools.startsWith(left, "-");
		final rightNegative = StringTools.startsWith(right, "-");
		if (leftNegative != rightNegative)
			return leftNegative ? -1 : 1;
		final leftDigits = normalizedDigits(left, leftNegative);
		final rightDigits = normalizedDigits(right, rightNegative);
		var order = leftDigits.length < rightDigits.length ? -1 : leftDigits.length > rightDigits.length ? 1 : leftDigits < rightDigits ? -1 : leftDigits > rightDigits ? 1 : 0;
		if (leftNegative)
			order = -order;
		return order;
	}

	static function normalizedDigits(value:String, negative:Bool):String {
		var index = negative || StringTools.startsWith(value, "+") ? 1 : 0;
		while (index < value.length - 1 && value.charAt(index) == "0")
			index++;
		return value.substr(index);
	}
}
