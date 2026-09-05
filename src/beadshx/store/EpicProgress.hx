package beadshx.store;

/** Optional epic child-progress projection from a show detail read. */
enum EpicProgress {
	NoEpicProgress;
	HasEpicProgress(totalChildren:Int, closedChildren:Int, closeable:Bool);
}
