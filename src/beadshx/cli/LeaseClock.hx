package beadshx.cli;

import beadshx.nativeextern.time.TimePkg;

/**
	Reads the system clock for show's `Lease:` line with Go's time package, as
	upstream's formatTimeUntil and formatTimeAgo do (cmd/bd/wisp.go:547-606).
**/
@:goNative
final class LeaseClock {
	/** Go's time.RFC3339Nano layout, in which the readers keep issue times. */
	static inline final RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";

	/**
		The seconds from now until an RFC 3339 instant, negative once it passed,
		as Go's time.Until measures them; null when the instant does not parse.
	**/
	public static function secondsFromNow(instant:String):Null<Float> {
		final parsed = TimePkg.parse(RFC3339_NANO, instant);
		if (parsed.value2 != null)
			return null;
		return TimePkg.until(parsed.value1).seconds();
	}
}
