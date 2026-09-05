package beadshx.store;

/** Workspace statistics with explicit availability for skipped counts. */
typedef StatusSnapshot = {
	final totalIssues:Int;
	final openIssues:Int;
	final inProgressIssues:Int;
	final closedIssues:Int;
	final blockedIssues:Int;
	final blockedAvailable:Bool;
	final deferredIssues:Int;
	final readyIssues:Int;
	final readyAvailable:Bool;
	final pinnedIssues:Int;
	final epicsEligibleForClosure:Int;
	final averageLeadTime:Float;
}
