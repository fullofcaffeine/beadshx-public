package beadshx.relation;

/**
	The smallest native persistence answer needed by Haxe dependency reads.

	Native code owns a consistent read transaction. It reports only which source
	rows exist and the stored edge rows; it does not validate, filter, order, or
	assemble command results.
**/
typedef DependencySnapshot = {
	final presentIds:Array<String>;
	final edges:Array<RawDependencyEdge>;
}
