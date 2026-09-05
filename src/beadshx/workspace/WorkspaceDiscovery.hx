package beadshx.workspace;

/** Workspace discovery is explicit and distinguishes absence from a valid path. */
enum WorkspaceDiscovery {
	Found(location:WorkspaceLocation);
	NotFound;
	InvalidSelection(message:String);
}
