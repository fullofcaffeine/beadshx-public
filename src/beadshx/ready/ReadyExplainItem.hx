package beadshx.ready;

import beadshx.store.IssueListItem;

/** One ready issue plus Haxe-owned dependency reasoning. */
typedef ReadyExplainItem = {
	final issue:IssueListItem;
	final reason:String;
	final resolvedBlockers:Null<Array<String>>;
	final dependencyCount:Int;
	final dependentCount:Int;
	final ?parent:String;
}
