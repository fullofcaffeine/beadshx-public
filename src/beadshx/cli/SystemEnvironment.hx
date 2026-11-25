package beadshx.cli;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.DatabaseVariableSelection;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.config.WorkspaceEnvironment;
import beadshx.workspace.RedirectLookups;
import beadshx.workspace.WorkspacePort;

/** Owns host process environment access for Haxe-authored command policy. */
@:goNative
final class SystemEnvironment implements EnvironmentPort {
	final workspace:WorkspacePort;

	/** The command's redirect lookups, which upstream's -C and `.env` steps run first; null runs none. */
	final lookups:Null<RedirectLookups>;

	public function new(workspace:WorkspacePort, ?lookups:RedirectLookups) {
		this.workspace = workspace;
		this.lookups = lookups;
	}

	public function value(name:String):String {
		final found = Sys.getEnv(name);
		return found == null ? "" : found;
	}

	public function selectWorkspace(selection:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection {
		return WorkspaceEnvironment.load(workspace, selection, use, lookups);
	}
}
