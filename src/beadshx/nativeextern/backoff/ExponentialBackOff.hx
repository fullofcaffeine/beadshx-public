package beadshx.nativeextern.backoff;

import beadshx.nativeextern.time.Duration;

/**
	What: the two `backoff.ExponentialBackOff` fields that upstream's embedded
	store open sets.
	Why: the embedded Dolt driver retries a locked database with this
	independent library's policy; upstream `embeddeddolt.OpenSQL` sets it.
	How: start from `BackoffPkg.newExponentialBackOff()`, which fills the
	library defaults. Each field is a `time.Duration` stored by value.
**/
@:go.import("github.com/cenkalti/backoff/v4")
@:go.package("backoff")
@:go.name("ExponentialBackOff")
@:go.struct
@:goNative
extern class ExponentialBackOff {
	/** The longest wait between two attempts. */
	@:go.name("MaxInterval")
	@:go.valueField
	public var maxInterval:Duration;

	/** The total time to retry; zero retries until the context ends. */
	@:go.name("MaxElapsedTime")
	@:go.valueField
	public var maxElapsedTime:Duration;
}
