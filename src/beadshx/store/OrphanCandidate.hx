package beadshx.store;

/** Open or in-progress issue that can be matched against Git history. */
typedef OrphanCandidate = {
	final id:String;
	final title:String;
	final status:String;
}
