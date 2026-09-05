package beadshx.cli;

/** Owns host process environment access for Haxe-authored command policy. */
@:goNative
final class SystemEnvironment implements EnvironmentPort {
	public function new() {}

	public function value(name:String):String {
		final found = Sys.getEnv(name);
		return found == null ? "" : found;
	}
}
