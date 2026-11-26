package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.RelatedIssue;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.relation.RelationRead.RelationDirection;
import beadshx.store.EpicProgress;
import beadshx.store.OptionalIssueInteger;
import beadshx.store.SqlCommentReader.readSqlIssueCommentDetails;
import beadshx.store.SqlIssueBatchReader.readIssuesByIds;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SQL_READ_ISSUE;
import beadshx.store.SqlIssueRow.SQL_READ_WISP;
import beadshx.store.SqlIssueRow.readSqlIssueFields;

/** Labels and iteration error travel together because the direct store preserves partial rows. */
private typedef SqlDetailLabels = {
	final values:Array<String>;
	final error:Null<String>;
}

/** One dependency edge before its issue is read: the issue at the other end and the edge's type. */
private typedef SqlDependencyEdge = {
	final id:String;
	final dependencyType:String;
}

/**
	The issue-detail read of `bd show`, in one read transaction that the caller owns.

	Why: the embedded store reads every issue detail here, also an issue with
	dependencies or dependents, so a command opens no native store for it and
	checks the schema once.
	What: upstream's store-backed `issueops.Reader.Get`
	(internal/workapi/storereader/reader.go), which an embedded store answers:
	`workapi.GetIssueOrWisp` and `workapi.BuildIssueDetails`
	(internal/workapi/detail.go) over the store's own methods. The issue row
	and its labels come first (`GetIssue`, whose label error is fatal), then
	the labels again (`GetLabels`), the outgoing dependencies with their issues
	(`GetDependenciesWithMetadata`), and the three counts. Those are best
	effort, as upstream ignores their errors. The dependents and the comment
	bodies are read only when the request asks for them, and their errors stop
	the read. The parent is the first parent-child dependency. Dependents, and
	dependencies under `briefDependencies`, keep only the fields of upstream's
	`shallowDep`; an epic's child progress counts its parent-child dependents.
	How: each upstream store call opens its own connection; this reads them
	all in the caller's transaction, which sees the same rows.
**/
@:goNative
final class SqlIssueDetailsReader {
	static inline final DEPENDENCY_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	/** Go's zero `time.Time` in RFC 3339, which a shallow record carries as its created and updated times. */
	static inline final GO_ZERO_TIME = "0001-01-01T00:00:00Z";

	public static function readSqlIssueDetails(context:Context, transaction:Tx, id:String, request:IssueDetailsRequest):StoreResult<IssueDetailsLookup> {
		var fields:Null<SqlIssueFields> = null;
		var isWisp = false;
		switch readSqlIssueFields(context, transaction, SQL_READ_ISSUE, id) {
			case Failure(message):
				return Failure(message);
			case Success(value):
				fields = value;
		}
		if (fields == null) {
			isWisp = true;
			switch readSqlIssueFields(context, transaction, SQL_READ_WISP, id) {
				case Failure(message):
					return Failure(message);
				case Success(value):
					fields = value;
			}
		}
		if (fields == null)
			return Success(DetailsMissing);
		final issue = fields;
		// GetIssueInTx fetches labels before detail assembly and treats this first error as fatal.
		final initialLabels = readLabels(context, transaction, id, isWisp);
		if (initialLabels.error != null)
			return Failure("get issue labels: " + initialLabels.error);

		// BuildIssueDetails overwrites the first labels and deliberately ignores this error.
		final labels = readLabels(context, transaction, id, SqlWispRouting.isActiveWispInTx(context, transaction, id)).values;
		// It ignores a failed dependency read too, which leaves no dependencies.
		final dependencies = switch readSqlDependencyRows(context, transaction, id, Outgoing) {
			case Failure(_): [];
			case Success(rows): rows;
		};
		final dependentCount = countEdges(context, transaction, 'SELECT count(*) FROM dependencies WHERE $DEPENDENCY_TARGET = ?',
			'SELECT count(*) FROM wisp_dependencies WHERE $DEPENDENCY_TARGET = ?', id);
		final dependencyCount = countEdges(context, transaction, "SELECT count(*) FROM dependencies WHERE issue_id = ?",
			"SELECT count(*) FROM wisp_dependencies WHERE issue_id = ?", id);
		var dependents = new Array<IssueDependency>();
		var epicProgress = NoEpicProgress;
		// The requested rows are not best effort: a failed read stops the detail read.
		if (request.includeDependents) {
			switch readSqlDependencyRows(context, transaction, id, Incoming) {
				case Failure(message):
					return Failure('iter dependents $id: $message');
				case Success(rows):
					dependents = [for (row in rows) shallowDependency(row)];
			}
			epicProgress = childProgress(issue.issueType, dependents);
		}
		final commentDetails = switch readSqlIssueCommentDetails(context, transaction, {id: id, includeComments: request.includeComments}) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		var parent = "";
		for (dependency in dependencies)
			if (dependency.dependencyType == "parent-child") {
				parent = dependency.id;
				break;
			}
		final longFields:IssueLongFields = {
			isBlocked: issue.isBlocked,
			leaseExpiresAt: issue.leaseExpiresAt,
			heartbeatAt: issue.heartbeatAt,
			leaseGrantedNode: issue.leaseGrantedNode,
			compactionLevel: issue.compactionLevel,
			compactedAt: issue.compactedAt,
			compactedAtCommit: issue.compactedAtCommit,
			originalSize: issue.originalSize,
			sender: issue.sender,
			ephemeral: issue.ephemeral,
			noHistory: issue.noHistory,
			storageClass: issue.storageClass,
			pinned: issue.pinned,
			template: issue.template,
			bondedFrom: [],
			awaitType: issue.awaitType,
			awaitId: issue.awaitId,
			timeout: issue.timeout,
			timeoutNanos: issue.timeoutNanos,
			waiters: issue.waiters,
			sourceFormula: "",
			sourceLocation: "",
			workType: issue.workType,
			eventKind: issue.eventKind,
			actor: issue.actor,
			target: issue.target,
			payload: issue.payload
		};
		return Success(DetailsFound({
			id: issue.id,
			title: issue.title,
			description: issue.description,
			design: issue.design,
			acceptanceCriteria: issue.acceptanceCriteria,
			notes: issue.notes,
			specId: issue.specId,
			status: issue.status,
			priority: issue.priority,
			issueType: issue.issueType,
			assignee: issue.assignee,
			owner: issue.owner,
			estimatedMinutes: issue.estimatedMinutes,
			createdAt: issue.createdAt,
			createdBy: issue.createdBy,
			updatedAt: issue.updatedAt,
			startedAt: issue.startedAt,
			closedAt: issue.closedAt,
			closeReason: issue.closeReason,
			closedBySession: issue.closedBySession,
			dueAt: issue.dueAt,
			deferUntil: issue.deferUntil,
			externalRef: issue.externalRef,
			sourceSystem: issue.sourceSystem,
			metadata: issue.metadata,
			wispType: issue.wispType,
			moleculeType: issue.moleculeType,
			labels: labels,
			dependencies: request.briefDependencies ? [for (dependency in dependencies) shallowDependency(dependency)] : dependencies,
			dependents: dependents,
			comments: commentDetails.comments,
			parent: parent,
			dependentCount: dependentCount,
			dependencyCount: dependencyCount,
			commentCount: commentDetails.commentCount,
			commentsOmitted: commentDetails.commentsOmitted,
			epicProgress: epicProgress,
			revision: issue.revision,
			longFields: longFields
		}));
	}

	/**
		The issues at the other end of the dependency edges of `id`, with their
		labels and each edge's type: upstream `GetDependenciesWithMetadataInTx`
		(`Outgoing`) and `GetDependentsWithMetadataInTx` (`Incoming`) in
		internal/storage/issueops/dependencies.go. Both read the edges of both
		dependency tables, in table order, then the issues with
		`GetIssuesByIDsInTx` (SqlIssueBatchReader), and skip an edge whose issue
		is missing, such as an external reference.
	**/
	public static function readSqlDependencyRows(context:Context, transaction:Tx, id:String, direction:RelationDirection):StoreResult<Array<RelatedIssue>> {
		final role = switch direction {
			case Outgoing: "dependencies";
			case Incoming: "dependents";
		};
		final edges = new Array<SqlDependencyEdge>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final query = switch direction {
				case Outgoing: 'SELECT $DEPENDENCY_TARGET AS depends_on_id, type FROM $table WHERE issue_id = ?';
				case Incoming: 'SELECT issue_id, type FROM $table WHERE $DEPENDENCY_TARGET = ?';
			};
			final queried = transaction.queryContext(context, query, id);
			if (queried.value2 != null)
				return Failure('get $role from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final edgeId = go.NativePointer.of("");
				final dependencyType = go.NativePointer.of("");
				final scanError = rows.scan(edgeId, dependencyType);
				if (scanError != null) {
					rows.close();
					return Failure('get $role: scan: ${scanError.toString()}');
				}
				edges.push({id: edgeId.get(), dependencyType: dependencyType.get()});
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('get $role: rows from $table: ${rowError.toString()}');
		}
		if (edges.length == 0)
			return Success([]);
		final issues = switch readIssuesByIds(context, transaction, [for (edge in edges) edge.id]) {
			case Failure(message): return Failure('get $role: fetch issues: $message');
			case Success(value): value;
		};
		final byId = new Map<String, RelatedIssue>();
		for (issue in issues)
			byId.set(issue.id, issue);
		final result = new Array<RelatedIssue>();
		for (edge in edges) {
			final issue = byId.get(edge.id);
			if (issue != null)
				result.push(relatedIssue(issue, issue.labels, issue.longFields, edge.dependencyType));
		}
		return Success(result);
	}

	/**
		Upstream's embedded `CountDependents` and `CountDependencies`: one count
		in each dependency table, summed. A failed count is 0, as upstream
		ignores the error and returns 0 when either query fails.
	**/
	static function countEdges(context:Context, transaction:Tx, issueQuery:String, wispQuery:String, id:String):Int {
		final issueCount = go.NativePointer.of(0);
		if (transaction.queryRowContext(context, issueQuery, id).scanInt(issueCount) != null)
			return 0;
		final wispCount = go.NativePointer.of(0);
		if (transaction.queryRowContext(context, wispQuery, id).scanInt(wispCount) != null)
			return 0;
		return issueCount.get() + wispCount.get();
	}

	/** Upstream applyEpicProgress: only an epic with parent-child dependents reports their progress. */
	static function childProgress(issueType:String, dependents:Array<IssueDependency>):EpicProgress {
		if (issueType != "epic")
			return NoEpicProgress;
		var total = 0;
		var closed = 0;
		for (dependent in dependents) {
			if (dependent.dependencyType != "parent-child")
				continue;
			total++;
			if (dependent.status == "closed")
				closed++;
		}
		return total == 0 ? NoEpicProgress : HasEpicProgress(total, closed, total == closed);
	}

	/**
		Upstream shallowDep: the ID, status, type, priority and title of the
		record and the edge's type. Every other field keeps Go's zero value, as
		upstream prints it: the zero time for the created and updated times.
	**/
	static function shallowDependency(row:IssueDependency):IssueDependency {
		return {
			id: row.id,
			title: row.title,
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: row.status,
			priority: row.priority,
			issueType: row.issueType,
			assignee: "",
			owner: "",
			estimatedMinutes: IntegerAbsent,
			createdAt: GO_ZERO_TIME,
			createdBy: "",
			updatedAt: GO_ZERO_TIME,
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: null,
			sourceSystem: "",
			metadata: StoredMetadata.fromSql(""),
			wispType: "",
			moleculeType: "",
			labels: [],
			longFields: {
				isBlocked: false,
				leaseExpiresAt: "",
				heartbeatAt: "",
				leaseGrantedNode: "",
				compactionLevel: JsonInteger.fromInt(0),
				compactedAt: "",
				compactedAtCommit: null,
				originalSize: JsonInteger.fromInt(0),
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
				timeoutNanos: JsonInteger.fromInt(0),
				waiters: [],
				sourceFormula: "",
				sourceLocation: "",
				workType: "",
				eventKind: "",
				actor: "",
				target: "",
				payload: ""
			},
			dependencyType: row.dependencyType
		};
	}

	/** Direct GetLabelsInTx semantics: failed scan discards rows, iteration failure retains them. */
	static function readLabels(context:Context, transaction:Tx, id:String, isWisp:Bool):SqlDetailLabels {
		final table = isWisp ? "wisp_labels" : "labels";
		final queried = transaction.queryContext(context, 'SELECT label FROM $table WHERE issue_id = ? ORDER BY label', id);
		if (queried.value2 != null)
			return {values: [], error: 'get labels: ${queried.value2.toString()}'};
		final rows = queried.value1;
		final labels = new Array<String>();
		while (rows.next()) {
			final label = go.NativePointer.of("");
			final scanError = rows.scan(label);
			if (scanError != null) {
				rows.close();
				return {values: [], error: 'get labels: scan: ${scanError.toString()}'};
			}
			labels.push(label.get());
		}
		// Pinned function evaluates Err before its deferred Close, ignoring Close's return.
		final rowError = rows.err();
		rows.close();
		return {values: labels, error: rowError == null ? null : rowError.toString()};
	}
}
