package beadshx.config;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspacePort;

/**
	Upstream's `.beads/.env` loading in the root pre-run.

	Why: upstream reads every BD_ and BEADS_ setting from the process
	environment, and its pre-run first copies the selected workspace's
	`.beads/.env` there, so a variable in that file acts as if it were
	exported, unless the real environment already has it. What: two steps
	that change the process environment the way upstream does, before any
	setting is read. How: first, when neither -C nor a set BEADS_DIR, BEADS_DB
	or BD_DB chooses the workspace, the .env file of the workspace found from
	the current directory may set those three selectors (upstream
	loadSelectionEnvironment). Then every variable of the selected workspace's
	.env file that the environment does not have is set (upstream
	loadBeadsEnvFile under prepareSelectedCommandContext). Upstream sets
	BEADS_DIR to the selected directory before that second step, so the file
	cannot set BEADS_DIR there and `$BEADS_DIR` expands to that directory.
	Nothing is printed: a missing, unreadable or rejected file adds nothing.
**/
@:goNative
final class WorkspaceEnvironment {
	/** Whether the first step set BEADS_DIR, which was then unset or empty for upstream's process-start config. */
	static var callerBeadsDirReplaced = false;

	/** Loads the `.env` variables for one command's -C and --db selection. */
	public static function load(workspace:WorkspacePort, selection:WorkspaceSelection):Void {
		var selected:Null<WorkspaceDiscovery> = null;
		// -C sets BEADS_DIR before upstream's first step, which then does nothing.
		if (goTrimSpace(selection.directory) == ""
			&& environmentValue("BEADS_DIR") == ""
			&& environmentValue("BEADS_DB") == ""
			&& environmentValue("BD_DB") == "") {
			final found = workspace.discover("", "");
			var changed = false;
			switch found {
				case Found(location):
					final variables = DotEnv.read(FilepathPkg.join(location.path, ".env"), name -> Sys.getEnv(name));
					if (variables != null)
						for (name in ["BEADS_DIR", "BEADS_DB", "BD_DB"]) {
							final assigned = variables.get(name);
							if (environmentValue(name) != "" || assigned == null || goTrimSpace(assigned) == "")
								continue;
							Sys.putEnv(name, assigned);
							changed = true;
							if (name == "BEADS_DIR")
								callerBeadsDirReplaced = true;
						}
				case NotFound | InvalidSelection(_):
			}
			// Without a new selector or --db, the selection is the workspace just found.
			if (!changed && selection.databasePath == "")
				selected = found;
		}
		if (selected == null)
			selected = workspace.discover(selection.directory, selection.databasePath);
		switch selected {
			case Found(location):
				loadFile(location.path);
			case NotFound | InvalidSelection(_):
		}
	}

	/**
		BEADS_DIR as upstream's process-start config saw it: "" when the first
		step set it, since that step runs only when BEADS_DIR is unset or empty.
	**/
	public static function callerBeadsDir():Null<String> {
		return callerBeadsDirReplaced ? "" : Sys.getEnv("BEADS_DIR");
	}

	/** Upstream loadBeadsEnvFile with BEADS_DIR set to `beadsDir`: gotenv.Load after an os.Stat check. */
	static function loadFile(beadsDir:String):Void {
		final path = FilepathPkg.join(beadsDir, ".env");
		if (OsPkg.stat(path).value2 != null)
			return;
		final variables = DotEnv.read(path, name -> name == "BEADS_DIR" ? beadsDir : Sys.getEnv(name));
		if (variables == null)
			return;
		for (name in variables.keys())
			if (name != "BEADS_DIR" && Sys.getEnv(name) == null)
				Sys.putEnv(name, variables.get(name));
	}
}
