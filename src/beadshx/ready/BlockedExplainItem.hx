package beadshx.ready;

import beadshx.store.IssueListItem;

/** One blocked issue plus the current blocker records known to the workspace. */
typedef BlockedExplainItem = {
	final issue:IssueListItem;
	final blockedBy:Array<ReadyBlockerInfo>;
	final blockedByCount:Int;
}
