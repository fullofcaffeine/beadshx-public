package beadshx.query;

import beadshx.query.QuerySyntax.QueryComparisonOperator;
import beadshx.store.QueryInstant;
import beadshx.store.QueryStorageRequest.QueryStorageFilter;

/** Closed time-bearing issue fields supported by predicate evaluation. */
enum QueryTimeField {
	CreatedTime;
	UpdatedTime;
	StartedTime;
	ClosedTime;
}

/** Closed boolean issue fields supported by predicate evaluation. */
enum QueryFlagField {
	PinnedFlag;
	EphemeralFlag;
	TemplateFlag;
}

/** One semantically validated comparison in a Haxe predicate tree. */
enum QueryPredicateTest {
	StatusTest(comparison:QueryComparisonOperator, value:String);
	PriorityTest(comparison:QueryComparisonOperator, value:Int);
	IssueTypeTest(comparison:QueryComparisonOperator, value:String);
	AssigneeTest(comparison:QueryComparisonOperator, value:String, none:Bool);
	OwnerTest(comparison:QueryComparisonOperator, value:String);
	LabelTest(comparison:QueryComparisonOperator, value:String, none:Bool);
	TitleTest(comparison:QueryComparisonOperator, value:String);
	DescriptionTest(comparison:QueryComparisonOperator, value:String, none:Bool);
	NotesTest(comparison:QueryComparisonOperator, value:String);
	TimeTest(field:QueryTimeField, comparison:QueryComparisonOperator, value:QueryInstant);
	IdTest(comparison:QueryComparisonOperator, value:String, wildcard:Bool);
	SpecTest(comparison:QueryComparisonOperator, value:String, wildcard:Bool);
	FlagTest(field:QueryFlagField, comparison:QueryComparisonOperator, value:Bool);
	MetadataTest(key:String, value:String);
	HasMetadataKeyTest(key:String);
}

/** Recursive predicate compiled once before any issue row is inspected. */
enum QueryPredicateExpression {
	PredicateComparison(test:QueryPredicateTest);
	PredicateAnd(left:QueryPredicateExpression, right:QueryPredicateExpression);
	PredicateOr(left:QueryPredicateExpression, right:QueryPredicateExpression);
	PredicateNot(operand:QueryPredicateExpression);
}

/** Haxe-owned page policy shared by direct and strict-proxied execution. */
typedef QueryPagePolicy = {
	final limit:Int;
	final offset:Int;
	final sortBy:String;
	final reverse:Bool;
}

/** Query meaning after syntax, semantic, and time normalization. */
enum QueryExecutionPlan {
	ExactQuery(filter:QueryStorageFilter, page:QueryPagePolicy);
	PredicateQuery(filter:QueryStorageFilter, predicate:QueryPredicateExpression, page:QueryPagePolicy);
}

/** Semantic planning keeps exact pinned diagnostics separate from a valid plan. */
enum QueryPlanResult {
	Planned(plan:QueryExecutionPlan);
	PlanInvalid(message:String);
}
