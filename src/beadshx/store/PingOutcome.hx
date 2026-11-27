package beadshx.store;

/** How ping's own body ended, after the store opened. */
enum PingOutcome {
	/** The query answered. */
	PingAnswered(snapshot:PingSnapshot);

	/**
		Upstream pingFail (cmd/bd/ping.go:88-101): the reason, such as
		`query failed: <error>`, and the milliseconds from the start of the
		command body to the failure.
	**/
	PingFailed(reason:String, totalMs:Int);
}
