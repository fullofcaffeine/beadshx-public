package beadshx.store;

/** One display-keyed bucket returned by a grouped count. */
typedef CountBucket = {
	final group:String;
	final count:JsonInteger;
}
