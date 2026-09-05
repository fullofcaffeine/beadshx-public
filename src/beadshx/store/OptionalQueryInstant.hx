package beadshx.store;

/** Presence-aware instant for nullable native issue timestamps. */
enum OptionalQueryInstant {
	InstantAbsent;
	InstantPresent(value:QueryInstant);
}
