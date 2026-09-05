package beadshx.nativeextern.time;

/** Precise subset of Go `time.Time` used by query normalization. */
@:go.import("time")
@:go.package("time")
@:go.name("Time")
@:go.struct
extern class Time {
	@:go.valueArgs("0")
	@:go.valueReturn
	@:go.name("Add")
	public function add(duration:Duration):Time;

	@:go.name("Day") public function day():Int;
	@:go.name("Format") public function format(layout:String):String;
	@:go.name("Location") public function location():Location;
	@:go.valueReturn
	@:go.name("Month") public function month():Month;
	@:go.name("Nanosecond") public function nanosecond():Int;
	@:go.name("Unix") public function unix():Int;
	@:go.name("Year") public function year():Int;
}
