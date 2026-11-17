package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.RelationRead.RelationReadPlan;
import beadshx.store.SqlIssueRow.SqlIssueFields;
import beadshx.store.SqlIssueRow.SqlIssueScanOrigin;
import beadshx.store.SqlIssueRow.SQL_ISSUE_COLUMNS;
import beadshx.store.SqlIssueRow.scanSqlIssueFields;

/** Complete scalar neighbor and labels; the edge contributes only its relation type. */
typedef SqlRelatedIssue = {
	final fields:SqlIssueFields;
	final labels:Array<String>;
	final dependencyType:String;
}

private typedef NeighborEdge = {
	final id:String;
	final dependencyType:String;
}

/**
	Read both dependency planes and hydrate neighbors in the caller's SQL snapshot.

	The caller owns transaction rollback and connection lifetime. Set-based scalar
	and label reads avoid opening a connection or querying once per neighbor.
	Wisps take precedence over durable issues with the same ID, as upstream does.
	External or missing targets contribute no placeholder issue. Edge order and
	duplicates survive hydration for the stable relation policy to finish later.
**/
@:goNative
final class SqlRelationReader {
	public static function readSqlRelations(context:Context, transaction:Tx, plan:RelationReadPlan):StoreResult<Array<SqlRelatedIssue>> {
		var present = false;
		for (table in ["issues", "wisps"]) {
			final row = transaction.queryRowContext(context, 'SELECT EXISTS(SELECT 1 FROM $table WHERE id = ?)', plan.anchor);
			final exists = go.NativePointer.of(false);
			final scanError = row.scanBool(exists);
			if (scanError != null) {
				if (isTableNotExist(scanError))
					continue;
				return Failure('check issue existence in $table: ${scanError.text()}');
			}
			if (exists.get()) {
				present = true;
				break;
			}
		}
		if (!present)
			return Failure('not found: issue ${plan.anchor}');

		final target = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";
		final selection = switch plan.direction {
			case Incoming: {
					neighbor: "issue_id",
					edgeProjection: "issue_id",
					anchor: target,
					role: "dependents"
				};
			case Outgoing: {
					neighbor: target,
					edgeProjection: '$target AS depends_on_id',
					anchor: "issue_id",
					role: "dependencies"
				};
		};
		final edges = new Array<NeighborEdge>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final queried = transaction.queryContext(context, 'SELECT ${selection.edgeProjection}, type FROM $table WHERE ${selection.anchor} = ?',
				plan.anchor);
			if (queried.value2 != null)
				return Failure('get ${selection.role} from $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final id = go.NativePointer.of("");
				final kind = go.NativePointer.of("");
				final scanError = rows.scan(id, kind);
				if (scanError != null) {
					rows.close();
					return Failure('get ${selection.role}: scan: ${scanError.toString()}');
				}
				edges.push({id: id.get(), dependencyType: kind.get()});
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('get ${selection.role}: rows from $table: ${rowError.toString()}');
		}
		if (edges.length == 0)
			return Success([]);

		final neighborIds = 'SELECT ${selection.neighbor} FROM dependencies WHERE ${selection.anchor} = ? '
			+ 'UNION SELECT ${selection.neighbor} FROM wisp_dependencies WHERE ${selection.anchor} = ?';
		final wispIds = switch readWispNeighbors(context, transaction, neighborIds, plan.anchor) {
			case Failure(message): return Failure('get ${selection.role}: fetch issues: $message');
			case Success(ids): ids;
		};
		var hasPermanent = false;
		for (edge in edges)
			if (!wispIds.exists(edge.id))
				hasPermanent = true;
		final hasWisps = wispIds.keys().hasNext();
		final fields = new Map<String, SqlIssueFields>();
		final labels = new Map<String, Array<String>>();
		for (plane in [{table: "issues", labels: "labels"}, {table: "wisps", labels: "wisp_labels"}]) {
			if (plane.table == "issues" ? !hasPermanent : !hasWisps)
				continue;
			final exclusion = plane.table == "issues"
				&& hasWisps ? " AND NOT EXISTS (SELECT 1 FROM wisps WHERE wisps.id = issues.id)" : "";
			final query = 'SELECT $SQL_ISSUE_COLUMNS FROM ${plane.table} LEFT JOIN leases ON leases.issue_id = ${plane.table}.id '
				+ 'WHERE ${plane.table}.id IN ($neighborIds)$exclusion';
			final queried = transaction.queryContext(context, query, plan.anchor, plan.anchor);
			if (queried.value2 != null)
				return Failure('get ${selection.role}: fetch issues: get issues by IDs from ${plane.table}: ${queried.value2.toString()}');
			final rows = queried.value1;
			final planeIds = new Map<String, Bool>();
			while (rows.next())
				switch scanSqlIssueFields(rows, plan.anchor, RelationHydration) {
					case Failure(message):
						rows.close();
						return Failure('get ${selection.role}: fetch issues: get issues by IDs: scan: $message');
					case Success(value):
						fields.set(value.id, value);
						labels.set(value.id, []);
						planeIds.set(value.id, true);
				}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('get ${selection.role}: fetch issues: get issues by IDs: rows: ${rowError.toString()}');
			if (!planeIds.keys().hasNext())
				continue;

			final labelQuery = 'SELECT issue_id, label FROM ${plane.labels} WHERE issue_id IN ($neighborIds) ORDER BY issue_id, label';
			final queriedLabels = transaction.queryContext(context, labelQuery, plan.anchor, plan.anchor);
			if (queriedLabels.value2 != null)
				return Failure('get ${selection.role}: fetch issues: get issues by IDs: labels from ${plane.labels}: ${queriedLabels.value2.toString()}');
			final labelRows = queriedLabels.value1;
			while (labelRows.next()) {
				final id = go.NativePointer.of("");
				final label = go.NativePointer.of("");
				final scanError = labelRows.scan(id, label);
				if (scanError != null) {
					labelRows.close();
					return Failure('get ${selection.role}: fetch issues: get issues by IDs: scan label: ${scanError.toString()}');
				}
				final issueId = id.get();
				final values = labels.get(issueId);
				if (planeIds.exists(issueId) && values != null)
					values.push(label.get());
			}
			labelRows.close();
			final labelError = labelRows.err();
			if (labelError != null)
				return Failure('get ${selection.role}: fetch issues: get issues by IDs: label rows: ${labelError.toString()}');
		}

		final result = new Array<SqlRelatedIssue>();
		for (edge in edges) {
			final issue = fields.get(edge.id);
			final issueLabels = labels.get(edge.id);
			if (issue != null && issueLabels != null)
				result.push({fields: issue, labels: issueLabels, dependencyType: edge.dependencyType});
		}
		return Success(result);
	}

	/** Probe optional wisps before partitioning; empty planes must not cause extra reads. */
	static function readWispNeighbors(context:Context, transaction:Tx, neighborQuery:String, anchor:String):StoreResult<Map<String, Bool>> {
		final result = new Map<String, Bool>();
		final probe = transaction.queryNativeContext(context, "SELECT 1 FROM wisps LIMIT 1");
		if (probe.error != null) {
			if (isTableNotExist(probe.error))
				return Success(result);
			return Failure('get issues by IDs: build wisp set: wisp id set: probe: ${probe.error.text()}');
		}
		final present = probe.rows.next();
		if (!present) {
			final probeError = probe.rows.errNative();
			probe.rows.closeNative();
			if (probeError != null) {
				if (isTableNotExist(probeError))
					return Success(result);
				return Failure('get issues by IDs: build wisp set: wisp id set: probe: ${probeError.text()}');
			}
			return Success(result);
		}
		final closeError = probe.rows.closeNative();
		if (closeError != null) {
			if (isTableNotExist(closeError))
				return Success(result);
			return Failure('get issues by IDs: build wisp set: wisp id set: probe: ${closeError.text()}');
		}

		final queried = transaction.queryNativeContext(context, 'SELECT id FROM wisps WHERE id IN ($neighborQuery)', anchor, anchor);
		if (queried.error != null)
			return Failure('get issues by IDs: build wisp set: wisp id set: ${queried.error.text()}');
		final rows = queried.rows;
		while (rows.next()) {
			final id = go.NativePointer.of("");
			final scanError = rows.scan(id);
			if (scanError != null) {
				rows.close();
				return Failure('get issues by IDs: build wisp set: wisp id set: scan: ${scanError.toString()}');
			}
			result.set(id.get(), true);
		}
		rows.close();
		final rowError = rows.err();
		if (rowError != null)
			return Failure('get issues by IDs: build wisp set: wisp id set: rows: ${rowError.toString()}');
		return Success(result);
	}
}
