import beadshx.ready.MoleculeDependency;
import beadshx.ready.MoleculeReady;
import beadshx.ready.MoleculeStep;
import beadshx.ready.MoleculeSubgraph;
import beadshx.ready.GatedReady;
import beadshx.ready.ReadyExplain;
import beadshx.store.IssueListDependency;
import beadshx.store.IssueListItem;
import beadshx.store.JsonInteger;
import beadshx.store.JsonValue;
import beadshx.store.OptionalInt;
import beadshx.store.StoreResult;

final class Main {
	static var failures = 0;

	static function main():Void {
		blocksAndParallelizes();
		waitsForAnyChild();
		cyclesTerminate();
		hierarchicalFallbackRespectsReparenting();
		explainsReadyBlockedAndCycles();
		discoversAndFiltersGatedMolecules();
		if (failures > 0)
			throw '${failures} ready Haxe contract(s) failed';
		Sys.println("ready Haxe contracts: PASS");
	}

	static function blocksAndParallelizes():Void {
		final steps = [
			step("mol", "open"),
			step("mol.1", "open"),
			step("mol.2", "open"),
			step("mol.3", "open")
		];
		final dependencies = [
			parent("mol.1", "mol"),
			parent("mol.2", "mol"),
			parent("mol.3", "mol"),
			blocks("mol.3", "mol.1")
		];
		final analysis = MoleculeReady.analyze("mol", steps, dependencies);
		equal(analysis.totalSteps, 4);
		equal(analysis.readySteps, 3);
		final blocked = info(analysis, "mol.3");
		equal(blocked.isReady, false);
		equal(blocked.blockedBy.join(","), "mol.1");
		final first = info(analysis, "mol.1");
		equal(first.blocks.join(","), "mol.3");
	}

	static function waitsForAnyChild():Void {
		final steps = [
			step("mol", "open"),
			step("mol.spawn", "open"),
			step("mol.child", "closed"),
			step("mol.gate", "open")
		];
		final dependencies:Array<MoleculeDependency> = [
			parent("mol.spawn", "mol"),
			parent("mol.child", "mol.spawn"),
			parent("mol.gate", "mol"),
			{
				issueId: "mol.gate",
				dependsOnId: "mol.spawn",
				dependencyType: "waits-for",
				metadata: '{"gate":"any-children"}'
			}
		];
		final analysis = MoleculeReady.analyze("mol", steps, dependencies);
		equal(info(analysis, "mol.gate").isReady, true);
	}

	static function cyclesTerminate():Void {
		final steps = [step("mol", "open"), step("mol.1", "open"), step("mol.2", "open")];
		final analysis = MoleculeReady.analyze("mol", steps, [blocks("mol.1", "mol.2"), blocks("mol.2", "mol.1")]);
		equal(info(analysis, "mol.1").isReady, false);
		equal(info(analysis, "mol.2").isReady, false);
	}

	static function hierarchicalFallbackRespectsReparenting():Void {
		final ids = MoleculeSubgraph.collectIds("mol", [
			{id: "mol", parents: []},
			{id: "mol.1", parents: []},
			{id: "mol.1.1", parents: []},
			{id: "mol.2", parents: ["other"]},
			{id: "named-child", parents: ["mol"]},
			{id: "other", parents: []}
		]);
		equal(ids.join(","), "mol,named-child,mol.1,mol.1.1");
	}

	static function explainsReadyBlockedAndCycles():Void {
		final first = issue("first", "open", 1, [], [], 1, 1);
		final second = issue("second", "closed", 2, [], [], 1, 0);
		final ready = issue("ready", "open", 2, [edge("ready", "second", "blocks"), edge("ready", "parent", "parent-child")], [], 2, 0);
		final blocked = issue("blocked", "open", 2, [edge("blocked", "first", "blocks")], ["first"], 1, 0);
		final left = issue("left", "open", 2, [edge("left", "right", "conditional-blocks")], ["right"], 1, 0);
		final right = issue("right", "open", 2, [edge("right", "left", "blocks")], ["left"], 1, 0);
		final explanation = ReadyExplain.build([first, ready], [first, second, ready, blocked, left, right]);
		equal(explanation.ready.length, 2);
		equal(explanation.ready[0].reason, "no blocking dependencies");
		equal(explanation.ready[0].resolvedBlockers, null);
		equal(explanation.ready[1].reason, "1 blocker(s) resolved");
		equal(explanation.ready[1].resolvedBlockers.join(","), "second");
		equal(explanation.ready[1].parent, "parent");
		equal(explanation.blocked.length, 3);
		equal(explanation.blocked[0].blockedBy[0].title, "first");
		equal(explanation.cycles.length, 1);
		equal(explanation.cycles[0].join(","), "left,right");
	}

	static function discoversAndFiltersGatedMolecules():Void {
		final root = issue("mol", "in_progress", 2, [], [], 0, 0, "molecule");
		final gate = issue("mol.gate", "closed", 2, [edge("mol.gate", "mol", "parent-child")], [], 1, 1, "gate", [], "gh:run");
		final step = issue("mol.step", "open", 2, [edge("mol.step", "mol", "parent-child"), edge("mol.step", "mol.gate", "blocks")], [], 2, 0);
		final discovered = GatedReady.discover([step], [root, gate, step]);
		equal(discovered.length, 1);
		equal(discovered[0].moleculeId, "mol");
		equal(discovered[0].closedGate.id, "mol.gate");
		equal(discovered[0].readyStep.id, "mol.step");

		final openGate = issue("mol.gate", "open", 2, gate.dependencies, [], 1, 1, "gate");
		equal(GatedReady.discover([step], [root, openGate, step]).length, 0);

		final hook = issue("mol.hook", "hooked", 2, [edge("mol.hook", "mol", "parent-child")], [], 1, 0);
		equal(GatedReady.discover([step], [root, gate, step, hook]).length, 0);
	}

	static function step(id:String, status:String):MoleculeStep {
		return {
			id: id,
			title: id,
			status: status,
			priority: 2,
			issueType: "task"
		};
	}

	static function parent(issueId:String, parentId:String):MoleculeDependency {
		return {
			issueId: issueId,
			dependsOnId: parentId,
			dependencyType: "parent-child",
			metadata: ""
		};
	}

	static function blocks(issueId:String, blockerId:String):MoleculeDependency {
		return {
			issueId: issueId,
			dependsOnId: blockerId,
			dependencyType: "blocks",
			metadata: ""
		};
	}

	static function edge(issueId:String, dependsOnId:String, dependencyType:String):IssueListDependency {
		return {
			id: '${issueId}-${dependsOnId}',
			issueId: issueId,
			dependsOnId: dependsOnId,
			dependencyType: dependencyType,
			createdAt: "2026-08-25T00:00:00Z",
			createdBy: "tester",
			metadata: "",
			threadId: ""
		};
	}

	static function issue(id:String, status:String, priority:Int, dependencies:Array<IssueListDependency>, blockedBy:Array<String>, dependencyCount:Int,
			dependentCount:Int, issueType:String = "task", labels:Array<String> = null, awaitType:String = ""):IssueListItem {
		final zero = switch JsonInteger.parse("0") {
			case Failure(message): throw message;
			case Success(value): value;
		};
		return {
			id: id,
			title: id,
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: status,
			priority: priority,
			issueType: issueType,
			assignee: "",
			owner: "fixture",
			estimatedMinutes: IntAbsent,
			createdAt: "2026-08-25T00:00:00Z",
			createdBy: "tester",
			updatedAt: "2026-08-25T00:00:00Z",
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: "",
			sourceSystem: "",
			metadata: JsonValue.fromValidatedNative(""),
			wispType: "",
			moleculeType: "",
			longFields: {
				isBlocked: blockedBy.length > 0,
				leaseExpiresAt: "",
				heartbeatAt: "",
				leaseGrantedNode: "",
				compactionLevel: 0,
				compactedAt: "",
				compactedAtCommit: "",
				originalSize: 0,
				sender: "",
				ephemeral: false,
				noHistory: false,
				storageClass: "",
				pinned: false,
				template: false,
				bondedFrom: [],
				awaitType: awaitType,
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
			},
			sender: "",
			labels: labels == null ? [] : labels,
			dependencies: dependencies,
			dependencyCount: dependencyCount,
			dependentCount: dependentCount,
			commentCount: 0,
			parent: "",
			blockedBy: blockedBy,
			blocks: [],
			blockingParent: ""
		};
	}

	static function info(analysis:beadshx.ready.MoleculeReadyAnalysis, id:String):beadshx.ready.MoleculeParallelInfo {
		for (value in analysis.steps)
			if (value.stepId == id)
				return value;
		throw 'missing analysis for ${id}';
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected) {
			failures++;
			Sys.println('expected ${expected}, got ${actual}');
		}
	}
}
