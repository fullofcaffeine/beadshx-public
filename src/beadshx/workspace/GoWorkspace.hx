package beadshx.workspace;

import go.Result;

/**
	Typed binding to Beads' canonical workspace discovery.

	The Go package remains the authority for Git worktrees, redirects, and
	BEADS_DIR resolution. This adapter immediately narrows its empty-string
	sentinel into a Haxe enum before command logic sees it.
**/
@:goNative
final class GoWorkspace implements WorkspacePort {
	public function new() {}

	public function discover(directory:String, databasePath:String):WorkspaceDiscovery {
		final result = NativeWorkspaceFacade.discoverFrom(directory, databasePath);
		if (result.isErr()) {
			final message = result.error();
			return InvalidSelection(message == null ? "workspace selection failed" : message);
		}
		final native = result.unwrap();
		final path = native.path();
		if (path == "")
			return NotFound;
		return Found({
			path: path,
			redirectedFrom: native.redirectedFrom(),
			prefix: native.prefix(),
			databasePath: native.databasePath(),
			databaseName: native.databaseName(),
			databaseMissing: native.databaseMissing(),
			proxiedServer: native.proxiedServer(),
			listLimitConfigured: native.listLimitConfigured(),
			listLimit: native.listLimit()
		});
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/workspacefacade")
@:go.name("Location")
extern class NativeLocation {
	@:go.name("Path") function path():String;
	@:go.name("RedirectedFrom") function redirectedFrom():String;
	@:go.name("Prefix") function prefix():String;
	@:go.name("DatabasePath") function databasePath():String;
	@:go.name("DatabaseName") function databaseName():String;
	@:go.name("DatabaseMissing") function databaseMissing():Bool;
	@:go.name("ProxiedServer") function proxiedServer():Bool;
	@:go.name("ListLimitConfigured") function listLimitConfigured():Bool;
	@:go.name("ListLimit") function listLimit():Int;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/workspacefacade")
extern class NativeWorkspaceFacade {
	@:go.name("DiscoverFrom")
	@:go.valueError
	static function discoverFrom(directory:String, databasePath:String):Result<NativeLocation>;
}
