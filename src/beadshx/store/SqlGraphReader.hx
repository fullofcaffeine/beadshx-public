package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.relation.DependencyCycle.walkBlockingCycles;
import beadshx.store.SqlCycleReader.readBlockingGraph;
import beadshx.store.SqlIssueReader.readIssueInTx;

/**
	Reads what `bd graph check` needs in the caller's SQL snapshot.

	The caller owns the transaction and connection lifetime.
**/
@:goNative
final class SqlGraphReader {
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
}
