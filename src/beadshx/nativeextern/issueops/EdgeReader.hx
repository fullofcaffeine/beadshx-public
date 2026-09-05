package beadshx.nativeextern.issueops;

import beadshx.nativeextern.context.Context;

/** Exported raw dependency-edge role consumed directly by authored Haxe. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("EdgeReader")
extern interface EdgeReader {
	@:go.tupleReturn
	@:go.valueArgs("1")
	@:go.tupleValueResults("0")
	@:go.name("ReadEdges")
	public function readEdges(context:Context, request:EdgeReadRequest):EdgeReaderResult;
}
