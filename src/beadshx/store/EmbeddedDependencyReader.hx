package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.DB;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.Rows;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.Connector;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;
import beadshx.relation.DependencySnapshot;
import beadshx.relation.RawDependencyEdge;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import haxe.io.Path;

/** Result of one Haxe-owned embedded dependency snapshot. */
enum EmbeddedDependencyResult {
	EmbeddedDependencySnapshot(snapshot:DependencySnapshot);
	EmbeddedDependencyFailure(message:String);
}

/**
	Reads stored dependency facts directly through independent Go APIs.

	What: owns one embedded Dolt connector, SQL transaction, row scan, and cleanup.
	Why: first-party Beads `issueops.EdgeReader` is migration scaffolding, not a
	permanent implementation boundary for the Haxe port.
	How: query issue and wisp presence plus both edge planes inside one transaction,
	copy concrete scalar rows, then roll back so this read can persist no state.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedDependencyReader {
	static final READ_ANCHOR = "SELECT 'present', id, '', '', '', '', '', '', '' FROM issues WHERE id = ? "
		+ "UNION ALL SELECT 'present', id, '', '', '', '', '', '', '' FROM wisps WHERE id = ? "
		+ "UNION ALL SELECT 'edge', COALESCE(id, ''), issue_id, "
		+ "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external), type, "
		+ "COALESCE(CAST(created_at AS CHAR), ''), COALESCE(created_by, ''), COALESCE(metadata, ''), COALESCE(thread_id, '') "
		+ "FROM dependencies WHERE issue_id = ? "
		+ "UNION ALL SELECT 'edge', COALESCE(id, ''), issue_id, "
		+ "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external), type, "
		+ "COALESCE(CAST(created_at AS CHAR), ''), COALESCE(created_by, ''), COALESCE(metadata, ''), COALESCE(thread_id, '') "
		+ "FROM wisp_dependencies WHERE issue_id = ?";

	final beadsDir:String;
	final databaseName:String;

	public function new(beadsDir:String, databaseName:String) {
		this.beadsDir = beadsDir;
		this.databaseName = resolveEmbeddedDatabaseName(beadsDir, databaseName);
	}

	public function read(anchors:Array<String>):EmbeddedDependencyResult {
		if (anchors.length == 0)
			return EmbeddedDependencySnapshot({presentIds: [], edges: []});

		final config = new Config();
		config.directory = Path.join([beadsDir, "embeddeddolt"]);
		config.commitName = "BeadsHX read-only dependency snapshot";
		config.commitEmail = "beadshx-readonly@invalid";
		config.database = databaseName;
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		if (openedConnector.value2 != null)
			return EmbeddedDependencyFailure('open embedded dependency connector: ${openedConnector.value2.toString()}');
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();
		final pingError = database.pingContext(context);
		if (pingError != null)
			return failAfterDatabase('ping embedded dependency database: ${pingError.toString()}', database, connector);

		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null)
			return failAfterDatabase('begin embedded dependency transaction: ${openedTransaction.value2.toString()}', database, connector);
		final transaction = openedTransaction.value1;
		final present = new Map<String, Bool>();
		final edges = new Array<RawDependencyEdge>();
		for (anchor in anchors) {
			final read = readAnchor(context, transaction, anchor, present, edges);
			switch read {
				case EmbeddedDependencyFailure(message):
					return failAfterTransaction(message, transaction, database, connector);
				case EmbeddedDependencySnapshot(_):
			}
		}

		final rollbackError = transaction.rollback();
		if (rollbackError != null)
			return failAfterDatabase('roll back embedded dependency transaction: ${rollbackError.toString()}', database, connector);
		final closeDatabaseError = database.close();
		if (closeDatabaseError != null) {
			connector.close();
			return EmbeddedDependencyFailure('close embedded dependency database: ${closeDatabaseError.toString()}');
		}
		final closeConnectorError = connector.close();
		if (closeConnectorError != null)
			return EmbeddedDependencyFailure('close embedded dependency connector: ${closeConnectorError.toString()}');

		return EmbeddedDependencySnapshot({presentIds: [for (anchor in anchors) if (present.exists(anchor)) anchor], edges: edges});
	}

	function readAnchor(context:Context, transaction:Tx, anchor:String, present:Map<String, Bool>, edges:Array<RawDependencyEdge>):EmbeddedDependencyResult {
		final queried = transaction.queryContext(context, READ_ANCHOR, anchor, anchor, anchor, anchor);
		if (queried.value2 != null)
			return EmbeddedDependencyFailure('read dependency anchor "$anchor": ${queried.value2.toString()}');
		final rows = queried.value1;
		while (rows.next()) {
			final kind = new NullString();
			final id = new NullString();
			final issueId = new NullString();
			final dependsOnId = new NullString();
			final dependencyType = new NullString();
			final createdAt = new NullString();
			final createdBy = new NullString();
			final metadata = new NullString();
			final threadId = new NullString();
			final scanError = rows.scan(kind, id, issueId, dependsOnId, dependencyType, createdAt, createdBy, metadata, threadId);
			if (scanError != null) {
				rows.close();
				return EmbeddedDependencyFailure('scan dependency anchor "$anchor": ${scanError.toString()}');
			}
			if (!kind.valid)
				continue;
			switch kind.string {
				case "present":
					if (id.valid)
						present.set(id.string, true);
				case "edge":
					edges.push({
						id: value(id),
						issueId: value(issueId),
						dependsOnId: value(dependsOnId),
						dependencyType: value(dependencyType),
						createdAt: canonicalStoredTime(value(createdAt)),
						createdBy: value(createdBy),
						metadata: value(metadata),
						threadId: value(threadId)
					});
				case _:
					rows.close();
					return EmbeddedDependencyFailure('read dependency anchor "$anchor": unknown row kind "${kind.string}"');
			}
		}
		final rowError = rows.err();
		if (rowError != null) {
			rows.close();
			return EmbeddedDependencyFailure('finish dependency anchor "$anchor": ${rowError.toString()}');
		}
		final closeError = rows.close();
		if (closeError != null)
			return EmbeddedDependencyFailure('close dependency anchor "$anchor": ${closeError.toString()}');
		return EmbeddedDependencySnapshot({presentIds: [], edges: []});
	}

	static inline function value(field:NullString):String {
		return field.valid ? field.string : "";
	}

	static function canonicalStoredTime(value:String):String {
		if (value.length < 19 || value.charAt(10) != " ")
			return value;
		return value.substr(0, 10) + "T" + value.substr(11) + "Z";
	}

	static function failAfterTransaction(message:String, transaction:Tx, database:DB, connector:Connector):EmbeddedDependencyResult {
		transaction.rollback();
		return failAfterDatabase(message, database, connector);
	}

	static function failAfterDatabase(message:String, database:DB, connector:Connector):EmbeddedDependencyResult {
		database.close();
		connector.close();
		return EmbeddedDependencyFailure(message);
	}
}
