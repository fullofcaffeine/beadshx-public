package beadshx.store;

/** Successful read-only connectivity timings in milliseconds. */
typedef PingSnapshot = {
	final resolveMs:Int;
	final storeMs:Int;
	final queryMs:Int;
	final totalMs:Int;
}
