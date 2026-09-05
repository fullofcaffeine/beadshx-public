package beadshx.ready;

/** Dependency-derived execution facts for one molecule step. */
typedef MoleculeParallelInfo = {
	final stepId:String;
	final status:String;
	final isReady:Bool;
	var parallelGroup:String;
	final blockedBy:Array<String>;
	final blocks:Array<String>;
	var canParallel:Array<String>;
}
