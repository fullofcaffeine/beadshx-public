package beadshx.ready;

import beadshx.relation.RelatedIssue;

/** One blocked issue plus the current blocker records known to the workspace. */
typedef BlockedExplainItem = {
	final issue:RelatedIssue;
	final blockedBy:Array<ReadyBlockerInfo>;
	final blockedByCount:Int;
}
