import beadshx.store.EmbeddedRelationReader;
import beadshx.relation.RelationRead.prepareRelationRead;

/** Full lifecycle and record projection over an upstream-created disposable fixture. */
@:goNative
class Main {
	static function main():Void {
		final args = Sys.args();
		if (args.length != 1)
			throw "usage: relation-storage-tracer <disposable-workspace>";
		if (!sys.FileSystem.exists(args[0] + "/.beadshx-disposable-fixture"))
			throw "relation storage tracer requires a disposable fixture";
		final plan = switch prepareRelationRead("rel-target", "in", []) {
			case RelationPlanInvalid(message): throw message;
			case RelationPlanReady(value): value;
		};
		switch EmbeddedRelationReader.read(args[0] + "/.beads", "", plan) {
			case Failure(message):
				Sys.println(message);
				throw "relation read failed";
			case Success(rows):
				if (rows.length != 1)
					throw 'expected one incoming relation, got ${rows.length}';
				final row = rows[0];
				if (row.id != "rel-dependent" || row.title != "Dependent" || row.dependencyType != "blocks")
					throw "incoming relation identity, title, or edge type differs";
				if (row.labels.join(",") != "fixture-label")
					throw "incoming relation lost labels";
				if (row.longFields.isBlocked)
					throw "relation unexpectedly hydrated the derived blocked annotation";
				if (row.description != "Relation description" || row.longFields.awaitType != "" || row.longFields.awaitId != "fixture-run")
					throw "incoming relation lost content or gate fields";
		}
		Sys.println("Haxe SQL incoming relation: PASS");
	}
}
