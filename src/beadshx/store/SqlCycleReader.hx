package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyCycle;
import beadshx.relation.DependencyCycle.buildCycles;
import beadshx.relation.DependencyCycle.canonicalCyclePaths;
import beadshx.relation.RelatedIssue;
import beadshx.store.SqlIssueReader.readIssueInTx;

/**
	Read every dependency cycle in the caller's SQL snapshot, as upstream DetectCycleReportInTx does.

	Only `blocks` and `conditional-blocks` edges from both dependency tables form the
	graph. Each member is looked up in issues first and then in wisps, with its labels.
	Like upstream, any member lookup that fails counts as a member without a record,
	so the report still lists the cycle and marks it partial. The caller owns the
	transaction and connection lifetime.
**/
@:goNative
final class SqlCycleReader {
	public static function readSqlCycles(context:Context, transaction:Tx):StoreResult<Array<DependencyCycle<RelatedIssue>>> {
		final graph = new Map<String, Array<String>>();
		for (table in ["dependencies", "wisp_dependencies"]) {
			final queried = transaction.queryContext(context,
				'SELECT issue_id, COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) AS depends_on_id, type FROM $table');
			if (queried.value2 != null)
				return Failure('dependency graph: query $table: ${queried.value2.toString()}');
			final rows = queried.value1;
			while (rows.next()) {
				final issueId = go.NativePointer.of("");
				final dependsOnId = go.NativePointer.of("");
				final kind = go.NativePointer.of("");
				final scanError = rows.scan(issueId, dependsOnId, kind);
				if (scanError != null) {
					rows.close();
					return Failure('dependency graph: scan $table: ${scanError.toString()}');
				}
				if (kind.get() != "blocks" && kind.get() != "conditional-blocks")
					continue;
				var targets = graph.get(issueId.get());
				if (targets == null) {
					targets = [];
					graph.set(issueId.get(), targets);
				}
				targets.push(dependsOnId.get());
			}
			rows.close();
			final rowError = rows.err();
			if (rowError != null)
				return Failure('dependency graph: rows $table: ${rowError.toString()}');
		}
		return Success(buildCycles(canonicalCyclePaths(graph), id -> readMember(context, transaction, id)));
	}

	/** Upstream ignores the read error here: a failed read and a miss both mean no record. */
	static function readMember(context:Context, transaction:Tx, id:String):Null<RelatedIssue> {
		return switch readIssueInTx(context, transaction, id) {
			case Success(issue): issue;
			case Failure(_): null;
		};
	}
}
