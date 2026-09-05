package beadshx.ready;

/** One storage-neutral dependency edge used by molecule readiness policy. */
typedef MoleculeDependency = {
	final issueId:String;
	final dependsOnId:String;
	final dependencyType:String;
	final metadata:String;
}
