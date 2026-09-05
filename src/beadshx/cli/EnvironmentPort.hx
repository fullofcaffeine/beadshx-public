package beadshx.cli;

/** Provides narrowed process environment values to portable CLI policy. */
interface EnvironmentPort {
	function value(name:String):String;
}
