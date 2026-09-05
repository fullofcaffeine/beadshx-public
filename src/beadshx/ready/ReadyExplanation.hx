package beadshx.ready;

/** Complete dependency-aware explanation for the workspace's ready state. */
typedef ReadyExplanation = {
	final ready:Array<ReadyExplainItem>;
	final blocked:Array<BlockedExplainItem>;
	final cycles:Array<Array<String>>;
}
