import beadshx.cli.DepListSelection;
import beadshx.cli.DepListSelection.selectDepList;

/** Independent expectations from the pinned dep list command's public dispatch. */
class Main {
	static function main():Void {
		for (direction in ["", "down"])
			for (count in [2, 3])
				switch selectDepList(direction, count) {
					case BatchEdges:
					case _:
						throw "default/down batches must retain raw edge shape";
				}
		for (count in [1, 2, 3]) {
			switch selectDepList("up", count) {
				case RelatedIssues(Incoming):
				case _:
					throw "up always returns incoming neighboring issues";
			}
			for (direction in ["sideways", "UP", "both", " down"])
				switch selectDepList(direction, count) {
					case RelatedIssues(Outgoing):
					case _:
						throw "unknown directions retain upstream outgoing issue shape";
				}
		}
		for (direction in ["", "down"])
			switch selectDepList(direction, 1) {
				case RelatedIssues(Outgoing):
				case _:
					throw "single down anchor returns neighboring issues";
			}
		Sys.println("dependency CLI selection contracts: PASS");
	}
}
