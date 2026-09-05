package beadshx.store;

/** Ready query failures keep the defensive row cap distinct from storage errors. */
enum ReadyLoadResult {
	ReadySuccess(value:ReadyResult);
	ReadyFailure(message:String);
	ReadyRowLimitExceeded(found:Int, source:String, cap:Int);
}
