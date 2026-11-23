package beadshx.cli;

import beadshx.config.DatabaseVariableSelection;
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

	/** The --db value, or the BEADS_DB or BD_DB path that `databaseVariable` selects instead; it can be empty. */
	final databasePath:String;

	/** What BEADS_DB or BD_DB selects: a path is then `databasePath`, as if --db had named it. */
	final databaseVariable:DatabaseVariableSelection;

	final databaseName:String;
	final global:Bool;

	/**
		The --readonly value, which pflag reads as a bool (`--readonly=false`
		and the other strconv.ParseBool forms too), or null when the flag is
		absent. Upstream's strict read-only mode is this value, or the
		`readonly` setting when the flag is absent.
	**/
	final readonly:Null<Bool>;

	/** --ignore-schema-skew: upstream's pre-run then sets BD_IGNORE_SCHEMA_SKEW=1 for every store open. */
	final ignoreSchemaSkew:Bool;

	final cpuProfile:Bool;
	final memProfilePath:String;
	final showHelp:Bool;

	/** `bd help <command>`: cobra's help command, which runs upstream's root pre-run; a --help flag does not. */
	final helpCommand:Bool;

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

	/** The BEADS_MAX_ROWS warning of `list` and `ready`, which prints where the command reads BEADS_MAX_ROWS. */
	final listWarning:String;

	/**
		The first argument check that upstream runs in the command body, after
		its pre-run. For `list` and `ready`, the checks before the command reads
		--max-rows and BEADS_MAX_ROWS.
	**/
	final deferredCheck:DeferredCheck;

	/** `ready`'s --brief rules, which its command body checks before it picks a route or a view. */
	final readyModeCheck:DeferredCheck;

	/** A negative --max-rows of `list` or `ready`; when it is set, the command reads no BEADS_MAX_ROWS. */
	final maxRowsCheck:DeferredCheck;

	/** `ready`'s metadata filter and --sort checks, which come after it reads --max-rows and BEADS_MAX_ROWS. */
	final readyFilterCheck:DeferredCheck;

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
	final comments:CommentsInvocation;
	final history:HistoryInvocation;
	final events:EventsInvocation;

	/** `bd types --sections`. */
	final typesSections:Bool;

	/** The `bd config get` key as typed; it can be empty. */
	final configKey:String;

	/** The `bd config show --source` prefix; empty keeps every row. */
	final configSource:String;
}

/** The `bd events tail` and `bd events export` arguments; export has no --since and reads from 0. */
typedef EventsInvocation = {
	final since:haxe.Int64;

	/** `--limit`; zero or a negative value reads every row. */
	final limit:haxe.Int64;
}

/** The `bd history` arguments as typed. */
typedef HistoryInvocation = {
	/** The issue ID argument as typed; it can be a partial ID. */
	final issueId:String;

	/** `--limit`; zero or a negative value keeps every entry. */
	final limit:Int;

	final events:Bool;
}

/** The `bd comments` listing arguments as typed. */
typedef CommentsInvocation = {
	/** The issue ID argument as typed; it can be a partial ID. */
	final issueId:String;

	/** `bd comments list`, which upstream rejects only after it opens the store. */
	final misplacedList:Bool;

	final localTime:Bool;
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
