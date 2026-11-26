package beadshx.nativeextern.glamour;

/**
	A glamour v2 `TermRendererOption`: one setting that `NewTermRenderer`
	applies to the renderer it builds.

	The Go type is a named function type. Haxe only passes the values that
	glamour's `With*` functions return on to `NewTermRenderer`; it never calls
	or builds one.
**/
@:go.import("charm.land/glamour/v2")
@:go.package("glamour")
@:go.name("TermRendererOption")
extern interface TermRendererOption {}
