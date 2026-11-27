package beadshx.store;

import beadshx.store.CustomConfig.DatabaseCustomStatuses;
import beadshx.store.CustomConfig.DatabaseCustomTypes;
import beadshx.store.SqlIssueFilter.IssueListConfig;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;

/**
	Upstream workapi.LoadStoreListConfig on an embedded store, in three sessions.

	Why: upstream reads the list configuration with three store calls
	(GetCustomStatusesDetailed, GetCustomTypes and GetInfraTypes), and each call
	opens the store. Dolt warns at each open about every unfinished database
	directory beside the database, so `search --status` and
	`count --include-infra` print those lines once for each call.
	What: SqlIssueFilter.loadListConfig's configuration, each part read in a
	session of its own. Like upstream, a part whose read or session fails falls
	back to the layered lists and the defaults.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedListConfig {
	public static function load(beadsDir:String, databaseName:String, layers:IssueListConfigLayers):IssueListConfig {
		final statuses:DatabaseCustomStatuses = switch EmbeddedSession.withRead(beadsDir, databaseName, SqlCustomConfigReader.readCustomStatuses) {
			case EmbeddedReadFinished(value, cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): NoStoredStatuses;
		};
		final types:DatabaseCustomTypes = switch EmbeddedSession.withRead(beadsDir, databaseName, SqlCustomConfigReader.readCustomTypes) {
			case EmbeddedReadFinished(value, cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): UnreadableTypes;
		};
		final infraTypes = switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlIssueFilter.loadInfraTypes(context, transaction, layers)) {
			case EmbeddedReadFinished(value, cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): SqlIssueFilter.fallbackInfraTypes([], layers);
		};
		return SqlIssueFilter.listConfig(statuses, types, infraTypes, layers);
	}
}
