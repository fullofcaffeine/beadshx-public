package beadshx.relation;

import beadshx.relation.GraphLayout.GraphEdge;

/**
	The refusal of `bd graph` when upstream would look the `<id>` of an
	`external:<project>:<id>` row up in another repository (a routes.jsonl prefix
	route or contributor auto-routing). This build reads one database only.
**/
final GRAPH_EXTERNAL_UNAVAILABLE = "graph of an issue with a dependency on another repository is not available yet in this build";

/** What the lookup of an `external:<project>:<id>` row's `<id>` finds, when that ID is not in the graph yet. */
enum ExternalTargetLookup {
	/** An issue of this database, by its full ID. */
	ExternalTargetFound(id:String);

	/** Nothing: upstream leaves the row out. */
	ExternalTargetMissing;

	/** Upstream would look the ID up in another repository. */
	ExternalTargetElsewhere;
}

/** One row that `bd graph` keeps: its index in the loaded rows, and its target after an external rewrite. */
typedef KeptGraphRow = {
	final index:Int;
	final dependsOnId:String;
}

/** The rows that `bd graph` keeps, or the refusal of a row that needs another repository. */
enum GraphRowSelection {
	/** `addedIds` lists each found external target in the order found, once for each row that found it. */
	GraphRowsSelected(addedIds:Array<String>, kept:Array<KeptGraphRow>);

	GraphRowsElsewhere;
}

/**
	The `<id>` of an `external:<project>:<id>` reference with a non-empty ID, or null.

	Upstream splits the reference at its first two colons, so `<id>` keeps any later colon.
**/
function externalTarget(dependsOnId:String):Null<String> {
	if (!StringTools.startsWith(dependsOnId, "external:"))
		return null;
	final separator = dependsOnId.indexOf(":", 9);
	if (separator < 0 || separator == dependsOnId.length - 1)
		return null;
	return dependsOnId.substr(separator + 1);
}

/**
	Keeps the dependency rows of a loaded graph like the loops of upstream
	loadGraphSubgraph and loadAllGraphSubgraphs (cmd/bd/graph.go:431-466, :509-544).

	Why: a row is kept only when both ends are in the graph, and an external row
	can bring its target into the graph.
	What: `rows` are the rows of the loaded issues `loadedIds`, issue by issue, in
	the order upstream reads them. A row whose target is known is kept. An
	external row whose `<id>` is known points to that ID. Any other external row
	calls `lookup` for its `<id>`, once for each such row: a found issue joins
	the graph under its full ID, also when that ID is already in it, and the row
	points to it; a missing one leaves the row out; an ID in another repository
	stops the selection.
	How: one pass that adds each found ID to the known IDs, so later rows can
	point to it. The rows of a found issue are not read, as upstream reads only
	the issues it loaded before this pass.
**/
function selectGraphRows(loadedIds:Array<String>, rows:Array<GraphEdge>, lookup:String->ExternalTargetLookup):GraphRowSelection {
	final known = new Map<String, Bool>();
	for (id in loadedIds)
		known.set(id, true);
	final addedIds = new Array<String>();
	final kept = new Array<KeptGraphRow>();
	for (index in 0...rows.length) {
		var target:Null<String> = rows[index].dependsOnId;
		final external = externalTarget(rows[index].dependsOnId);
		if (external != null && known.exists(external)) {
			target = external;
		} else if (external != null) {
			target = switch lookup(external) {
				case ExternalTargetFound(id):
					addedIds.push(id);
					known.set(id, true);
					id;
				case ExternalTargetMissing:
					null;
				case ExternalTargetElsewhere:
					return GraphRowsElsewhere;
			};
		}
		if (target != null && known.exists(target))
			kept.push({index: index, dependsOnId: target});
	}
	return GraphRowsSelected(addedIds, kept);
}
