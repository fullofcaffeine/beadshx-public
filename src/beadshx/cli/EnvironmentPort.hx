package beadshx.cli;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.DatabaseVariableSelection;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;

/** Provides narrowed process environment values to portable CLI policy. */
interface EnvironmentPort {
	function value(name:String):String;

	/**
		Adds the variables of the selected workspace's `.beads/.env`, as upstream's
		pre-run does before it reads the JSON switch or any other setting, and
		returns what BEADS_DB or BD_DB selects for a command with this `use`.
	**/
	function selectWorkspace(selection:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection;
}
