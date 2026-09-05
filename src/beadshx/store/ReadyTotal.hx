package beadshx.store;

/** A truncated ready page can survive a best-effort total-count failure. */
enum ReadyTotal {
	TotalUnknown;
	TotalKnown(value:JsonInteger);
}
