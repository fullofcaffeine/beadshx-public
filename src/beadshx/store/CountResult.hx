package beadshx.store;

/** Exact scalar total plus optional, stably ordered buckets. */
typedef CountResult = {
	final total:JsonInteger;
	final groups:Array<CountBucket>;
}
