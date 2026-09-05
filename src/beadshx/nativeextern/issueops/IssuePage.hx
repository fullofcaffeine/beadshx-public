package beadshx.nativeextern.issueops;

/** Native page kept opaque except for continuation evidence. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("IssuePage")
@:go.struct
extern class IssuePage {
	public function new();

	@:go.name("HasMore") public var hasMore:Bool;
}
