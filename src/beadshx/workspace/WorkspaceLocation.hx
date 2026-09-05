package beadshx.workspace;

/** Concrete paths and identity reported for one discovered Beads workspace. */
typedef WorkspaceLocation = {
	final path:String;
	final redirectedFrom:String;
	final prefix:String;
	final databasePath:String;
	final databaseName:String;
	final databaseMissing:Bool;
	final proxiedServer:Bool;
	final listLimitConfigured:Bool;
	final listLimit:Int;
}
