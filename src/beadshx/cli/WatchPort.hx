package beadshx.cli;

/** Narrow timer and process-signal lifecycle used by polling read commands. */
interface WatchPort {
	function start():Void;
	function waitForStop():Bool;
	function close():Void;
}
