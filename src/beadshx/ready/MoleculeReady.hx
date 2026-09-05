package beadshx.ready;

import beadshx.store.JsonValue;

/**
	Computes molecule readiness without delegating product policy to native Go.

	The input contains only copied step and edge facts. Storage construction and
	transaction lifetime remain outside this module, while readiness, waits-for
	gates, blocking depth, and parallel grouping remain authored and tested in Haxe.
**/
final class MoleculeReady {
	public static function analyze(moleculeId:String, steps:Array<MoleculeStep>, dependencies:Array<MoleculeDependency>):MoleculeReadyAnalysis {
		final byId = new Map<String, MoleculeStep>();
		final blockedBy = new Map<String, Array<String>>();
		final blocks = new Map<String, Array<String>>();
		final parentChildren = new Map<String, Array<String>>();
		for (step in steps) {
			byId.set(step.id, step);
			blockedBy.set(step.id, []);
			blocks.set(step.id, []);
		}

		for (dependency in dependencies)
			if (dependency.dependencyType == "parent-child" && byId.exists(dependency.issueId) && byId.exists(dependency.dependsOnId))
				addToMap(parentChildren, dependency.dependsOnId, dependency.issueId);

		for (dependency in dependencies) {
			if (!byId.exists(dependency.issueId) || !byId.exists(dependency.dependsOnId))
				continue;
			switch dependency.dependencyType {
				case "blocks" | "conditional-blocks":
					addBlockingEdge(blockedBy, blocks, dependency.issueId, dependency.dependsOnId);
				case "waits-for":
					final children = valueOrEmpty(parentChildren, dependency.dependsOnId);
					if (children.length == 0)
						continue;
					final anyChild = JsonValue.rawTopLevelStringEquals(dependency.metadata, "gate", "any-children");
					if (anyChild && hasClosedStep(children, byId))
						continue;
					for (childId in children) {
						final child = byId.get(childId);
						if (child != null && child.status != "closed")
							addBlockingEdge(blockedBy, blocks, dependency.issueId, childId);
					}
				case _:
			}
		}

		final infos = new Map<String, MoleculeParallelInfo>();
		var readyCount = 0;
		for (step in steps) {
			final openBlockers = new Array<String>();
			for (blockerId in valueOrEmpty(blockedBy, step.id)) {
				final blocker = byId.get(blockerId);
				if (blocker != null && blocker.status != "closed")
					openBlockers.push(blockerId);
			}
			openBlockers.sort(compareStrings);
			final blockedSteps = valueOrEmpty(blocks, step.id).copy();
			blockedSteps.sort(compareStrings);
			final ready = (step.status == "open" || step.status == "in_progress") && openBlockers.length == 0;
			if (ready)
				readyCount++;
			infos.set(step.id, {
				stepId: step.id,
				status: step.status,
				isReady: ready,
				parallelGroup: "",
				blockedBy: openBlockers,
				blocks: blockedSteps,
				canParallel: []
			});
		}

		final depths = calculateDepths(steps, byId, blockedBy);
		final groups = assignParallelGroups(steps, depths, blockedBy, blocks, infos);
		return {
			moleculeId: moleculeId,
			totalSteps: steps.length,
			readySteps: readyCount,
			groups: groups,
			steps: [for (step in steps) infos.get(step.id)]
		};
	}

	static function addBlockingEdge(blockedBy:Map<String, Array<String>>, blocks:Map<String, Array<String>>, issueId:String, blockerId:String):Void {
		addToMap(blockedBy, issueId, blockerId);
		addToMap(blocks, blockerId, issueId);
	}

	static function addToMap(values:Map<String, Array<String>>, key:String, value:String):Void {
		var items = values.get(key);
		if (items == null) {
			items = [];
			values.set(key, items);
		}
		if (items.indexOf(value) < 0)
			items.push(value);
	}

	static function hasClosedStep(ids:Array<String>, byId:Map<String, MoleculeStep>):Bool {
		for (id in ids) {
			final step = byId.get(id);
			if (step != null && step.status == "closed")
				return true;
		}
		return false;
	}

	static function calculateDepths(steps:Array<MoleculeStep>, byId:Map<String, MoleculeStep>, blockedBy:Map<String, Array<String>>):Map<String, Int> {
		final depths = new Map<String, Int>();
		final visiting = new Map<String, Bool>();
		function depth(id:String):Int {
			final known = depths.get(id);
			if (known != null)
				return known;
			if (visiting.exists(id))
				return 0;
			visiting.set(id, true);
			var maximum = -1;
			for (blockerId in valueOrEmpty(blockedBy, id)) {
				final blocker = byId.get(blockerId);
				if (blocker != null && blocker.status != "closed") {
					final blockerDepth = depth(blockerId);
					if (blockerDepth > maximum)
						maximum = blockerDepth;
				}
			}
			visiting.remove(id);
			final result = maximum + 1;
			depths.set(id, result);
			return result;
		}
		for (step in steps)
			depth(step.id);
		return depths;
	}

	static function assignParallelGroups(steps:Array<MoleculeStep>, depths:Map<String, Int>, blockedBy:Map<String, Array<String>>,
			blocks:Map<String, Array<String>>, infos:Map<String, MoleculeParallelInfo>):Array<MoleculeParallelGroup> {
		final result = new Array<MoleculeParallelGroup>();
		var groupCounter = 0;
		for (depth in 0...steps.length + 1) {
			final atDepth = [for (step in steps) if (depths.get(step.id) == depth) step.id];
			if (atDepth.length == 0)
				continue;
			final parents = new Map<String, String>();
			for (id in atDepth)
				parents.set(id, id);
			function root(id:String):String {
				var value = id;
				while (parents.get(value) != value)
					value = parents.get(value);
				return value;
			}
			for (leftIndex in 0...atDepth.length)
				for (rightIndex in leftIndex + 1...atDepth.length) {
					final left = atDepth[leftIndex];
					final right = atDepth[rightIndex];
					if (!contains(blocks, left, right) && !contains(blocks, right, left) && !contains(blockedBy, left, right)
						&& !contains(blockedBy, right, left)) {
						final leftRoot = root(left);
						final rightRoot = root(right);
						if (leftRoot != rightRoot)
							parents.set(leftRoot, rightRoot);
					}
				}
			final grouped = new Map<String, Array<String>>();
			for (id in atDepth)
				addToMap(grouped, root(id), id);
			for (id in atDepth) {
				final members = grouped.get(id);
				if (members == null || members.length < 2)
					continue;
				groupCounter++;
				final name = 'group-${groupCounter}';
				result.push({name: name, members: members.copy()});
				for (member in members) {
					final info = infos.get(member);
					if (info == null)
						continue;
					info.parallelGroup = name;
					for (other in members)
						if (other != member)
							info.canParallel.push(other);
					info.canParallel.sort(compareStrings);
				}
			}
		}
		return result;
	}

	static inline function contains(values:Map<String, Array<String>>, key:String, value:String):Bool {
		return valueOrEmpty(values, key).indexOf(value) >= 0;
	}

	static function valueOrEmpty(values:Map<String, Array<String>>, key:String):Array<String> {
		final result = values.get(key);
		return result == null ? [] : result;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}
}
