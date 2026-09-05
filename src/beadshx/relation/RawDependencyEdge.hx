package beadshx.relation;

/** One dependency row copied from a native persistence snapshot. */
typedef RawDependencyEdge = {
	final id:String;
	final issueId:String;
	final dependsOnId:String;
	final dependencyType:String;
	final createdAt:String;
	final createdBy:String;
	final metadata:String;
	final threadId:String;
}
