package beadshx.query;

import beadshx.query.QueryPlan.QueryExecutionPlan;
import beadshx.query.QueryPlan.QueryFlagField;
import beadshx.query.QueryPlan.QueryPagePolicy;
import beadshx.query.QueryPlan.QueryPlanResult;
import beadshx.query.QueryPlan.QueryPredicateExpression;
import beadshx.query.QueryPlan.QueryPredicateTest;
import beadshx.query.QueryPlan.QueryTimeField;
import beadshx.query.QuerySyntax.QueryComparisonOperator;
import beadshx.query.QuerySyntax.QueryExpression;
import beadshx.query.QuerySyntax.QueryValueKind;
import beadshx.query.QueryTimePort.QueryNormalizedTime;
import beadshx.query.QueryTimePort.QueryTimeInput;
import beadshx.query.QueryTimePort.QueryTimeOutcome;
import beadshx.store.IssueListMetadataFilter;
import beadshx.store.OptionalInt;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.QueryOptionalBool;
import beadshx.store.QueryStorageRequest.QueryStorageFilter;

private enum ApplyResult {
	Applied;
	ApplyFailed(message:String);
}

private enum PredicateResult {
	PredicateReady(value:QueryPredicateExpression);
	PredicateFailed(message:String);
}

private enum TimeLookupResult {
	TimeReady(value:QueryNormalizedTime);
	TimeFailed(message:String);
}

/**
	Haxe-owned semantic planner for the pinned Beads query language.

	It preserves the upstream exact-versus-predicate split and its observable
	asymmetries. The native boundary receives only the resulting typed filter and
	fetch shape; it never receives the expression or syntax tree.
**/
final class QueryPlanner {
	public static function plan(expression:QueryExpression, request:QueryCommandRequest, timePort:QueryTimePort):QueryPlanResult {
		if (request.limit < 0)
			return PlanInvalid('invalid limit ${request.limit}: a query limit must be zero or greater; 0 means unlimited');
		if (request.offset < 0)
			return PlanInvalid('invalid offset ${request.offset}: a query offset must be zero or greater');
		if (request.offset > 0 && request.sortBy != "")
			return
				PlanInvalid("invalid offset: an offset cannot be combined with a display order, because the order is applied to the rows the query bounded and each page would be sorted for itself");

		final times = normalizeTimes(expression, timePort);
		final filter = new QueryFilterBuilder();
		final page:QueryPagePolicy = {
			limit: request.limit,
			offset: request.offset,
			sortBy: request.sortBy,
			reverse: request.reverse
		};
		return canUseExactFilter(expression) ? planExact(expression, request, filter, times, page) : planPredicate(expression, request, filter, times, page);
	}

	static function planExact(expression:QueryExpression, request:QueryCommandRequest, filter:QueryFilterBuilder, times:Map<String, QueryTimeOutcome>,
			page:QueryPagePolicy):QueryPlanResult {
		return switch applyExact(expression, filter, times) {
			case ApplyFailed(message): PlanInvalid("invalid query expression: " + message);
			case Applied:
				applyClosedDefault(expression, request.includeClosed, filter);
				Planned(ExactQuery(filter.snapshot(), page));
		};
	}

	static function planPredicate(expression:QueryExpression, request:QueryCommandRequest, filter:QueryFilterBuilder, times:Map<String, QueryTimeOutcome>,
			page:QueryPagePolicy):QueryPlanResult {
		return switch compilePredicate(expression, times) {
			case PredicateFailed(message): PlanInvalid("invalid query expression: " + message);
			case PredicateReady(compiledPredicate):
				extractSafeBase(expression, filter, times);
				applyClosedDefault(expression, request.includeClosed, filter);
				Planned(PredicateQuery(filter.snapshot(), compiledPredicate, page));
		};
	}

	static function canUseExactFilter(expression:QueryExpression):Bool {
		return switch expression {
			case Comparison(_, _, _, _): true;
			case And(left, right): canUseExactFilter(left) && canUseExactFilter(right);
			case Not(Comparison(field, comparison, _, _)): (field == "status" || field == "type") && comparison == Equal;
			case Not(_): false;
			case Or(_, _): collectOrLabels(expression) != null;
		};
	}

	static function collectOrLabels(expression:QueryExpression):Null<Array<String>> {
		return switch expression {
			case Comparison(field, Equal, value, _) if (field == "label" || field == "labels"): [value];
			case Or(left, right):
				final leftLabels = collectOrLabels(left);
				final rightLabels = collectOrLabels(right);
				if (leftLabels == null || rightLabels == null) null; else leftLabels.concat(rightLabels);
			case _: null;
		};
	}

	static function applyExact(expression:QueryExpression, filter:QueryFilterBuilder, times:Map<String, QueryTimeOutcome>):ApplyResult {
		return switch expression {
			case Comparison(field, comparison, value, valueKind): applyExactComparison(field, comparison, value, valueKind, filter, times);
			case And(left, right):
				switch applyExact(left, filter, times) {
					case ApplyFailed(message): ApplyFailed(message);
					case Applied: applyExact(right, filter, times);
				}
			case Not(Comparison(field, comparison, value, _)): applyExactNot(field, comparison, value, filter);
			case Not(_): ApplyFailed("NOT only supports simple comparisons in filter mode");
			case Or(_, _):
				final labels = collectOrLabels(expression);
				if (labels == null) ApplyFailed("OR not supported for this field combination"); else {
					for (label in labels)
						filter.labelsAny.push(label);
					Applied;
				}
		};
	}

	static function applyExactComparison(field:String, comparison:QueryComparisonOperator, value:String, valueKind:QueryValueKind, filter:QueryFilterBuilder,
			times:Map<String, QueryTimeOutcome>):ApplyResult {
		return switch field {
			case "status":
				if (comparison != Equal && comparison != NotEqual) ApplyFailed("status only supports = and != operators"); else {
					final normalized = value.toLowerCase();
					if (!isValidStatus(normalized))
						ApplyFailed("invalid status: " + value);
					else {
						if (comparison == Equal)
							filter.status = normalized;
						else
							filter.excludeStatuses.push(normalized);
						Applied;
					}
				}
			case "priority": applyExactPriority(comparison, value, filter);
			case "type":
				if (comparison != Equal && comparison != NotEqual) ApplyFailed("type only supports = and != operators"); else {
					final normalized = value.toLowerCase();
					if (comparison == Equal)
						filter.issueType = normalized;
					else
						filter.excludeTypes.push(normalized);
					Applied;
				}
			case "assignee":
				if (comparison != Equal) ApplyFailed("assignee only supports = operator"); else {
					if (isNone(value))
						filter.noAssignee = true;
					else
						filter.assignee = value;
					Applied;
				}
			case "owner": ApplyFailed("owner filtering requires predicate mode");
			case "label" | "labels":
				if (comparison != Equal) ApplyFailed("label only supports = operator"); else {
					if (isNone(value))
						filter.noLabels = true;
					else
						filter.labels.push(value);
					Applied;
				}
			case "title":
				if (comparison != Equal) ApplyFailed("title only supports = operator (use title contains pattern)"); else {
					filter.titleContains = value;
					Applied;
				}
			case "description" | "desc":
				if (comparison != Equal) ApplyFailed("description only supports = operator (use desc contains pattern)"); else {
					if (isNone(value))
						filter.emptyDescription = true;
					else
						filter.descriptionContains = value;
					Applied;
				}
			case "notes":
				if (comparison != Equal) ApplyFailed("notes only supports = operator"); else {
					filter.notesContains = value;
					Applied;
				}
			case "created" | "created_at": applyExactTime("created", comparison, value, valueKind, filter, times);
			case "updated" | "updated_at": applyExactTime("updated", comparison, value, valueKind, filter, times);
			case "closed" | "closed_at": applyExactTime("closed", comparison, value, valueKind, filter, times);
			case "started" | "started_at": applyExactTime("started", comparison, value, valueKind, filter, times);
			case "id":
				if (comparison != Equal) ApplyFailed("id only supports = operator"); else {
					if (StringTools.endsWith(value, "*"))
						filter.idPrefix = value.substr(0, value.length - 1);
					else
						filter.ids.push(value);
					Applied;
				}
			case "spec" | "spec_id":
				if (comparison != Equal) ApplyFailed("spec only supports = operator"); else {
					filter.specPrefix = StringTools.endsWith(value, "*") ? value.substr(0, value.length - 1) : value;
					Applied;
				}
			case "parent":
				if (comparison != Equal) ApplyFailed("parent only supports = operator"); else {
					filter.parentId = value;
					Applied;
				}
			case "pinned" | "ephemeral" | "template": applyExactFlag(field, comparison, value, filter);
			case "mol_type":
				if (comparison != Equal) ApplyFailed("mol_type only supports = operator"); else {
					final normalized = value.toLowerCase();
					if (normalized != "swarm" && normalized != "patrol" && normalized != "work")
						ApplyFailed("invalid mol_type: " + value);
					else {
						filter.moleculeType = normalized;
						Applied;
					}
				}
			case "has_metadata_key":
				if (comparison != Equal) ApplyFailed("has_metadata_key only supports = operator"); else if (!isMetadataKey(value))
					ApplyFailed(metadataKeyError(value)); else {
					filter.hasMetadataKey = value;
					Applied;
				}
			case _ if (StringTools.startsWith(field, "metadata.")):
				if (comparison != Equal) ApplyFailed("metadata fields only support = operator"); else {
					final key = field.substr(9);
					if (!isMetadataKey(key))
						ApplyFailed(metadataKeyError(key));
					else {
						filter.setMetadata(key, value);
						Applied;
					}
				}
			case _: ApplyFailed("unknown field: " + field);
		};
	}

	static function applyExactPriority(comparison:QueryComparisonOperator, value:String, filter:QueryFilterBuilder):ApplyResult {
		final priority = parseInteger(value);
		if (priority == null)
			return ApplyFailed("invalid priority value: " + value);
		if (priority < 0 || priority > 4)
			return ApplyFailed("priority must be between 0 and 4");
		return switch comparison {
			case Equal:
				filter.priority = IntPresent(priority);
				Applied;
			case NotEqual: ApplyFailed("priority != requires predicate filtering");
			case LessThan:
				final maximum = priority - 1;
				if (maximum < 0) ApplyFailed('priority < ${priority} matches nothing'); else {
					filter.priorityMax = IntPresent(maximum);
					Applied;
				}
			case LessThanOrEqual:
				filter.priorityMax = IntPresent(priority);
				Applied;
			case GreaterThan:
				final minimum = priority + 1;
				if (minimum > 4) ApplyFailed('priority > ${priority} matches nothing'); else {
					filter.priorityMin = IntPresent(minimum);
					Applied;
				}
			case GreaterThanOrEqual:
				filter.priorityMin = IntPresent(priority);
				Applied;
		};
	}

	static function applyExactTime(field:String, comparison:QueryComparisonOperator, value:String, valueKind:QueryValueKind, filter:QueryFilterBuilder,
			times:Map<String, QueryTimeOutcome>):ApplyResult {
		return switch lookupTime(value, valueKind, times) {
			case TimeFailed(message): ApplyFailed('invalid ${field} time: ${message}');
			case TimeReady(time): applyExactNormalizedTime(field, comparison, time, filter);
		};
	}

	static function applyExactNormalizedTime(field:String, comparison:QueryComparisonOperator, time:QueryNormalizedTime,
			filter:QueryFilterBuilder):ApplyResult {
		return switch field {
			case "created": applyCreatedTime(comparison, time, filter);
			case "updated": applyUpdatedTime(comparison, time, filter);
			case "closed": applyClosedTime(comparison, time, filter);
			case "started": applyStartedTime(comparison, time, filter);
			case _: ApplyFailed("unknown time field: " + field);
		};
	}

	static function applyCreatedTime(comparison:QueryComparisonOperator, time:QueryNormalizedTime, filter:QueryFilterBuilder):ApplyResult {
		return switch comparison {
			case Equal:
				filter.createdAfter = InstantPresent(time.dayStart);
				filter.createdBefore = InstantPresent(time.nextDay);
				Applied;
			case GreaterThan | GreaterThanOrEqual:
				filter.createdAfter = InstantPresent(time.target);
				Applied;
			case LessThan:
				filter.createdBefore = InstantPresent(time.target);
				Applied;
			case LessThanOrEqual:
				filter.createdBefore = InstantPresent(time.endOfDay);
				Applied;
			case NotEqual: ApplyFailed("created does not support != operator");
		};
	}

	static function applyUpdatedTime(comparison:QueryComparisonOperator, time:QueryNormalizedTime, filter:QueryFilterBuilder):ApplyResult {
		return switch comparison {
			case Equal:
				filter.updatedAfter = InstantPresent(time.dayStart);
				filter.updatedBefore = InstantPresent(time.nextDay);
				Applied;
			case GreaterThan | GreaterThanOrEqual:
				filter.updatedAfter = InstantPresent(time.target);
				Applied;
			case LessThan:
				filter.updatedBefore = InstantPresent(time.target);
				Applied;
			case LessThanOrEqual:
				filter.updatedBefore = InstantPresent(time.endOfDay);
				Applied;
			case NotEqual: ApplyFailed("updated does not support != operator");
		};
	}

	static function applyClosedTime(comparison:QueryComparisonOperator, time:QueryNormalizedTime, filter:QueryFilterBuilder):ApplyResult {
		return switch comparison {
			case GreaterThan | GreaterThanOrEqual:
				filter.closedAfter = InstantPresent(time.target);
				Applied;
			case LessThan:
				filter.closedBefore = InstantPresent(time.target);
				Applied;
			case LessThanOrEqual:
				filter.closedBefore = InstantPresent(time.endOfDay);
				Applied;
			case Equal | NotEqual: ApplyFailed('closed does not support ${operatorText(comparison)} operator');
		};
	}

	static function applyStartedTime(comparison:QueryComparisonOperator, time:QueryNormalizedTime, filter:QueryFilterBuilder):ApplyResult {
		return switch comparison {
			case GreaterThan | GreaterThanOrEqual:
				filter.startedAfter = InstantPresent(time.target);
				Applied;
			case LessThan:
				filter.startedBefore = InstantPresent(time.target);
				Applied;
			case LessThanOrEqual:
				filter.startedBefore = InstantPresent(time.endOfDay);
				Applied;
			case Equal | NotEqual: ApplyFailed('started does not support ${operatorText(comparison)} operator');
		};
	}

	static function applyExactFlag(field:String, comparison:QueryComparisonOperator, value:String, filter:QueryFilterBuilder):ApplyResult {
		if (comparison != Equal)
			return ApplyFailed('${field} only supports = operator');
		final parsed = parseBoolean(value);
		if (parsed == null)
			return ApplyFailed('invalid boolean value for ${field}: ${value}');
		switch field {
			case "pinned":
				filter.pinned = BoolPresent(parsed);
			case "ephemeral":
				filter.ephemeral = BoolPresent(parsed);
			case "template":
				filter.template = BoolPresent(parsed);
			case _:
		}
		return Applied;
	}

	static function applyExactNot(field:String, comparison:QueryComparisonOperator, value:String, filter:QueryFilterBuilder):ApplyResult {
		return switch field {
			case "status":
				if (comparison != Equal) ApplyFailed("NOT status only supports = operator"); else {
					filter.excludeStatuses.push(value.toLowerCase());
					Applied;
				}
			case "type":
				if (comparison != Equal) ApplyFailed("NOT type only supports = operator"); else {
					filter.excludeTypes.push(value.toLowerCase());
					Applied;
				}
			case _: ApplyFailed('NOT not supported for field ${field} in filter mode');
		};
	}

	static function compilePredicate(expression:QueryExpression, times:Map<String, QueryTimeOutcome>):PredicateResult {
		return switch expression {
			case Comparison(field, comparison, value, valueKind): compilePredicateComparison(field, comparison, value, valueKind, times);
			case And(left, right): combinePredicates(left, right, times, true);
			case Or(left, right): combinePredicates(left, right, times, false);
			case Not(operand):
				switch compilePredicate(operand, times) {
					case PredicateFailed(message): PredicateFailed(message);
					case PredicateReady(value): PredicateReady(PredicateNot(value));
				}
		};
	}

	static function combinePredicates(left:QueryExpression, right:QueryExpression, times:Map<String, QueryTimeOutcome>, and:Bool):PredicateResult {
		return switch compilePredicate(left, times) {
			case PredicateFailed(message): PredicateFailed(message);
			case PredicateReady(leftPredicate):
				switch compilePredicate(right, times) {
					case PredicateFailed(message): PredicateFailed(message);
					case PredicateReady(rightPredicate):
						PredicateReady(and ? PredicateAnd(leftPredicate, rightPredicate) : PredicateOr(leftPredicate, rightPredicate));
				}
		};
	}

	static function compilePredicateComparison(field:String, comparison:QueryComparisonOperator, value:String, valueKind:QueryValueKind,
			times:Map<String, QueryTimeOutcome>):PredicateResult {
		return switch field {
			case "status":
				if (!supportsEquality(comparison)) PredicateFailed('status does not support ${operatorText(comparison)} operator'); else
					ready(StatusTest(comparison, value.toLowerCase()));
			case "priority":
				final priority = parseInteger(value);
				if (priority == null) PredicateFailed("invalid priority: " + value); else ready(PriorityTest(comparison, priority));
			case "type":
				if (!supportsEquality(comparison)) PredicateFailed('type does not support ${operatorText(comparison)} operator'); else
					ready(IssueTypeTest(comparison, value.toLowerCase()));
			case "assignee":
				if (!supportsEquality(comparison)) PredicateFailed('assignee does not support ${operatorText(comparison)} operator'); else
					ready(AssigneeTest(comparison, value, isNone(value)));
			case "owner":
				if (!supportsEquality(comparison)) PredicateFailed('owner does not support ${operatorText(comparison)} operator'); else
					ready(OwnerTest(comparison, value));
			case "label" | "labels":
				if (!supportsEquality(comparison)) PredicateFailed('label does not support ${operatorText(comparison)} operator'); else
					ready(LabelTest(comparison, value, isNone(value)));
			case "title":
				if (!supportsEquality(comparison)) PredicateFailed('title does not support ${operatorText(comparison)} operator'); else
					ready(TitleTest(comparison, value.toLowerCase()));
			case "description" | "desc":
				if (!supportsEquality(comparison)) PredicateFailed('description does not support ${operatorText(comparison)} operator'); else
					ready(DescriptionTest(comparison, value, isNone(value)));
			case "notes":
				if (!supportsEquality(comparison)) PredicateFailed('notes does not support ${operatorText(comparison)} operator'); else
					ready(NotesTest(comparison, value.toLowerCase()));
			case "created" | "created_at": compilePredicateTime(CreatedTime, "created", comparison, value, valueKind, times);
			case "updated" | "updated_at": compilePredicateTime(UpdatedTime, "updated", comparison, value, valueKind, times);
			case "closed" | "closed_at": compilePredicateTime(ClosedTime, "closed", comparison, value, valueKind, times);
			case "started" | "started_at": compilePredicateTime(StartedTime, "started", comparison, value, valueKind, times);
			case "id": compileIdentityPredicate(false, comparison, value);
			case "spec" | "spec_id": compileIdentityPredicate(true, comparison, value);
			case "pinned" | "ephemeral" | "template":
				final parsed = parseBoolean(value);
				if (parsed == null) PredicateFailed("invalid boolean value: " + value); else if (!supportsEquality(comparison))
					PredicateFailed('boolean field does not support ${operatorText(comparison)} operator'); else ready(FlagTest(queryFlag(field), comparison,
					parsed));
			case "has_metadata_key":
				if (comparison != Equal) PredicateFailed("has_metadata_key only supports = operator"); else if (!isMetadataKey(value))
					PredicateFailed(metadataKeyError(value)); else ready(HasMetadataKeyTest(value));
			case _ if (StringTools.startsWith(field, "metadata.")):
				final key = field.substr(9);
				if (comparison != Equal) PredicateFailed("metadata fields only support = operator"); else if (!isMetadataKey(key))
					PredicateFailed(metadataKeyError(key)); else ready(MetadataTest(key, value));
			case _: PredicateFailed("unknown field: " + field);
		};
	}

	static function compilePredicateTime(field:QueryTimeField, name:String, comparison:QueryComparisonOperator, value:String, valueKind:QueryValueKind,
			times:Map<String, QueryTimeOutcome>):PredicateResult {
		return switch lookupTime(value, valueKind, times) {
			case TimeFailed(message): PredicateFailed('invalid ${name} time: ${message}');
			case TimeReady(time): ready(TimeTest(field, comparison, time.target));
		};
	}

	static function compileIdentityPredicate(spec:Bool, comparison:QueryComparisonOperator, value:String):PredicateResult {
		final wildcard = StringTools.endsWith(value, "*");
		if (wildcard && !supportsEquality(comparison))
			return PredicateFailed((spec ? "spec" : "id") + " with wildcard only supports = and != operators");
		if (!supportsEquality(comparison))
			return PredicateFailed((spec ? "spec" : "id") + ' does not support ${operatorText(comparison)} operator');
		return ready(spec ? SpecTest(comparison, value, wildcard) : IdTest(comparison, value, wildcard));
	}

	static inline function ready(test:QueryPredicateTest):PredicateResult {
		return PredicateReady(PredicateComparison(test));
	}

	static function extractSafeBase(expression:QueryExpression, filter:QueryFilterBuilder, times:Map<String, QueryTimeOutcome>):Void {
		switch expression {
			case Comparison(field, comparison, value, valueKind):
				applyExactComparison(field, comparison, value, valueKind, filter, times);
			case And(left, right):
				extractSafeBase(left, filter, times);
				extractSafeBase(right, filter, times);
			case Not(Comparison(field, comparison, value, _)):
				applyExactNot(field, comparison, value, filter);
			case Not(_) | Or(_, _):
		}
	}

	static function applyClosedDefault(expression:QueryExpression, includeClosed:Bool, filter:QueryFilterBuilder):Void {
		if (!includeClosed && filter.status == "" && !mentionsStatus(expression))
			filter.excludeStatuses.push("closed");
	}

	static function mentionsStatus(expression:QueryExpression):Bool {
		return switch expression {
			case Comparison(field, _, _, _): field == "status";
			case And(left, right) | Or(left, right): mentionsStatus(left) || mentionsStatus(right);
			case Not(operand): mentionsStatus(operand);
		};
	}

	static function normalizeTimes(expression:QueryExpression, port:QueryTimePort):Map<String, QueryTimeOutcome> {
		final inputs = new Array<QueryTimeInput>();
		final keys = new Array<String>();
		collectTimeInputs(expression, inputs, keys);
		final result = new Map<String, QueryTimeOutcome>();
		if (inputs.length == 0)
			return result;
		final outcomes = port.normalize(inputs);
		for (index in 0...keys.length) {
			result.set(keys[index], index < outcomes.length ? outcomes[index] : TimeInvalid("native time normalization returned no outcome"));
		}
		return result;
	}

	static function collectTimeInputs(expression:QueryExpression, inputs:Array<QueryTimeInput>, keys:Array<String>):Void {
		switch expression {
			case Comparison(field, _, value, valueKind) if (isTimeField(field)):
				final key = timeKey(value, valueKind);
				if (keys.indexOf(key) < 0) {
					keys.push(key);
					inputs.push({value: value, durationAgo: valueKind == DurationValue});
				}
			case Comparison(_, _, _, _):
			case And(left, right) | Or(left, right):
				collectTimeInputs(left, inputs, keys);
				collectTimeInputs(right, inputs, keys);
			case Not(operand):
				collectTimeInputs(operand, inputs, keys);
		}
	}

	static function lookupTime(value:String, valueKind:QueryValueKind, times:Map<String, QueryTimeOutcome>):TimeLookupResult {
		final outcome = times.get(timeKey(value, valueKind));
		if (outcome == null)
			return TimeFailed("native time normalization returned no outcome");
		return switch outcome {
			case TimeNormalized(time): TimeReady(time);
			case TimeInvalid(message): TimeFailed(message);
		};
	}

	static inline function timeKey(value:String, valueKind:QueryValueKind):String {
		return (valueKind == DurationValue ? "duration:" : "relative:") + value;
	}

	static function isTimeField(field:String):Bool {
		return field == "created" || field == "created_at" || field == "updated" || field == "updated_at" || field == "closed" || field == "closed_at"
			|| field == "started" || field == "started_at";
	}

	static function isValidStatus(value:String):Bool {
		return value == "open" || value == "in_progress" || value == "blocked" || value == "deferred" || value == "closed" || value == "pinned"
			|| value == "hooked";
	}

	static function parseInteger(value:String):Null<Int> {
		if (!new EReg("^[+-]?[0-9]+$", "").match(value))
			return null;
		return Std.parseInt(value);
	}

	static function parseBoolean(value:String):Null<Bool> {
		return switch value.toLowerCase() {
			case "true" | "yes" | "1": true;
			case "false" | "no" | "0": false;
			case _: null;
		};
	}

	static inline function isNone(value:String):Bool {
		final normalized = value.toLowerCase();
		return value == "" || normalized == "none" || normalized == "null";
	}

	static inline function supportsEquality(comparison:QueryComparisonOperator):Bool {
		return comparison == Equal || comparison == NotEqual;
	}

	static function isMetadataKey(value:String):Bool {
		return new EReg("^[a-zA-Z_][a-zA-Z0-9_./]*$", "").match(value);
	}

	static function metadataKeyError(value:String):String {
		return 'invalid metadata key "${value}": must match ^[a-zA-Z_][a-zA-Z0-9_./]*$';
	}

	static function operatorText(comparison:QueryComparisonOperator):String {
		return switch comparison {
			case Equal: "=";
			case NotEqual: "!=";
			case LessThan: "<";
			case LessThanOrEqual: "<=";
			case GreaterThan: ">";
			case GreaterThanOrEqual: ">=";
		};
	}

	static function queryFlag(field:String):QueryFlagField {
		return switch field {
			case "pinned": PinnedFlag;
			case "ephemeral": EphemeralFlag;
			case "template": TemplateFlag;
			case _: throw "validated query flag escaped its boundary";
		};
	}
}

private final class QueryFilterBuilder {
	public var status = "";
	public final excludeStatuses = new Array<String>();
	public var priority:OptionalInt = IntAbsent;
	public var priorityMin:OptionalInt = IntAbsent;
	public var priorityMax:OptionalInt = IntAbsent;
	public var issueType = "";
	public final excludeTypes = new Array<String>();
	public var assignee = "";
	public var noAssignee = false;
	public final labels = new Array<String>();
	public final labelsAny = new Array<String>();
	public var noLabels = false;
	public var titleContains = "";
	public var descriptionContains = "";
	public var notesContains = "";
	public var emptyDescription = false;
	public var createdAfter:OptionalQueryInstant = InstantAbsent;
	public var createdBefore:OptionalQueryInstant = InstantAbsent;
	public var updatedAfter:OptionalQueryInstant = InstantAbsent;
	public var updatedBefore:OptionalQueryInstant = InstantAbsent;
	public var startedAfter:OptionalQueryInstant = InstantAbsent;
	public var startedBefore:OptionalQueryInstant = InstantAbsent;
	public var closedAfter:OptionalQueryInstant = InstantAbsent;
	public var closedBefore:OptionalQueryInstant = InstantAbsent;
	public final ids = new Array<String>();
	public var idPrefix = "";
	public var specPrefix = "";
	public var parentId = "";
	public var pinned:QueryOptionalBool = BoolAbsent;
	public var ephemeral:QueryOptionalBool = BoolAbsent;
	public var template:QueryOptionalBool = BoolAbsent;
	public var moleculeType = "";
	public final metadataFields = new Array<IssueListMetadataFilter>();
	public var hasMetadataKey = "";

	public function new() {}

	public function setMetadata(key:String, value:String):Void {
		for (index in 0...metadataFields.length) {
			if (metadataFields[index].key == key) {
				metadataFields[index] = {key: key, value: value};
				return;
			}
		}
		metadataFields.push({key: key, value: value});
	}

	public function snapshot():QueryStorageFilter {
		return {
			status: status,
			excludeStatuses: excludeStatuses.copy(),
			priority: priority,
			priorityMin: priorityMin,
			priorityMax: priorityMax,
			issueType: issueType,
			excludeTypes: excludeTypes.copy(),
			assignee: assignee,
			noAssignee: noAssignee,
			labels: labels.copy(),
			labelsAny: labelsAny.copy(),
			noLabels: noLabels,
			titleContains: titleContains,
			descriptionContains: descriptionContains,
			notesContains: notesContains,
			emptyDescription: emptyDescription,
			createdAfter: createdAfter,
			createdBefore: createdBefore,
			updatedAfter: updatedAfter,
			updatedBefore: updatedBefore,
			startedAfter: startedAfter,
			startedBefore: startedBefore,
			closedAfter: closedAfter,
			closedBefore: closedBefore,
			ids: ids.copy(),
			idPrefix: idPrefix,
			specPrefix: specPrefix,
			parentId: parentId,
			pinned: pinned,
			ephemeral: ephemeral,
			template: template,
			moleculeType: moleculeType,
			metadataFields: metadataFields.copy(),
			hasMetadataKey: hasMetadataKey
		};
	}
}
