package beadshx.profile;

/** Typed adapter over Go's process-wide CPU, trace, and heap profilers. */
@:goNative
final class GoProfiler implements ProfilePort {
	public function new() {}

	public function startCpu(command:String):Void {
		NativeProfileFacade.startCpu(command);
	}

	public function finish(memProfilePath:String):Void {
		NativeProfileFacade.finish(memProfilePath);
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/profilefacade")
extern class NativeProfileFacade {
	@:go.name("StartCPU") static function startCpu(command:String):Void;
	@:go.name("Finish") static function finish(memProfilePath:String):Void;
}
