package beadshx.config;

import beadshx.cli.JsonSettingPort;
import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.workspace.WorkspacePort;

/**
	Upstream's `json` setting, read from the config of the workspace that the
	command selects.

	Why: upstream's pre-run sets its JSON switch from config.GetBool("json")
	unless --json or the root --format was given, and sets it again from the
	config it reloads for the selected workspace, before any command prints.
	What: Viper's boolean of BD_JSON, config.local.yaml, config.yaml and the user
	config.yaml, from the config of the workspace that upstream's setups bind
	last before they reread the setting (see WorkspaceEnvironment.settingsBeadsDir),
	or from the process-start config when no workspace is found. How: LayeredConfig loads the same layers in the
	same order. Viper reads BD_JSON as strconv.ParseBool does and treats an empty
	value as unset.
**/
final class LayeredJsonSetting implements JsonSettingPort {
	final workspace:WorkspacePort;

	public function new(workspace:WorkspacePort) {
		this.workspace = workspace;
	}

	public function enabled(selection:WorkspaceSelection, use:DatabaseVariableUse):Bool {
		final config = switch workspace.discover(selection.directory, selection.databasePath) {
			case Found(location): LayeredConfig.forWorkspace(WorkspaceEnvironment.settingsBeadsDir(selection, use, location));
			// An invalid selection fails before any output, so its config never matters.
			case NotFound | InvalidSelection(_): LayeredConfig.atStartup();
		};
		return config.getBool("json");
	}
}
