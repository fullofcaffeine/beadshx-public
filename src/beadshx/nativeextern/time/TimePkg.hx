package beadshx.nativeextern.time;

/** Precise package functions used to capture one `now` and build day bounds. */
@:go.import("time")
@:go.package("time")
extern class TimePkg {
	@:go.valueArgs("1")
	@:go.valueReturn
	@:go.name("Date")
	public static function date(year:Int, month:Month, day:Int, hour:Int, minute:Int, second:Int, nanosecond:Int, location:Location):Time;

	@:go.valueReturn
	@:go.name("Now")
	public static function now():Time;

	@:go.tupleReturn
	@:go.tupleValueResults("0")
	@:go.name("Parse")
	public static function parse(layout:String, value:String):ParseTimeResult;

	@:go.tupleReturn
	@:go.tupleValueResults("0")
	@:go.name("ParseDuration")
	public static function parseDuration(value:String):ParseDurationResult;

	/** The duration from now until `value`, negative once it passed. */
	@:go.valueArgs("0")
	@:go.valueReturn
	@:go.name("Until")
	public static function until(value:Time):Duration;
}
