package beadshx.ready;

import beadshx.store.IssueListItem;

/** One molecule whose closed gate now permits a ready step to resume. */
typedef GatedMolecule = {
	final moleculeId:String;
	final moleculeTitle:String;
	final closedGate:IssueListItem;
	final readyStep:IssueListItem;
}
