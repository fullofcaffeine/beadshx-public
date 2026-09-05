package beadshx.bootstrap;

import beadshx.store.EmbeddedCgoStore;
import beadshx.cli.Application;
import beadshx.cli.Parser;
import beadshx.cli.SystemEnvironment;
import beadshx.cli.SystemOutput;
import beadshx.cli.SystemWatch;
import beadshx.identity.SystemActor;
import beadshx.git.GoGitHistory;
import beadshx.store.GoReadonlyStore;
import beadshx.workspace.GoWorkspace;
import beadshx.profile.GoProfiler;

/**
 * Starts the Haxe-authored BeadsHX development binary.
 *
 * Why: command behavior needs one honest product-owned process boundary before
 * any task operation is ported. What: it reports the BeadsHX build identity and
 * exact upstream compatibility target. How: haxe.go lowers this entry point
 * into the existing caller-owned Go module without touching task state.
 */
@:goNative
class Main {
	static function main():Void {
		final application = new Application(new Parser(new SystemEnvironment()), new SystemOutput(), new SystemActor(), new GoGitHistory(), new GoWorkspace(),
			new GoReadonlyStore(), new GoProfiler(), new SystemWatch());
		Sys.exit(application.run(Sys.args()));
	}
}
