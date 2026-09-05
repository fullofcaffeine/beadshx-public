package beadshx.store;

/** Typed list outcome keeps a defensive row-cap refusal distinct from I/O. */
enum IssueListResult {
	ListSuccess(page:IssueListPage);
	ListFailure(message:String);
	ListRowLimitExceeded(found:Int, source:String, cap:Int);
}
