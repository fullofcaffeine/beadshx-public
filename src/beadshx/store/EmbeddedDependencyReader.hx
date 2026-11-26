package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencySnapshot;
import beadshx.relation.RawDependencyEdge;
import beadshx.store.DatabaseErrors.isTableNotExist;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/** Result of one Haxe-owned embedded dependency snapshot. */
enum EmbeddedDependencyResult {
	EmbeddedDependencySnapshot(snapshot:DependencySnapshot);
	EmbeddedDependencyFailure(message:String);
}

/**
	Reads stored dependency facts directly through independent Go APIs.

	What: owns one read transaction of the shared `EmbeddedSession`, and the row scans.
	Why: first-party Beads `issueops.EdgeReader` is migration scaffolding, not a
	permanent implementation boundary for the Haxe port. A failed read must say
	what upstream's says, and Dolt words a failed query after its SQL, so each
	query is upstream's query.
	How: upstream ExecuteEdgeRead (internal/storage/issueops/edges.go) in one
	transaction: PresentIssueOrWispIDsInTx ("check issue existence in <table>: ")
	over the issues and then the wisps table, in batches, where a missing table
	has no IDs; then GetDependencyRecordsForIssuesInTx: the wisp partition
	("partition wisp ids: ") and the rows of the wisps from wisp_dependencies,
	then of the other IDs from dependencies ("get dependency records from
	<table>: "). The read is rolled back, so it can persist no state.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedDependencyReader {
	/** Upstream queryBatchSize. */
	static inline final BATCH_SIZE = 200;

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(anchors:Array<String>):EmbeddedDependencyResult {
		if (anchors.length == 0)
			return EmbeddedDependencySnapshot({presentIds: [], edges: []});

		final read = EmbeddedSession.withRead(beadsDir, databaseName, (context, transaction) -> readAnchors(context, transaction, anchors));
		// A failed anchor read comes first; each failed release step follows it, as upstream withConn joins them.
		return switch EmbeddedReadWording.forNoun("dependency", true).joinedResult(read) {
			case Failure(message): EmbeddedDependencyFailure(message);
			case Success(snapshot): EmbeddedDependencySnapshot(snapshot);
		};
	}

	function readAnchors(context:Context, transaction:Tx, anchors:Array<String>):StoreResult<DependencySnapshot> {
		final present = switch presentIds(context, transaction, anchors) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final wisps = switch SqlExportReader.partitionWispIds(context, transaction, anchors) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final edges = new Array<RawDependencyEdge>();
		for (plane in [
			{table: "wisp_dependencies", ids: [for (anchor in anchors) if (wisps.exists(anchor)) anchor]},
			{table: "dependencies", ids: [for (anchor in anchors) if (!wisps.exists(anchor)) anchor]}
		]) {
			var start = 0;
			while (start < plane.ids.length) {
				final batch = plane.ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				switch SqlGraphReader.readDependencyBatch(context, transaction, plane.table, batch) {
					case Failure(message):
						return Failure(message);
					case Success(rows):
						for (row in rows)
							edges.push({
								// The source-keyed read does not select the row's own key.
								id: "",
								issueId: row.issueId,
								dependsOnId: row.dependsOnId,
								dependencyType: row.type,
								createdAt: row.createdAt,
								createdBy: row.createdBy,
								metadata: row.metadata,
								threadId: row.threadId
							});
				}
			}
		}
		return Success({presentIds: [for (anchor in anchors) if (present.exists(anchor)) anchor], edges: edges});
	}

	/** Upstream PresentIssueOrWispIDsInTx: the anchors that either table holds. */
	static function presentIds(context:Context, transaction:Tx, ids:Array<String>):StoreResult<Map<String, Bool>> {
		final present = new Map<String, Bool>();
		for (table in ["issues", "wisps"]) {
			var start = 0;
			while (start < ids.length) {
				final batch = ids.slice(start, start + BATCH_SIZE);
				start += BATCH_SIZE;
				final arguments:Array<Dynamic> = [for (id in batch) id];
				final queried = transaction.queryNativeContext(context, 'SELECT id FROM $table WHERE id IN (${[for (_ in batch) "?"].join(",")})',
					...arguments);
				if (queried.error != null) {
					// An older schema has no wisps table: none of the IDs is a wisp.
					if (isTableNotExist(queried.error))
						break;
					return Failure('check issue existence in $table: ${queried.error.text()}');
				}
				final rows = queried.rows;
				while (rows.next()) {
					final id = go.NativePointer.of("");
					final scanError = rows.scanNative(id);
					if (scanError != null) {
						rows.closeNative();
						return Failure('check issue existence in $table: scan: ${scanError.text()}');
					}
					present.set(id.get(), true);
				}
				rows.closeNative();
				final rowError = rows.errNative();
				if (rowError != null)
					return Failure('check issue existence in $table: rows: ${rowError.text()}');
			}
		}
		return Success(present);
	}
}
