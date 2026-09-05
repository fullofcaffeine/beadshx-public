import beadshx.relation.DependencyRead;
import beadshx.relation.DependencyRead.DependencyFinishResult;
import beadshx.relation.DependencyRead.DependencyPlanResult;

class Main {
	static function main():Void {
		planningContracts();
		assemblyContracts();
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
