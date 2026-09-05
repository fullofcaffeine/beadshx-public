package beadshx.cli;

/** Stable public output modes accepted by the read-only CLI. */
enum abstract OutputMode(String) {
	final Human = "human";
	final Json = "json";
}
