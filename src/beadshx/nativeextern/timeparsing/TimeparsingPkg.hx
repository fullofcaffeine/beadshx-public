package beadshx.nativeextern.timeparsing;

import beadshx.nativeextern.time.Time;

/** Exact generated signatures for the exported Beads time parsers. */
@:go.import("github.com/steveyegge/beads/internal/timeparsing")
@:go.package("timeparsing")
extern class TimeparsingPkg {
	@:go.tupleReturn
	@:go.valueArgs("1")
	@:go.tupleValueResults("0")
	@:go.name("ParseCompactDuration")
	public static function parseCompactDuration(value:String, now:Time):ParseCompactDurationResult;

	@:go.tupleReturn
	@:go.valueArgs("1")
	@:go.tupleValueResults("0")
	@:go.name("ParseRelativeTime")
	public static function parseRelativeTime(value:String, now:Time):ParseRelativeTimeResult;
}
