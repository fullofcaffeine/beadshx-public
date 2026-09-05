package beadshx.nativeextern.issueops;

/** Exact per-anchor raw-edge answer, including source-missing evidence. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("AnchorEdges")
@:go.struct
@:goNative
extern class AnchorEdges {
	@:go.name("ID") public var id:String;
	@:go.name("Edges") public var edges:go.NativeSlice<Dependency>;
	@:go.name("Missing") public var missing:Bool;
}
