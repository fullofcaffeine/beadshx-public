package beadshx.nativeextern.time;

/** Precise subset of Go `time.Time` used by query normalization. */
@:go.import("time")
@:go.package("time")
@:go.name("Time")
@:go.struct
extern class Time {
	/** Allocate an addressable zero time for standard-library scan destinations. */
	public function new();

	@:go.valueArgs("0")
	@:go.valueReturn
	@:go.name("Add")
	public function add(duration:Duration):Time;

	@:go.name("Day") public function day():Int;
	@:go.name("Format") public function format(layout:String):String;

	/** Whether this is Go's zero time, January 1, year 1, 00:00:00 UTC. */
	@:go.name("IsZero") public function isZero():Bool;

	@:go.name("Location") public function location():Location;
	@:go.valueReturn
	@:go.name("Month") public function month():Month;
	@:go.name("Nanosecond") public function nanosecond():Int;

	/** Go's default text for a time, which `fmt` prints: `2006-01-02 15:04:05.999999999 -0700 MST`. */
	@:go.name("String") public function stringValue():String;

	@:go.name("Unix") public function unix():Int;
	@:go.valueReturn
	@:go.name("UTC") public function utc():Time;
	@:go.name("Year") public function year():Int;
}
