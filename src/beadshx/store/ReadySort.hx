package beadshx.store;

/** Closed ordering policies accepted by the pinned ready command. */
enum ReadySort {
	Priority;
	Hybrid;
	Oldest;
}
