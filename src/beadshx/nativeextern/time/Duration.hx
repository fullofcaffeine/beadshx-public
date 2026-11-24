package beadshx.nativeextern.time;

/** Opaque native duration preserved across `time` calls. */
@:go.import("time")
@:go.package("time")
@:go.name("Duration")
@:go.valueType
extern class Duration {
	@:go.name("String")
	public function toString():String;

	/** The duration as a floating-point number of seconds, negative for a negative duration. */
	@:go.name("Seconds")
	public function seconds():Float;
}
