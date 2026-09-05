package beadshx.ready;

import beadshx.store.IssueListItem;

/**
	Discovers gate-resumable molecules from copied issue and dependency facts.

	Haxe owns gate selection, parent traversal, hook exclusion, deduplication,
	and ordering. Storage supplies only typed rows and the exact ready issue set.
**/
final class GatedReady {
	static inline final MAX_PARENT_DEPTH = 50;

	public static function discover(readyIssues:Array<IssueListItem>, candidates:Array<IssueListItem>):Array<GatedMolecule> {
		final byId = new Map<String, IssueListItem>();
		final parentOf = new Map<String, String>();
		for (issue in candidates) {
			byId.set(issue.id, issue);
			for (dependency in issue.dependencies)
				if (dependency.dependencyType == "parent-child" && !parentOf.exists(issue.id))
					parentOf.set(issue.id, dependency.dependsOnId);
		}

		final readyIds = new Map<String, Bool>();
		for (issue in readyIssues)
			readyIds.set(issue.id, true);

		final hookedMolecules = new Map<String, Bool>();
		for (issue in candidates)
			if (issue.status == "hooked") {
				hookedMolecules.set(issue.id, true);
				final root = moleculeRoot(issue.id, byId, parentOf);
				if (root != null)
					hookedMolecules.set(root.id, true);
			}

		final gates = [
			for (issue in candidates)
				if (issue.issueType == "gate" && issue.status == "closed") issue
		];
		final resultByRoot = new Map<String, GatedMolecule>();
		for (gate in gates) {
			for (dependent in candidates) {
				if (!readyIds.exists(dependent.id) || !dependsOn(dependent, gate.id))
					continue;
				final root = moleculeRoot(dependent.id, byId, parentOf);
				if (root == null || hookedMolecules.exists(root.id) || resultByRoot.exists(root.id))
					continue;
				resultByRoot.set(root.id, {
					moleculeId: root.id,
					moleculeTitle: root.title,
					closedGate: gate,
					readyStep: dependent
				});
			}
		}

		final result = [for (molecule in resultByRoot) molecule];
		result.sort(function(left, right) return compareStrings(left.moleculeId, right.moleculeId));
		return result;
	}

	static function dependsOn(issue:IssueListItem, targetId:String):Bool {
		for (dependency in issue.dependencies)
			if (dependency.dependsOnId == targetId)
				return true;
		return false;
	}

	static function moleculeRoot(id:String, byId:Map<String, IssueListItem>, parentOf:Map<String, String>):Null<IssueListItem> {
		var current = id;
		final visited = new Map<String, Bool>();
		var depth = 0;
		while (depth < MAX_PARENT_DEPTH && parentOf.exists(current) && !visited.exists(current)) {
			visited.set(current, true);
			current = parentOf.get(current);
			depth++;
		}
		final root = byId.get(current);
		if (root == null)
			return null;
		if (root.issueType == "epic" || root.issueType == "molecule" || root.labels.indexOf("template") >= 0)
			return root;
		return null;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}
}
