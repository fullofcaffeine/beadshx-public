package beadshx.store;

/** Typed issue kind, with an explicit fallback for future upstream values. */
enum IssueType {
	Epic;
	Bug;
	OtherType(value:String);
}
