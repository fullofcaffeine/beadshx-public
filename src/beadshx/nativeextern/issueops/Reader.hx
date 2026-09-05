package beadshx.nativeextern.issueops;

import beadshx.nativeextern.context.Context;

/** Exported Beads read role consumed directly by authored Haxe. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("Reader")
extern interface Reader {
	@:go.tupleReturn
	@:go.valueArgs("1")
	@:go.tupleValueResults("0")
	@:go.name("List")
	public function list(context:Context, request:ListRequest):ReaderListResult;
}
