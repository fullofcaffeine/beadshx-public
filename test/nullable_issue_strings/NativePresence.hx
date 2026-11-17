/** The exported zero value proves nullable native calls retain nil through the typed ABI. */
@:goNative
class NativePresence {
	public static function check(failures:Array<String>):Void {
		final record = new ZeroRecord();
		if (record.externalRef() != null)
			failures.push("native zero external_ref must remain absent");
		if (record.compactedAtCommit() != null)
			failures.push("native zero compacted_at_commit must remain absent");
	}
}

/** Exact exported facade type: no test constructor or product wrapper is required. */
@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueRecord")
@:go.struct
private extern class ZeroRecord {
	public function new();
	@:go.name("ExternalRef") public function externalRef():Null<String>;
	@:go.name("CompactedAtCommit") public function compactedAtCommit():Null<String>;
}
