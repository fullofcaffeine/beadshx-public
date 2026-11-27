package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.NullTime;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyCycle.walkBlockingCycles;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.relation.RelatedIssue;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.SqlCycleReader.readBlockingGraph;
import beadshx.store.SqlIssueBatchReader.readIssuesByIds;
import beadshx.store.SqlIssueBatchReader.readWispIdSet;
import beadshx.store.SqlIssueReader.readIssueInTx;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.scanSqlIssueFields;
import beadshx.store.SqlRelationReader.relatedIssueFromSql;

/** The connected issues of one root and the dependency rows between them, as `bd graph <id>` shows them. */
typedef GraphSubgraph = {
	final root:RelatedIssue;

	/** The root, then each issue in the order the walk reached it. */
	final issues:Array<RelatedIssue>;

	/** Each dependency row with both ends in `issues`, by issue and then in row order. */
	final edges:Array<GraphEdge>;
}

/** A complete dependency row, as upstream GetDependencyRecords reads it. */
typedef GraphDependency = {
	> GraphEdge,

	/** RFC 3339 with nanoseconds, or Go's zero time for a NULL. */
	final createdAt:String;

	final createdBy:String;
	final metadata:String;
	final threadId:String;
}

/**
	What `bd graph <id>` loads before it keeps the rows between its issues (see
	GraphExternal.selectGraphRows).
**/
typedef GraphLoad = {
	final root:RelatedIssue;

	/** The root, then each issue in the order the walk reached it. */
	final issues:Array<RelatedIssue>;

	/** Each issue's dependency rows, issue by issue and in row order; an issue whose rows fail to read has none. */
	final rows:Array<GraphDependency>;
}

/** What `bd graph --all` loads: the issues and their rows, or a status search over the row cap. */
enum AllGraphLoad {
	/** The issues in search order, then each issue's dependency rows as GraphLoad reads them. */
	AllGraphRows(issues:Array<RelatedIssue>, rows:Array<GraphDependency>);

	AllGraphRowLimitExceeded(found:Int, cap:Int);
}

/**
	Reads what `bd graph` needs in the caller's SQL snapshot.

	The caller owns the transaction and connection lifetime.
**/
@:goNative
final class SqlGraphReader {
	static final DEP_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	/**
		The cycles `bd graph check` and `ready --explain` report, like upstream DetectCyclesInTx.

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
		issue's dependency rows are read like GetDependencyRecords (see readRows).
	**/
	public static function readGraphSubgraph(context:Context, transaction:Tx, rootId:String):StoreResult<GraphLoad> {
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
		return Success({root: root, issues: issues, rows: readRows(context, transaction, issues)});
	}

	/**
		Loads what `bd graph --all` groups, like upstream loadAllGraphSubgraphs.

		The open, then the in_progress, then the blocked issues are each searched like
		SearchIssues with only a status filter (see searchStatus); a positive `maxRows`
		applies to each status on its own. Then each issue's rows are read as
		readGraphSubgraph reads them.
	**/
	public static function readAllGraphs(context:Context, transaction:Tx, maxRows:Int):StoreResult<AllGraphLoad> {
		final issues = new Array<RelatedIssue>();
		for (status in ["open", "in_progress", "blocked"])
			switch searchStatus(context, transaction, status, maxRows) {
				case Failure(message):
					return Failure('failed to search issues: $message');
				case Success(found):
					if (maxRows > 0 && found.length > maxRows)
						return Success(AllGraphRowLimitExceeded(found.length, maxRows));
					for (issue in found)
						issues.push(issue);
			}
		return Success(AllGraphRows(issues, readRows(context, transaction, issues)));
	}

	/**
		The issues of exact IDs, each read like GetIssueInTx (see readIssueInTx), as
		upstream reads the issue that an external row's `<id>` resolves to. The first
		failed read fails the whole read.
	**/
	public static function readGraphIssues(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Array<RelatedIssue>> {
		final issues = new Array<RelatedIssue>();
		for (id in ids)
			switch readIssueInTx(context, transaction, id) {
				case Failure(message):
					return Failure('failed to get issue: $message');
				case Success(issue):
					issues.push(issue);
			}
		return Success(issues);
	}

	/** Each issue's dependency rows, issue by issue. Like upstream, a failed read skips that issue's rows. */
	static function readRows(context:Context, transaction:Tx, issues:Array<RelatedIssue>):Array<GraphDependency> {
		final rows = new Array<GraphDependency>();
		for (issue in issues)
			switch readDependencyRows(context, transaction, issue.id) {
				case Failure(_):
				case Success(read):
					for (row in read)
						rows.push(row);
			}
		return rows;
	}

	/**
		Upstream SearchIssuesInTx with only a status filter and the default sort.

		The issues table is searched by priority, newest first, then by ID, with labels;
		a positive cap adds LIMIT cap + 1. When the wisps table has rows that match, an
		issue found in both tables keeps its wisp record, and the two lists are merged
		in the same order, the issues first among equals.
	**/
	static function searchStatus(context:Context, transaction:Tx, status:String, maxRows:Int):StoreResult<Array<RelatedIssue>> {
		final durable = switch searchTable(context, transaction, "issues", "labels", status, maxRows) {
			case Failure(message): return Failure('search issues: $message');
			case Success(value): value;
		};
		final wisps = switch searchTable(context, transaction, "wisps", "wisp_labels", status, maxRows) {
			case Failure(message): return Failure('search wisps (merge): $message');
			case Success(value): value;
		};
		if (wisps.length == 0)
			return Success(durable);
		final wispIds = [for (issue in wisps) issue.id => true];
		final merged = [for (issue in durable) if (!wispIds.exists(issue.id)) issue];
		for (issue in wisps)
			merged.push(issue);
		merged.sort(compareSearchOrder);
		return Success(merged);
	}

	/** Upstream sqlbuild.Less for the default sort: priority, then the newer created_at, then the ID in byte order. */
	static function compareSearchOrder(left:RelatedIssue, right:RelatedIssue):Int {
		final byPriority = left.priority.compare(right.priority);
		if (byPriority != 0)
			return byPriority;
		final leftTime = sortableInstant(left.createdAt);
		final rightTime = sortableInstant(right.createdAt);
		if (leftTime != rightTime)
			return leftTime > rightTime ? -1 : 1;
		return compareUtf8(left.id, right.id);
	}

	/**
		A created_at value that compares as a string in time order. The scanner prints UTC
		times in RFC 3339 and drops trailing zeros from the fraction, so the fraction is
		padded back to nine digits.
	**/
	static function sortableInstant(value:String):String {
		if (value.length < 20 || !StringTools.endsWith(value, "Z"))
			return value;
		var fraction = value.charAt(19) == "." ? value.substring(20, value.length - 1) : "";
		while (fraction.length < 9)
			fraction += "0";
		return value.substr(0, 19) + "." + fraction;
	}

	/**
		One search leg in one table, deduplicated by ID like upstream searchTableInTxT. A
		missing table reads as empty, which is also what upstream's wisp probe decides.
	**/
	static function searchTable(context:Context, transaction:Tx, table:String, labelTable:String, status:String, maxRows:Int):StoreResult<Array<RelatedIssue>> {
		// The row after the cap shows that the cap was exceeded; SqlRowCap keeps a cap of
		// 2147483647 exact (LIMIT 2147483648) without the 32-bit wrap of Haxe Int arithmetic.
		final limit = SqlRowCap.limitClause(maxRows);
		final queried = transaction.queryNativeContext(context,
			'SELECT $SQL_ISSUE_COLUMNS FROM $table LEFT JOIN leases ON leases.issue_id = $table.id WHERE status = ? ORDER BY priority ASC, created_at DESC, id ASC$limit',
			status);
		if (queried.error != null)
			return isTableNotExist(queried.error) ? Success([]) : Failure('search $table: ${queried.error.text()}');
		final rows = queried.rows;
		final found = new Array<SqlIssueRow.SqlIssueFields>();
		final seen = new Map<String, Bool>();
		while (rows.next())
			switch scanSqlIssueFields(rows, "", RelationHydration) {
				case Failure(message):
					rows.closeNative();
					return Failure('search $table: scan: $message');
				case Success(fields):
					if (!seen.exists(fields.id)) {
						seen.set(fields.id, true);
						found.push(fields);
					}
			}
		final rowError = rows.errNative();
		rows.closeNative();
		if (rowError != null)
			return Failure('search $table: rows: ${rowError.text()}');
		final labels = switch readLabels(context, transaction, labelTable, [for (fields in found) fields.id]) {
			case Failure(message): return Failure('search $table: hydrate labels: $message');
			case Success(value): value;
		};
		return Success([
			for (fields in found) {
				final issueLabels = labels.get(fields.id);
				relatedIssueFromSql(fields, issueLabels == null ? [] : issueLabels, "");
			}
		]);
	}

	/** Each issue's labels in byte order, read in batches of 200 like upstream GetLabelsForIssuesFromTableInTx. */
	static function readLabels(context:Context, transaction:Tx, table:String, ids:Array<String>):StoreResult<Map<String, Array<String>>> {
		final labels = new Map<String, Array<String>>();
		var start = 0;
		while (start < ids.length) {
			final batch = ids.slice(start, start + 200);
			start += 200;
			final arguments:Array<Dynamic> = [for (id in batch) id];
			final queried = transaction.queryContext(context,
				'SELECT issue_id, label FROM $table WHERE issue_id IN (${[for (_ in batch) "?"].join(",")}) ORDER BY issue_id, label', ...arguments);
			if (queried.value2 != null)
				return Failure('get labels from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = rows.scan(issueId, label);
				if (scanError != null) {
					rows.close();
					return Failure('get labels: scan: ${scanError.toString()}');
				}
				final values = labels.get(issueId.get());
				if (values == null)
					labels.set(issueId.get(), [label.get()]);
				else
					values.push(label.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('get labels: rows: ${rowError.toString()}');
		}
		return Success(labels);
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

	/**
		One issue's dependency rows from the table its wisp status selects, like
		GetDependencyRecordsForIssuesInTx. Like upstream's scan, a NULL created_by fails the read.
	**/
	static function readDependencyRows(context:Context, transaction:Tx, id:String):StoreResult<Array<GraphDependency>> {
		final wisps = switch readWispIdSet(context, transaction, [id]) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		return readDependencyBatch(context, transaction, wisps.exists(id) ? "wisp_dependencies" : "dependencies", [id]);
	}

	/**
		One batch of getDependencyRecordsIntoFromTable: the dependency rows of
		`ids` from one dependency table, in upstream's order. A NULL created_by
		fails the read, as upstream's scan does.
	**/
	public static function readDependencyBatch(context:Context, transaction:Tx, table:String, ids:Array<String>):StoreResult<Array<GraphDependency>> {
		final arguments:Array<Dynamic> = [for (id in ids) id];
		final queried = transaction.queryContext(context,
			'SELECT issue_id, $DEP_TARGET AS depends_on_id, type, created_at, created_by, metadata, thread_id FROM $table WHERE issue_id IN (${[for (_ in ids) "?"].join(",")}) ORDER BY issue_id, depends_on_id, type, id',
			...arguments);
		if (queried.value2 != null)
			return Failure('get dependency records from $table: ${queried.value2.toString()}');
		final rows = queried.value1;
		final records = new Array<GraphDependency>();
		while (rows.next()) {
			final issueId = go.NativePointer.of("");
			final dependsOnId = go.NativePointer.of("");
			final type = go.NativePointer.of("");
			final createdAt = new NullTime();
			final createdBy = go.NativePointer.of("");
			final metadata = new NullString();
			final threadId = new NullString();
			final scanError = rows.scan(issueId, dependsOnId, type, createdAt, createdBy, metadata, threadId);
			if (scanError != null) {
				rows.close();
				return Failure('get dependency records: scan: ${scanError.toString()}');
			}
			records.push({
				issueId: issueId.get(),
				dependsOnId: dependsOnId.get(),
				type: type.get(),
				createdAt: createdAt.valid ? createdAt.time.format("2006-01-02T15:04:05.999999999Z07:00") : "0001-01-01T00:00:00Z",
				createdBy: createdBy.get(),
				metadata: metadata.valid ? metadata.string : "",
				threadId: threadId.valid ? threadId.string : ""
			});
		}
		rows.close();
		final rowError = rows.err();
		if (rowError != null)
			return Failure('get dependency records: rows: ${rowError.toString()}');
		return Success(records);
	}
}
