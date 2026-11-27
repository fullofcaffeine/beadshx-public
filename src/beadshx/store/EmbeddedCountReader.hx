package beadshx.store;

import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;

/**
	Own the store opens and read transactions of `bd count`; the count semantics are authored Haxe.

	What: upstream's pre-run store open, then the store calls of its
	storeCounter. A request that counts the wisps tier (--include-infra) first
	loads the list configuration (LoadStoreListConfig: the custom statuses,
	the custom types and the infra types, of which the count reads only the
	infra types). Then the scalar total, or for a grouped count the buckets
	and then the total, which is the scalar count and not the sum of the
	buckets, as label buckets overlap.
	How: one embedded session for each store call, as upstream opens the
	store again for each one; the first open checks the schema. Like
	upstream, a configuration read that fails falls back to the layered
	lists and the defaults.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCountReader {
	static final WORDING = EmbeddedReadWording.forNoun("count", false);

	public static function read(beadsDir:String, databaseName:String, request:CountRequest, group:CountGroup,
			layers:IssueListConfigLayers):StoreResult<CountResult> {
		EmbeddedSession.openForCommand(beadsDir, databaseName);
		// LoadStoreListConfig's three store calls, of which the count reads only the infra types.
		final infraTypes = request.includeInfra ? EmbeddedListConfig.load(beadsDir, databaseName, layers).infraTypes : [];
		final filter = switch SqlIssueCountReader.buildCountFilter(request, infraTypes) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		final buckets = new Array<CountBucket>();
		if (!group.match(Ungrouped)) {
			final counts = switch WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName,
				(context, transaction) -> SqlIssueCountReader.countIssuesByGroup(context, transaction, filter, group))) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final keys = counts.keys.copy();
			keys.sort(compareUtf8);
			for (key in keys)
				buckets.push({group: key, count: NativeIntegers.fromInt(counts.count(key))});
		}
		return switch WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlIssueCountReader.countIssues(context, transaction, filter))) {
			case Failure(message): Failure(message);
			case Success(total): Success({total: NativeIntegers.fromInt(total), groups: buckets});
		};
	}
}
