package beadshx.ready;

/** One deterministically named group of steps that can execute together. */
typedef MoleculeParallelGroup = {
	final name:String;
	final members:Array<String>;
}
