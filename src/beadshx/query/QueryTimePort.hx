package beadshx.query;

import beadshx.store.QueryInstant;

/** One syntax literal that requires native time normalization. */
typedef QueryTimeInput = {
	final value:String;
	final durationAgo:Bool;
}

/** Native time mechanics returned for one input, all from one captured now. */
typedef QueryNormalizedTime = {
	final target:QueryInstant;
	final dayStart:QueryInstant;
	final nextDay:QueryInstant;
	final endOfDay:QueryInstant;
}

/** One ordered time-normalization result. */
enum QueryTimeOutcome {
	TimeNormalized(value:QueryNormalizedTime);
	TimeInvalid(message:String);
}

/** Narrow native time mechanism; field and operator policy remain in Haxe. */
interface QueryTimePort {
	function normalize(inputs:Array<QueryTimeInput>):Array<QueryTimeOutcome>;
}
