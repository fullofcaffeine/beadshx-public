package beadshx.store;

/** Exact native time facts used by Haxe-owned query comparisons. */
typedef QueryInstant = {
	final canonical:String;
	final epochSeconds:String;
	final nanosecond:Int;
	final year:Int;
	final month:Int;
	final day:Int;
}
