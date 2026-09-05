package beadshx.profile;

/** Process-profiler lifecycle used only when the caller explicitly opts in. */
interface ProfilePort {
	function startCpu(command:String):Void;
	function finish(memProfilePath:String):Void;
}
