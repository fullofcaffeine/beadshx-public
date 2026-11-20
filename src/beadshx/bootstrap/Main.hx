package beadshx.bootstrap;

import beadshx.store.EmbeddedCgoStore;
import beadshx.bootstrap.CommandProcess.commandApplication;
import beadshx.cli.SystemOutput;
import beadshx.workspace.GoWorkspace;

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
		Sys.exit(commandApplication(new GoWorkspace(), new SystemOutput()).run(Sys.args()));
	}
}
