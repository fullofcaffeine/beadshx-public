package beadshx.relation;

import beadshx.relation.DependencyKind.DependencyKindParse;
import haxe.io.Bytes;

typedef DependencyReadPlan = {
	final anchors:Array<String>;
	final allowedTypes:Array<DependencyKind>;
}

enum DependencyPlanResult {
	DependencyPlanReady(plan:DependencyReadPlan);
	DependencyPlanInvalid(message:String);
}

enum DependencyFinishResult {
	DependencyFinishReady(anchors:Array<DependencyAnchor>);
	DependencyFinishInvalid(message:String);
}

/**
	Owns the observable semantics of raw dependency reads.

	Native storage supplies one consistent presence-and-row snapshot. This module
	validates the request and stored relation kinds, collapses repeated anchors,
	filters open-vocabulary kinds, distinguishes missing sources from empty edge
	lists, and pins target/type ordering.
**/
final class DependencyRead {
	public static function prepare(ids:Array<String>, dependencyTypes:Array<String>):DependencyPlanResult {
		final anchors = new Array<String>();
		final seenAnchors = new Map<String, Bool>();
		for (index in 0...ids.length) {
			final id = ids[index];
			if (id == "")
				return DependencyPlanInvalid('validation failed: read edges id ${index} is empty');
			if (!seenAnchors.exists(id)) {
				seenAnchors.set(id, true);
				anchors.push(id);
			}
		}

		final allowedTypes = new Array<DependencyKind>();
		final seenTypes = new Map<String, Bool>();
		for (index in 0...dependencyTypes.length) {
			final raw = dependencyTypes[index];
			switch DependencyKind.parse(raw) {
				case DependencyKindInvalid:
					return
						DependencyPlanInvalid('validation failed: read edges type ${index} is not a usable dependency type (non-empty, max ${DependencyKind.MAX_BYTES} chars)');
				case DependencyKindValid(kind):
					if (!seenTypes.exists(raw)) {
						seenTypes.set(raw, true);
						allowedTypes.push(kind);
					}
			}
		}
		return DependencyPlanReady({anchors: anchors, allowedTypes: allowedTypes});
	}

	public static function finish(plan:DependencyReadPlan, snapshot:DependencySnapshot):DependencyFinishResult {
		final present = new Map<String, Bool>();
		for (id in snapshot.presentIds)
			present.set(id, true);

		final allowed = new Map<String, Bool>();
		for (kind in plan.allowedTypes)
			allowed.set(kind.toString(), true);

		final bySource = new Map<String, Array<DependencyEdge>>();
		for (index in 0...snapshot.edges.length) {
			final raw = snapshot.edges[index];
			if (!present.exists(raw.issueId) || plan.anchors.indexOf(raw.issueId) == -1)
				continue;
			switch DependencyKind.parse(raw.dependencyType) {
				case DependencyKindInvalid:
					return
						DependencyFinishInvalid('validation failed: stored dependency type ${index} is not usable (non-empty, max ${DependencyKind.MAX_BYTES} chars)');
				case DependencyKindValid(kind):
					if (allowed.keys().hasNext() && !allowed.exists(kind.toString()))
						continue;
					var sourceEdges = bySource.get(raw.issueId);
					if (sourceEdges == null) {
						sourceEdges = [];
						bySource.set(raw.issueId, sourceEdges);
					}
					sourceEdges.push({
						id: raw.id,
						issueId: raw.issueId,
						dependsOnId: raw.dependsOnId,
						dependencyType: kind,
						createdAt: raw.createdAt,
						createdBy: raw.createdBy,
						metadata: raw.metadata,
						threadId: raw.threadId
					});
			}
		}

		final anchors = new Array<DependencyAnchor>();
		for (id in plan.anchors) {
			final exists = present.exists(id);
			var edges = bySource.get(id);
			if (edges == null || !exists)
				edges = [];
			edges.sort(compareEdges);
			anchors.push({id: id, edges: edges, missing: !exists});
		}
		return DependencyFinishReady(anchors);
	}

	static function compareEdges(left:DependencyEdge, right:DependencyEdge):Int {
		return compareTargetAndType(left.dependsOnId, left.dependencyType.toString(), right.dependsOnId, right.dependencyType.toString());
	}

	/** Pins the shared edge order by target ID and then dependency type. */
	public static function compareTargetAndType(leftTarget:String, leftType:String, rightTarget:String, rightType:String):Int {
		final target = compareUtf8(leftTarget, rightTarget);
		return target != 0 ? target : compareUtf8(leftType, rightType);
	}

	static function compareUtf8(left:String, right:String):Int {
		final leftBytes = Bytes.ofString(left);
		final rightBytes = Bytes.ofString(right);
		final shared = leftBytes.length < rightBytes.length ? leftBytes.length : rightBytes.length;
		for (index in 0...shared) {
			final leftByte = leftBytes.get(index);
			final rightByte = rightBytes.get(index);
			if (leftByte != rightByte)
				return leftByte < rightByte ? -1 : 1;
		}
		return leftBytes.length == rightBytes.length ? 0 : (leftBytes.length < rightBytes.length ? -1 : 1);
	}
}
