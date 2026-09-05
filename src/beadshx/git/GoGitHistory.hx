package beadshx.git;

import beadshx.store.StoreResult;
import go.Result;

/**
	Runs the bounded native Git history probe and immediately narrows its result.

	Git process mechanics stay native. Haxe receives only the raw stable
	`--oneline` text and owns issue-reference matching and presentation.
**/
@:goNative
final class GoGitHistory implements GitHistoryPort {
	public function new() {}

	public function log(directory:String):StoreResult<String> {
		final result = NativeGitFacade.readLog(directory);
		if (result.isErr()) {
			final message = result.error();
			return Failure(message == null ? "reading git log failed" : message);
		}
		return Success(result.unwrap());
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/gitfacade")
extern class NativeGitFacade {
	@:go.name("ReadLog")
	@:go.valueError
	static function readLog(directory:String):Result<String>;
}
