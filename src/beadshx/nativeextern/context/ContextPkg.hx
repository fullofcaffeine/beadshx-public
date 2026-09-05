package beadshx.nativeextern.context;

/** Package functions needed to create a non-cancelled query context. */
@:go.import("context")
@:go.package("context")
extern class ContextPkg {
	@:go.name("Background")
	public static function background():Context;
}
