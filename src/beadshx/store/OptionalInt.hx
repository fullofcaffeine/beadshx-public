package beadshx.store;

/** Presence-aware integer for pointer-backed native fields where zero is data. */
enum OptionalInt {
	IntAbsent;
	IntPresent(value:Int);
}
