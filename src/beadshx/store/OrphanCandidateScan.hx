package beadshx.store;

/** Candidate issues plus the database prefix fallback used for commit matching. */
typedef OrphanCandidateScan = {
	final prefix:String;
	final candidates:Array<OrphanCandidate>;
}
