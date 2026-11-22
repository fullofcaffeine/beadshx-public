package beadshx.workspace;

/** Concrete paths and identity reported for one discovered Beads workspace. */
typedef WorkspaceLocation = {
	final path:String;
	final redirectedFrom:String;

	/**
		The workspace config.yaml's `issue-prefix`, or else its `issue_prefix`,
		as upstream config.GetStringFromDir reads them. Discovery opens no
		database, so this is never the stored `issue_prefix`; the commands that
		need that read it themselves.
	**/
	final yamlPrefix:String;

	final databasePath:String;
	final databaseName:String;
	final databaseMissing:Bool;
	final proxiedServer:Bool;
	final listLimitConfigured:Bool;
	final listLimit:Int;
}
