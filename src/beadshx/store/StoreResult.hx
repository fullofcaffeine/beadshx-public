package beadshx.store;

/** A typed native-store outcome keeps Go errors out of command logic. */
enum StoreResult<T> {
	Success(value:T);
	Failure(message:String);
}
