package beadshx.nativeextern.issueops;

/**
	Precise subset of Beads' exported issue-list request used to enumerate all
	query candidates. Unrepresented fields keep their Go zero values.
**/
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("ListRequest")
@:go.struct
extern class ListRequest {
	public function new();

	@:go.name("AllFlag") public var allFlag:Bool;
	@:go.name("IncludeAllTypes") public var includeAllTypes:Bool;
	@:go.name("Offset") public var offset:Int;
}
