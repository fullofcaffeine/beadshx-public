package beadshx.nativeextern.issueops;

/** Exact exported raw-edge batch result. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("EdgeReadResult")
@:go.struct
@:goNative
extern class EdgeReadResult {
	@:go.name("Anchors") public var anchors:go.NativeSlice<AnchorEdges>;
}
