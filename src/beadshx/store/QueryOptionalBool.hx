package beadshx.store;

/** Tri-state query filter flag: unspecified, true, or false. */
enum QueryOptionalBool {
	BoolAbsent;
	BoolPresent(value:Bool);
}
