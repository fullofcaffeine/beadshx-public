package beadshx.relation;

/** Haxe-owned outgoing edges and source-presence result for one exact anchor. */
typedef DependencyAnchor = {
	final id:String;
	final edges:Array<DependencyEdge>;
	final missing:Bool;
}
