package beadshx.query;

/** Parsed CLI choices for one Haxe-owned structured query invocation. */
typedef QueryCommandRequest = {
	final expression:String;
	final provided:Bool;
	final includeClosed:Bool;
	final sortBy:String;
	final reverse:Bool;
	final limit:Int;
	final offset:Int;
	final longFormat:Bool;
	final parseOnly:Bool;
}
