package beadshx.ready;

/** Complete Haxe-owned readiness analysis for one molecule subgraph. */
typedef MoleculeReadyAnalysis = {
	final moleculeId:String;
	final totalSteps:Int;
	final readySteps:Int;
	final groups:Array<MoleculeParallelGroup>;
	final steps:Array<MoleculeParallelInfo>;
}
