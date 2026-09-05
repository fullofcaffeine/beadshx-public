package beadshx.store;

import beadshx.store.QueryStorageRequest.QueryRowPage;

/** Storage-only result for one already-planned query fetch. */
enum QueryRowResult {
	QueryRows(page:QueryRowPage);
	QueryRowsFailure(message:String);
}
