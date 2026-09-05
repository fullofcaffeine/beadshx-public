package beadshx.store;

/** Typed filters for issues whose last update is older than a day threshold. */
typedef StaleRequest = {
	final days:Int;
	final status:String;
	final limit:Int;
}
