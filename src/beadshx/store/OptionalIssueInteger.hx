package beadshx.store;

/** SQL integer presence, preserving native signed width independently of pagination. */
enum OptionalIssueInteger {
	IntegerAbsent;
	IntegerPresent(value:JsonInteger);
}
