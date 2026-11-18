package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyCycle.walkBlockingCycles;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.relation.RelatedIssue;
import beadshx.store.SqlCycleReader.readBlockingGraph;
import beadshx.store.SqlIssueBatchReader.readIssuesByIds;
import beadshx.store.SqlIssueBatchReader.readWispIdSet;
import beadshx.store.SqlIssueReader.readIssueInTx;

/**
	Upstream would look an `external:` dependency target up in other repositories
	(routes.jsonl and contributor auto-routing); this build reads one database only.
**/
final GRAPH_EXTERNAL_UNAVAILABLE = "graph of an issue with a dependency on another repository is not available yet in this build";

/** The connected issues of one root and the dependency rows between them, as `bd graph <id>` loads them. */
typedef GraphSubgraph = {
	final root:RelatedIssue;

	/** The root, then each issue in the order the walk reached it. */
	final issues:Array<RelatedIssue>;

	/** Each dependency row with both ends in `issues`, by issue and then in row order. */
	final edges:Array<GraphEdge>;
}

/**
	Reads what `bd graph` needs in the caller's SQL snapshot.

	The caller owns the transaction and connection lifetime.
**/
@:goNative
final class SqlGraphReader {
	static final DEP_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	/**
		The cycles `bd graph check` reports, like upstream DetectCyclesInTx.

		The blocking graph is walked once (see walkBlockingCycles). Each member is read
		like GetIssueInTx; like upstream, a member whose read fails is left out, and a
		cycle with no member left is dropped. Each cycle lists the member IDs as read.
		An empty answer means a clean graph.
	**/
	public static function readGraphCycles(context:Context, transaction:Tx):StoreResult<Array<Array<String>>> {
		final graph = switch readBlockingGraph(context, transaction) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final cycles = new Array<Array<String>>();
		for (path in walkBlockingCycles(graph)) {
			final members = new Array<String>();
			for (id in path)
				switch readIssueInTx(context, transaction, id) {
					case Success(issue):
						members.push(issue.id);
					case Failure(_):
				}
			if (members.length > 0)
				cycles.push(members);
		}
		return Success(cycles);
	}

	/**
		Loads the subgraph of an exact root ID, like upstream loadGraphSubgraph.

		The root is read like GetIssueInTx. A breadth-first walk then follows every
		dependency type in both directions: for each issue, its dependents and then its
		dependencies, each list read like GetDependentsInTx and GetDependenciesInTx.
		Like upstream, a failed neighbor read skips the rest of that issue. Then each
		issue's dependency rows are read like GetDependencyRecords, and a row is kept
		when its target is in the subgraph. An `external:<project>:<id>` target that
		names an issue in the subgraph is rewritten to that ID; any other one needs a
		lookup in another repository and fails with GRAPH_EXTERNAL_UNAVAILABLE.
	**/
	public static function readGraphSubgraph(context:Context, transaction:Tx, rootId:String):StoreResult<GraphSubgraph> {
		final root = switch readIssueInTx(context, transaction, rootId) {
			case Failure(message): return Failure('failed to get issue: $message');
			case Success(value): value;
		};
		final issues = [root];
		final known = [root.id => true];
		final queue = [root.id];
		function visit(neighbors:Array<RelatedIssue>):Void {
			for (issue in neighbors)
				if (!known.exists(issue.id)) {
					known.set(issue.id, true);
					issues.push(issue);
					queue.push(issue.id);
				}
		}
		var next = 0;
		while (next < queue.length) {
			final current = queue[next];
			next++;
			switch readNeighbors(context, transaction, 'SELECT issue_id FROM {table} WHERE $DEP_TARGET = ?', current) {
				case Failure(_):
				case Success(dependents):
					visit(dependents);
					switch readNeighbors(context, transaction, 'SELECT $DEP_TARGET AS depends_on_id FROM {table} WHERE issue_id = ?', current) {
						case Failure(_):
						case Success(dependencies):
							visit(dependencies);
					}
			}
		}
		final edges = new Array<GraphEdge>();
		for (issue in issues)
			switch readDependencyRows(context, transaction, issue.id) {
				case Failure(_):
				case Success(rows):
					for (row in rows) {
						final target = externalTarget(row.dependsOnId);
						if (target != null && !known.exists(target))
							return Failure(GRAPH_EXTERNAL_UNAVAILABLE);
						final dependsOnId = target == null ? row.dependsOnId : target;
						if (known.exists(dependsOnId))
							edges.push({issueId: row.issueId, dependsOnId: dependsOnId, type: row.type});
					}
			}
		return Success({root: root, issues: issues, edges: edges});
	}

	/** The `<id>` of an `external:<project>:<id>` reference with a non-empty ID, or null. */
	static function externalTarget(dependsOnId:String):Null<String> {
		if (!StringTools.startsWith(dependsOnId, "external:"))
			return null;
		final separator = dependsOnId.indexOf(":", 9);
		if (separator < 0 || separator == dependsOnId.length - 1)
			return null;
		return dependsOnId.substr(separator + 1);
	}

	/** Reads one ID column from both dependency tables, then those issues like GetIssuesByIDsInTx. */
	static function readNeighbors(context:Context, transaction:Tx, query:String, id:String):StoreResult<Array<RelatedIssue>> {
		final ids = new Array<String>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final queried = transaction.queryContext(context, StringTools.replace(query, "{table}", table), id);
			if (queried.value2 != null)
				return Failure('graph neighbors from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final neighbor = go.NativePointer.of("");
				final scanError = rows.scan(neighbor);
				if (scanError != null) {
					rows.close();
					return Failure('graph neighbors: scan: ${scanError.toString()}');
				}
				ids.push(neighbor.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('graph neighbors: rows from $table: ${rowError.toString()}');
		}
		return readIssuesByIds(context, transaction, ids);
	}

	/** One issue's dependency rows from the table its wisp status selects, like GetDependencyRecordsForIssuesInTx. */
	static function readDependencyRows(context:Context, transaction:Tx, id:String):StoreResult<Array<GraphEdge>> {
		final wisps = switch readWispIdSet(context, transaction, [id]) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final table = wisps.exists(id) ? "wisp_dependencies" : "dependencies";
		final queried = transaction.queryContext(context,
			'SELECT issue_id, $DEP_TARGET AS depends_on_id, type FROM $table WHERE issue_id IN (?) ORDER BY issue_id, depends_on_id, type, id', id);
		if (queried.value2 != null)
			return Failure('get dependency records from $table: ${queried.value2.toString()}');
		final rows = queried.value1;
		final records = new Array<GraphEdge>();
		while (rows.next()) {
			final issueId = go.NativePointer.of("");
			final dependsOnId = go.NativePointer.of("");
			final type = go.NativePointer.of("");
			final scanError = rows.scan(issueId, dependsOnId, type);
			if (scanError != null) {
				rows.close();
				return Failure('get dependency records: scan: ${scanError.toString()}');
			}
			records.push({issueId: issueId.get(), dependsOnId: dependsOnId.get(), type: type.get()});
		}
		rows.close();
		final rowError = rows.err();
		if (rowError != null)
			return Failure('get dependency records: rows: ${rowError.toString()}');
		return Success(records);
	}
}
