package beadshx.ready;

/** The small issue projection required to decide molecule readiness. */
typedef MoleculeStep = {
	final id:String;
	final title:String;
	final status:String;
	final priority:Int;
	final issueType:String;
}
