package beadshx.nativeextern.issueops;

/** Exact batch request for the exported raw-edge role. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("EdgeReadRequest")
@:go.struct
@:goNative
extern class EdgeReadRequest {
	public function new();

	@:go.name("IDs") public var ids:go.NativeStringSlice;
	@:go.name("Types") public var types:go.NativeSlice<DependencyType>;
}
