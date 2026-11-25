import beadshx.query.QueryCommandRequest;
import beadshx.query.QueryPage;
import beadshx.query.QueryFilter;
import beadshx.query.QueryPlan.QueryExecutionPlan;
import beadshx.query.QueryPlan.QueryFlagField;
import beadshx.query.QueryPlan.QueryPagePolicy;
import beadshx.query.QueryPlan.QueryPlanResult;
import beadshx.query.QueryPlan.QueryPredicateExpression;
import beadshx.query.QueryPlan.QueryPredicateTest;
import beadshx.query.QueryPlan.QueryTimeField;
import beadshx.query.QueryPlanner;
import beadshx.query.QueryPredicate;
import beadshx.query.QuerySyntax;
import beadshx.query.QuerySyntax.QueryComparisonOperator;
import beadshx.query.QuerySyntax.QueryExpression;
import beadshx.query.QueryTimePort;
import beadshx.query.QueryTimePort.QueryTimeInput;
import beadshx.query.QueryTimePort.QueryTimeOutcome;
import beadshx.store.IssueQueryRow;
import beadshx.store.JsonInteger;
import beadshx.store.StoredMetadata;
import beadshx.store.OptionalInt;
import beadshx.store.OptionalQueryInstant;
import beadshx.store.QueryInstant;
import beadshx.store.StoreResult;

final class NoTime implements QueryTimePort {
	public function new() {}

	public function normalize(inputs:Array<QueryTimeInput>):Array<QueryTimeOutcome> {
		if (inputs.length != 0)
			throw "unexpected time input";
		return [];
	}
}

class Main {
	static final time = new NoTime();

	static function main():Void {
		plannerContracts();
		predicateContracts();
		filterContracts();
		pageContracts();
		exactOrderContracts();
		widePriorityContracts();
		metadataContracts();
		Sys.println("query Haxe contracts: PASS");
	}

	static function widePriorityContracts():Void {
		final maximum = switch JsonInteger.parse("9223372036854775807") {
			case Success(value): value;
			case Failure(message): throw message;
		};
		final minimum = switch JsonInteger.parse("-9223372036854775808") {
			case Success(value): value;
			case Failure(message): throw message;
		};
		final high = row("high", "High", "open", maximum, [], "{}");
		final low = row("low", "Low", "open", minimum, [], "{}");
		// workapi display sorting uses numeric comparison, unlike storage merge subtraction.
		final ordered = QueryPage.finish([high, low], page(0, 0, "priority", false), false);
		equal([for (entry in ordered.rows) entry.item.id].join(","), "low,high");
		isFalse(QueryFilter.matches(exactFilter("priority<=1"), high), "wide positive priority filter");
		isTrue(QueryFilter.matches(exactFilter("priority<=1"), low), "wide negative priority filter");
	}

	static function filterContracts():Void {
		final issue = row("bd-10", "An Urgent Fix", "open", 1, ["Backend"], '{"score":7,"owner":"Alice"}');
		isTrue(QueryFilter.matches(exactFilter("status=open AND priority<=1 AND label=backend"), issue), "exact scalar and label filter");
		isFalse(QueryFilter.matches(exactFilter("status=closed"), issue), "exact status mismatch");
		isTrue(QueryFilter.matches(exactFilter('id="bd-*" AND spec="spec-*"'), issue), "identity prefixes");
		isTrue(QueryFilter.matches(exactFilter("metadata.score=7"), issue), "metadata equality filter");
	}

	static function plannerContracts():Void {
		switch plan("status=open") {
			case Planned(ExactQuery(filter, _)):
				equal(filter.status, "open");
				equal(filter.excludeStatuses.length, 0);
			case _:
				fail("status=open was not exact");
		}
		switch plan("type=bug") {
			case Planned(ExactQuery(filter, _)):
				equal(filter.excludeStatuses.join(","), "closed");
			case _:
				fail("type=bug did not receive the default closed exclusion");
		}
		switch plan("status=open OR type=bug") {
			case Planned(PredicateQuery(filter, _, _)):
				equal(filter.excludeStatuses.length, 0);
			case _:
				fail("status OR query was not a predicate");
		}
		switch plan("label=frontend OR label=backend") {
			case Planned(ExactQuery(filter, _)):
				equal(filter.labelsAny.join(","), "frontend,backend");
			case _:
				fail("label OR was not exact");
		}
		expectError("owner=alice", "invalid query expression: owner filtering requires predicate mode");
		expectError("priority!=1", "invalid query expression: priority != requires predicate filtering");
		expectError("parent=x OR type=bug", "invalid query expression: unknown field: parent");
	}

	static function predicateContracts():Void {
		final issue = row("bd-10", "An Urgent Fix", "open", 1, ["Backend"], '{"score":7,"owner":"Alice","present":null}');
		isTrue(QueryPredicate.matches(test(TitleTest(Equal, "urgent")), issue), "title contains");
		isTrue(QueryPredicate.matches(test(LabelTest(Equal, "backend", false)), issue), "folded label");
		isTrue(QueryPredicate.matches(test(MetadataTest("score", "7")), issue), "numeric metadata");
		isTrue(QueryPredicate.matches(test(MetadataTest("owner", "Alice")), issue), "string metadata");
		isTrue(QueryPredicate.matches(test(HasMetadataKeyTest("present")), issue), "null metadata presence");
		isTrue(QueryPredicate.matches(test(MetadataTest("present", "")), issue), "null metadata compares as empty string");
		isFalse(QueryPredicate.matches(test(MetadataTest("present", "null")), issue), "null metadata is not literal null text");
		isTrue(QueryPredicate.matches(test(FlagTest(PinnedFlag, Equal, true)), issue), "typed flag");

		final target = instant("100", 5, 2026, 8, 24);
		isTrue(QueryPredicate.matches(test(TimeTest(CreatedTime, Equal, target)), issue), "same-day time");
		isTrue(QueryPredicate.matches(test(TimeTest(CreatedTime, GreaterThan, instant("99", 9, 2026, 8, 23))), issue), "exact time order");
		isFalse(QueryPredicate.matches(test(TimeTest(ClosedTime, NotEqual, target)), issue), "missing time never matches");
	}

	static function pageContracts():Void {
		final rows = [
			row("bd-10", "third", "open", 1, [], "{}"),
			row("bd-2", "first", "open", 1, [], "{}"),
			row("bd-2.1", "second", "open", 1, [], "{}")
		];
		final idPage = QueryPage.finish(rows, page(2, 0, "id", false), false);
		equal([for (entry in idPage.rows) entry.item.id].join(","), "bd-2,bd-2.1");
		isTrue(idPage.hasMore, "limit reports more rows");
		final offsetPage = QueryPage.finish(rows, page(0, 2, "id", false), false);
		equal([for (entry in offsetPage.rows) entry.item.id].join(","), "bd-10");
		final stable = QueryPage.finish(rows, page(0, 0, "priority", false), false);
		equal([for (entry in stable.rows) entry.item.id].join(","), "bd-10,bd-2,bd-2.1");
	}

	/**
		An exact query's page is upstream's storage order first (sqlbuild.Less over
		the rows that SQL bounded), then the display sort of that page.
	**/
	static function exactOrderContracts():Void {
		final rows = [
			orderRow("t-b", "open", 1, "300"),
			orderRow("t-a", "open", 2, "100"),
			orderRow("t-c", "open", 1, "200"),
			orderRow("t-d", "in_progress", 2, "400"),
			orderRow("t-e", "open", 0, "100")
		];
		// The default order: priority, then the newest first, then the id.
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "", false))), "t-e,t-b,t-c,t-d,t-a");
		// --reverse without --sort reverses only the priority.
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "", true))), "t-d,t-a,t-b,t-c,t-e");
		// A --sort that upstream does not know orders as the default does, also reversed.
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "bogus", true))), "t-d,t-a,t-b,t-c,t-e");
		// Rows that tie on the sort key stay in id order, not in the default order.
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "status", false))), "t-d,t-a,t-b,t-c,t-e");
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "status", true))), "t-a,t-b,t-c,t-e,t-d");
		equal(ids(QueryPage.orderedPage(rows, page(0, 0, "created", true))), "t-a,t-e,t-c,t-b,t-d");
		final limited = QueryPage.orderedPage(rows, page(2, 0, "", true));
		equal(ids(limited), "t-d,t-a");
		isTrue(limited.hasMore, "reversed default page reports more rows");

		// The limit keeps the first rows in byte order of the id; the display sort then compares numbers.
		final numbered = [
			orderRow("x-9", "open", 1, "100"),
			orderRow("x-10", "open", 1, "100"),
			orderRow("x-11", "open", 1, "100")
		];
		final idPage = QueryPage.orderedPage(numbered, page(1, 0, "id", false));
		equal(ids(idPage), "x-10");
		isTrue(idPage.hasMore, "id page reports more rows");
		equal(ids(QueryPage.orderedPage(numbered, page(0, 0, "id", false))), "x-9,x-10,x-11");
		equal(ids(QueryPage.orderedPage(numbered, page(1, 0, "id", true))), "x-11");
	}

	static function ids(result:beadshx.query.QueryPage.QueryPageResult):String {
		return [for (entry in result.rows) entry.item.id].join(",");
	}

	static function orderRow(id:String, status:String, priority:Int, createdSeconds:String):IssueQueryRow {
		final base = row(id, id, status, priority, [], "{}");
		return {
			item: base.item,
			pinned: base.pinned,
			ephemeral: base.ephemeral,
			template: base.template,
			created: instant(createdSeconds, 0, 2026, 8, 24),
			updated: base.updated,
			started: base.started,
			closed: base.closed
		};
	}

	static function metadataContracts():Void {
		final metadata = StoredMetadata.fromSql('{"text":"a\\nvalue","number":1.50,"object":{"x":1},"absent":null}');
		isTrue(metadata.hasTopLevelKey("absent"), "metadata null key is present");
		isFalse(metadata.hasTopLevelKey("missing"), "missing metadata key");
		isTrue(metadata.topLevelQueryEquals("absent", ""), "null value compares as empty string");
		isFalse(metadata.topLevelQueryEquals("absent", "null"), "null value is not the string null");
		final strings = StoredMetadata.fromSql('{"empty":"","literal":"null"}');
		isTrue(strings.topLevelQueryEquals("empty", ""), "empty string control");
		isTrue(strings.topLevelQueryEquals("literal", "null"), "literal null string control");
		isFalse(strings.topLevelQueryEquals("literal", ""), "literal null string is not empty");
		isTrue(metadata.topLevelQueryEquals("text", "a\nvalue"), "decoded metadata string");
		isTrue(metadata.topLevelQueryEquals("number", "1.50"), "raw metadata number");
		isTrue(metadata.topLevelQueryEquals("object", '{"x":1}'), "raw metadata object");
		for (raw in ["{", " ", "[]", "null", '"text"']) {
			final retained = StoredMetadata.fromSql(raw);
			isFalse(retained.hasTopLevelKey("present"), "malformed/non-object metadata has no queried key");
			isFalse(retained.topLevelQueryEquals("present", ""), "malformed/non-object metadata cannot match a field");
			equal(retained.wireValue(), raw);
		}
	}

	static inline function test(value:QueryPredicateTest):QueryPredicateExpression {
		return PredicateComparison(value);
	}

	static function plan(source:String):QueryPlanResult {
		final expression:QueryExpression = switch QuerySyntax.parse(source) {
			case Parsed(value): value;
			case Invalid(message): throw message;
		};
		return QueryPlanner.plan(expression, request(source), time);
	}

	static function exactFilter(source:String):beadshx.store.QueryStorageRequest.QueryStorageFilter {
		return switch plan(source) {
			case Planned(ExactQuery(filter, _)): filter;
			case _: throw 'expected exact plan for "${source}"';
		};
	}

	static function request(source:String):QueryCommandRequest {
		return {
			expression: source,
			provided: true,
			includeClosed: false,
			sortBy: "",
			reverse: false,
			limit: 50,
			offset: 0,
			longFormat: false,
			parseOnly: false
		};
	}

	static function page(limit:Int, offset:Int, sortBy:String, reverse:Bool):QueryPagePolicy {
		return {
			limit: limit,
			offset: offset,
			sortBy: sortBy,
			reverse: reverse
		};
	}

	static function instant(seconds:String, nanosecond:Int, year:Int, month:Int, day:Int):QueryInstant {
		return {
			canonical: seconds,
			epochSeconds: seconds,
			nanosecond: nanosecond,
			year: year,
			month: month,
			day: day
		};
	}

	static function row(id:String, title:String, status:String, priority:JsonInteger, labels:Array<String>, metadata:String):IssueQueryRow {
		return {
			item: {
				id: id,
				title: title,
				description: "Description",
				design: "",
				acceptanceCriteria: "",
				notes: "Notes",
				specId: "spec-1",
				status: status,
				priority: priority,
				issueType: "bug",
				assignee: "Alice",
				owner: "Owner",
				estimatedMinutes: beadshx.store.OptionalIssueInteger.IntegerAbsent,
				createdAt: "2026-08-24T00:00:00Z",
				createdBy: "tester",
				updatedAt: "2026-08-24T00:00:00Z",
				startedAt: "",
				closedAt: "",
				closeReason: "",
				closedBySession: "",
				dueAt: "",
				deferUntil: "",
				externalRef: null,
				sourceSystem: "",
				metadata: StoredMetadata.fromSql(metadata),
				wispType: "",
				moleculeType: "",
				longFields: emptyLongFields(),
				labels: labels,
				dependencies: [],
				dependencyCount: 0,
				dependentCount: 0,
				commentCount: 0,
				parent: "",
				blockedBy: [],
				blocks: [],
				blockingParent: ""
			},
			pinned: true,
			ephemeral: false,
			template: false,
			created: instant("100", 5, 2026, 8, 24),
			updated: instant("100", 5, 2026, 8, 24),
			started: InstantAbsent,
			closed: InstantAbsent
		};
	}

	static function emptyLongFields():beadshx.store.IssueLongFields {
		final zero = switch JsonInteger.parse("0") {
			case Failure(message): throw message;
			case Success(value): value;
		};
		return {
			isBlocked: false,
			leaseExpiresAt: "",
			heartbeatAt: "",
			leaseGrantedNode: "",
			compactionLevel: 0,
			compactedAt: "",
			compactedAtCommit: null,
			originalSize: 0,
			sender: "",
			ephemeral: false,
			noHistory: false,
			storageClass: "",
			pinned: false,
			template: false,
			bondedFrom: [],
			awaitType: "",
			awaitId: "",
			timeout: "",
			timeoutNanos: zero,
			waiters: [],
			sourceFormula: "",
			sourceLocation: "",
			workType: "",
			eventKind: "",
			actor: "",
			target: "",
			payload: ""
		};
	}

	static function expectError(source:String, expected:String):Void {
		switch plan(source) {
			case PlanInvalid(message):
				equal(message, expected);
			case Planned(_):
				fail(source + " unexpectedly planned");
		}
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			fail('expected ${expected}, got ${actual}');
	}

	static function isTrue(actual:Bool, context:String):Void {
		if (!actual)
			fail(context + " was false");
	}

	static function isFalse(actual:Bool, context:String):Void {
		if (actual)
			fail(context + " was true");
	}

	static function fail(message:String):Void {
		throw message;
	}
}
