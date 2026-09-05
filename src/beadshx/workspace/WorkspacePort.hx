package beadshx.workspace;

/** Behavior-oriented boundary for workspace discovery. */
interface WorkspacePort {
	function discover(directory:String, databasePath:String):WorkspaceDiscovery;
}
