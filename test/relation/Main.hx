import beadshx.relation.DependencyRead;
import beadshx.relation.RelationRead;
import beadshx.relation.RelationRead.prepareRelationRead;
import beadshx.relation.RelationRead.finishRelationRead;
import beadshx.relation.DependencyRead.DependencyFinishResult;
import beadshx.relation.DependencyRead.DependencyPlanResult;

private typedef LabeledRelation = {
	final id:String;
	final dependencyType:String;
	final labels:Array<String>;
	final leaseExpiresAt:String;
}

class Main {
	static function main():Void {
		planningContracts();
		assemblyContracts();
		relatedContracts();
		Sys.println("relation Haxe contracts: PASS");
	}

	static function planningContracts():Void {
		final plan = expectPlan(["bd-a", "bd-a", "bd-b"], ["blocks", "workspace-own"]);
		equal(plan.anchors.join(","), "bd-a,bd-b");
		equal([for (kind in plan.allowedTypes) kind.toString()].join(","), "blocks,workspace-own");
		isTrue(DependencyRead.compareTargetAndType("bd-a", "parent-child", "bd-a.1", "blocks") < 0, "target byte order");
		isTrue(DependencyRead.compareTargetAndType("bd-a", "blocks", "bd-a", "parent-child") < 0, "type byte order");

		expectInvalid(["bd-a", ""], [], "validation failed: read edges id 1 is empty");
		expectInvalid(["bd-a"], [""], "validation failed: read edges type 0 is not a usable dependency type (non-empty, max 32 chars)");
		expectInvalid(["bd-a"], ["ééééééééééééééééé"], "validation failed: read edges type 0 is not a usable dependency type (non-empty, max 32 chars)");
	}

	static function assemblyContracts():Void {
		final plan = expectPlan(["bd-a", "bd-a", "bd-missing"], ["blocks"]);
		final anchors = switch DependencyRead.finish(plan, {
			presentIds: ["bd-a"],
			edges: [
				edge("ignored", "bd-z", "blocks", "outside"),
				edge("bd-a", "external:ticket", "blocks", "external"),
				edge("bd-a", "bd-z", "waits-for", "filtered"),
				edge("bd-a", "bd-z", "blocks", "last"),
				edge("bd-a", "bd-b", "blocks", "first")
			]
		}) {
			case DependencyFinishReady(value): value;
			case DependencyFinishInvalid(message): throw message;
		};
		equal(anchors.length, 2);
		equal(anchors[0].id, "bd-a");
		isFalse(anchors[0].missing, "present anchor");
		equal([for (item in anchors[0].edges) item.dependsOnId].join(","), "bd-b,bd-z,external:ticket");
		equal([for (item in anchors[0].edges) item.metadata].join(","), "first,last,external");
		equal([for (item in anchors[0].edges) item.dependencyType.toString()].join(","), "blocks,blocks,blocks");
		equal(anchors[1].id, "bd-missing");
		isTrue(anchors[1].missing, "missing anchor");
		equal(anchors[1].edges.length, 0);
	}

	static function relatedContracts():Void {
		final kinds = ["blocks", "workspace-own"];
		final plan = switch prepareRelationRead("bd-target", "in", kinds) {
			case RelationPlanInvalid(message): throw message;
			case RelationPlanReady(value): value;
		};
		kinds[0] = "tracks";
		equal(plan.allowedTypes[0].toString(), "blocks");
		switch plan.direction {
			case Incoming:
			case Outgoing:
				fail("incoming direction was reversed");
		}
		final source = [
			related("bd-z", "blocks", "last"),
			related("bd-a", "workspace-own", "custom"),
			related("bd-a", "blocks", "first"),
			related("bd-a", "blocks", "second"),
			related("bd-b", "tracks", "excluded")
		];
		final result = finishRelationRead(plan, source);
		equal([for (row in result) row.title].join(","), "first,second,custom,last");
		equal(source[0].title, "last");
		equal(source.length, 5);
		final labeled:Array<LabeledRelation> = [
			{
				id: "bd-z",
				dependencyType: "blocks",
				labels: ["last"],
				leaseExpiresAt: "2026-02-01T00:00:00Z"
			},
			{
				id: "bd-a",
				dependencyType: "blocks",
				labels: ["first", "kept"],
				leaseExpiresAt: "2026-03-01T00:00:00Z"
			}
		];
		final complete = finishRelationRead(plan, labeled);
		equal(complete[0].labels.join(","), "first,kept");
		equal(complete[0].leaseExpiresAt, "2026-03-01T00:00:00Z");
		isTrue(complete[0] == labeled[1], "relation policy preserves the complete caller-owned record");
		equal(labeled[0].id, "bd-z");
		for (direction in ["", "up", "both"])
			switch prepareRelationRead("bd-target", direction, []) {
				case RelationPlanInvalid(message):
					equal(message, 'validation failed: related requires a direction ("out" or "in"), and has no default');
				case RelationPlanReady(_):
					fail("accepted an invalid relation direction");
			}
		switch prepareRelationRead("", "in", []) {
			case RelationPlanInvalid(message):
				equal(message, "validation failed: related requires an issue ID");
			case RelationPlanReady(_):
				fail("accepted empty anchor");
		}
		for (kind in ["", "ééééééééééééééééé"])
			switch prepareRelationRead("bd-target", "in", [kind]) {
				case RelationPlanInvalid(message):
					equal(message, "validation failed: related type 0 is not a usable dependency type (non-empty, max 32 chars)");
				case RelationPlanReady(_):
					fail("accepted unusable kind");
			}
	}

	static function related(id:String, kind:String, title:String):beadshx.store.IssueDependency {
		return {
			id: id,
			title: title,
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: "open",
			priority: 2,
			issueType: "task",
			assignee: "",
			owner: "",
			estimatedMinutes: beadshx.store.OptionalIssueInteger.IntegerAbsent,
			createdAt: "2026-01-01T00:00:00Z",
			createdBy: "fixture",
			updatedAt: "2026-01-01T00:00:00Z",
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: null,
			sourceSystem: "",
			metadata: beadshx.store.StoredMetadata.fromSql(""),
			wispType: "",
			moleculeType: "",
			dependencyType: kind
		};
	}

	static function expectPlan(ids:Array<String>, types:Array<String>):beadshx.relation.DependencyRead.DependencyReadPlan {
		return switch DependencyRead.prepare(ids, types) {
			case DependencyPlanReady(plan): plan;
			case DependencyPlanInvalid(message): throw message;
		};
	}

	static function expectInvalid(ids:Array<String>, types:Array<String>, expected:String):Void {
		switch DependencyRead.prepare(ids, types) {
			case DependencyPlanInvalid(message):
				equal(message, expected);
			case DependencyPlanReady(_):
				fail("expected invalid dependency plan");
		}
	}

	static function edge(issueId:String, dependsOnId:String, dependencyType:String, metadata:String):beadshx.relation.RawDependencyEdge {
		return {
			id: "",
			issueId: issueId,
			dependsOnId: dependsOnId,
			dependencyType: dependencyType,
			createdAt: "2026-08-27T00:00:00Z",
			createdBy: "tester",
			metadata: metadata,
			threadId: ""
		};
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			fail('expected ${expected}, got ${actual}');
	}

	static function isTrue(value:Bool, label:String):Void {
		if (!value)
			fail(label);
	}

	static function isFalse(value:Bool, label:String):Void {
		if (value)
			fail(label);
	}

	static function fail(message:String):Void {
		throw message;
	}
}
