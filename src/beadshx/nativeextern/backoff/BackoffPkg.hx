package beadshx.nativeextern.backoff;

/** Package constructor of the independent `cenkalti/backoff/v4` retry policy. */
@:go.import("github.com/cenkalti/backoff/v4")
@:go.package("backoff")
@:goNative
extern class BackoffPkg {
	/** `backoff.NewExponentialBackOff()` with the library's default options. */
	@:go.name("NewExponentialBackOff")
	public static function newExponentialBackOff():ExponentialBackOff;
}
