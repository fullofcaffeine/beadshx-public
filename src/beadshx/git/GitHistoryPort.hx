package beadshx.git;

import beadshx.store.StoreResult;

/** Read-only Git history boundary used by repository-aware command policy. */
interface GitHistoryPort {
	function log(directory:String):StoreResult<String>;
}
