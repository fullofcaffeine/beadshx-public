package beadshx.relation;

/** One validated dependency edge owned by the Haxe relation domain. */
typedef DependencyEdge = {
	final id:String;
	final issueId:String;
	final dependsOnId:String;
	final dependencyType:DependencyKind;
	final createdAt:String;
	final createdBy:String;
	final metadata:String;
	final threadId:String;
}
