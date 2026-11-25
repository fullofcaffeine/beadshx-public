package beadshx.cli;

import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;

/** The workspace selectors a command typed, which choose the config that the `json` setting comes from. */
typedef WorkspaceSelection = {
	/** The -C directory as typed; it can be empty. */
	final directory:String;

	/** The --db value as typed; it can be empty. */
	final databasePath:String;
}

/**
	Reads upstream's `json` setting, which turns on JSON output for every command
	when neither --json nor the root --format decides the output mode. `use`
	tells `where`, `version` and help pages from commands that open a store,
	which reread the setting after they bind their database.
**/
interface JsonSettingPort {
	function enabled(selection:WorkspaceSelection, use:DatabaseVariableUse):Bool;
}
