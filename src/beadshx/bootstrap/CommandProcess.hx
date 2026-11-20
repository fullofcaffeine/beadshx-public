package beadshx.bootstrap;

import beadshx.cli.Application;
import beadshx.cli.OutputPort;
import beadshx.cli.Parser;
import beadshx.cli.SystemEnvironment;
import beadshx.cli.SystemWatch;
import beadshx.config.LayeredJsonSetting;
import beadshx.git.GoGitHistory;
import beadshx.identity.SystemActor;
import beadshx.profile.GoProfiler;
import beadshx.store.GoReadonlyStore;
import beadshx.workspace.InvocationWorkspace;
import beadshx.workspace.WorkspacePort;

/**
	Builds the application that runs one `bd` process's command.

	Why: the `.beads/.env` step, the `json` setting and the command each look up
	the selected workspace, so they must share one InvocationWorkspace. A
	contract builds this same graph around a discovery that counts its calls.
	What: the parser, its ports and the application over the given native
	workspace discovery and output. How: one InvocationWorkspace wraps the
	discovery and serves the parser's environment, its JSON setting and the
	application.
**/
function commandApplication(discovery:WorkspacePort, output:OutputPort):Application {
	final workspace = new InvocationWorkspace(discovery);
	final parser = new Parser(new SystemEnvironment(workspace), new LayeredJsonSetting(workspace));
	return new Application(parser, output, new SystemActor(), new GoGitHistory(), workspace, new GoReadonlyStore(), new GoProfiler(), new SystemWatch());
}
