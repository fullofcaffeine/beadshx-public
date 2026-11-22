package beadshx.workspace;

/** The previous native discovery and everything outside the files that it read. */
private typedef PreviousDiscovery = {
	final directory:String;
	final databasePath:String;
	final currentDirectory:String;

	/** Every `key=value` entry of the process environment, sorted. */
	final environment:Array<String>;

	final result:WorkspaceDiscovery;
}

/**
	One command's workspace discovery, which asks the native discovery again
	only when its inputs changed.

	Why: before a command runs, the `.beads/.env` step, the `json` setting and
	the command itself each look up the selected workspace. A native discovery
	runs git and reloads the config, so each repeat costs time and finds the
	same workspace.

	What: a WorkspacePort that gives the previous answer again when a discovery
	repeats the previous one and nothing that discovery reads has changed.

	How: the previous answer is kept with its -C and --db values, the current
	directory and the complete process environment. A discovery with the same
	values gets that answer. Any other discovery asks the native discovery and
	replaces the kept answer. So a variable that `.beads/.env` adds always
	causes a new discovery. The files that discovery reads do not change
	between these lookups: they all happen before the command reads the store,
	and no command in this build writes them.
**/
@:goNative
final class InvocationWorkspace implements WorkspacePort {
	final native:WorkspacePort;
	var previous:Null<PreviousDiscovery> = null;

	public function new(native:WorkspacePort) {
		this.native = native;
	}

	public function discover(directory:String, databasePath:String):WorkspaceDiscovery {
		final currentDirectory = Sys.getCwd();
		final environment = environmentEntries();
		final last = previous;
		if (last != null
			&& last.directory == directory
			&& last.databasePath == databasePath
			&& last.currentDirectory == currentDirectory
			&& sameEnvironment(last.environment, environment))
			return last.result;
		final result = native.discover(directory, databasePath);
		previous = {
			directory: directory,
			databasePath: databasePath,
			currentDirectory: currentDirectory,
			environment: environment,
			result: result
		};
		return result;
	}
}

/**
	The process environment as sorted `key=value` entries, so that only the
	variables and their values count, not the order in which they are kept.
**/
private function environmentEntries():Array<String> {
	final entries = [for (key => value in Sys.environment()) '$key=$value'];
	entries.sort((first, second) -> first < second ? -1 : (first > second ? 1 : 0));
	return entries;
}

/** Whether two sorted environments have the same entries. */
private function sameEnvironment(first:Array<String>, second:Array<String>):Bool {
	if (first.length != second.length)
		return false;
	for (index in 0...first.length)
		if (first[index] != second[index])
			return false;
	return true;
}
