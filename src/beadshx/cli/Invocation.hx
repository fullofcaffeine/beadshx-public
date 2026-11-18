package beadshx.cli;

import beadshx.store.IssueListRequest;
import beadshx.store.OptionalInt;
import beadshx.store.CountGroup;
import beadshx.store.CountRequest;
import beadshx.store.ReadyRequest;
import beadshx.store.StaleRequest;
import beadshx.query.QueryCommandRequest;

/** A parsed invocation with no process-global or native storage types. */
typedef Invocation = {
	final command:Command;
	final output:OutputMode;
	final actor:String;
	final directory:String;
	final databasePath:String;
	final databaseName:String;
	final global:Bool;
	final cpuProfile:Bool;
	final memProfilePath:String;
	final showHelp:Bool;
	final infoSchema:Bool;
	final infoWhatsNew:Bool;
	final statusSkipBlocked:Bool;
	final statusAssigned:Bool;
	final countRequest:CountRequest;
	final countGroup:CountGroup;
	final readyRequest:ReadyRequest;
	final readyPretty:Bool;
	final readyPlain:Bool;
	final readyClaim:Bool;
	final readyGated:Bool;
	final readyMolecule:String;
	final readyExplain:Bool;
	final searchQuery:String;
	final queryRequest:QueryCommandRequest;
	final staleRequest:StaleRequest;
	final orphansDetails:Bool;
	final orphansFix:Bool;
	final listRequest:IssueListRequest;
	final listWarning:String;
	final listFlat:Bool;
	final listLong:Bool;
	final listNoPager:Bool;
	final listDepsMode:String;
	final listAgentMode:Bool;
	final showShort:Bool;
	final showLong:Bool;
	final showCurrent:Bool;
	final watchMode:Bool;
	final showThread:Bool;
	final showRefs:Bool;
	final showChildren:Bool;
	final showIncludeDependents:Bool;
	final showIncludeComments:Bool;
	final showBriefDependencies:Bool;
	final showIds:Array<String>;
	final depType:String;
	final depListSelection:DepListSelection;
	final depTree:DepTreeInvocation;
	final graph:GraphInvocation;
}

/**
	The `bd graph` arguments and flags as typed. The command checks them after the
	store opens, in upstream's order, and reads the row cap only after the load.
**/
typedef GraphInvocation = {
	/** The arguments after `graph`; upstream accepts at most one. */
	final ids:Array<String>;

	final all:Bool;

	/**
		The first of `--open`, `--dot`, `--html`, `--compact` and `--box` that is set, in
		upstream's order, or "". With `--all`, `--html` comes before `--dot`.
	**/
	final view:String;

	final maxRows:OptionalInt;
	final maxRowsSource:String;

	/** The warning for a malformed BEADS_MAX_ROWS, printed when upstream reads the cap. */
	final maxRowsWarning:String;
}

/**
	The `bd dep tree` flags as typed. The direction, depth and row cap are checked by the
	command itself, after the store opens, in upstream's order.
**/
typedef DepTreeInvocation = {
	/** The issue ID argument as typed; it can be a partial ID. */
	final root:String;

	/** `--direction`, or `up` for `--reverse` without it, or `down`. */
	final direction:String;

	final maxDepth:Int;
	final status:String;

	/** A `--format` value other than `json`; only `mermaid` changes the output. */
	final format:String;

	final maxRows:OptionalInt;
	final maxRowsSource:String;

	/** The warning for a malformed BEADS_MAX_ROWS, printed when upstream reads the cap. */
	final maxRowsWarning:String;
}
