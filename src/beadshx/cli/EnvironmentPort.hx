package beadshx.cli;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;

/** Provides narrowed process environment values to portable CLI policy. */
interface EnvironmentPort {
	function value(name:String):String;

	/**
		Adds the variables of the selected workspace's `.beads/.env`, as upstream's
		pre-run does before it reads the JSON switch or any other setting.
	**/
	function selectWorkspace(selection:WorkspaceSelection):Void;
}
