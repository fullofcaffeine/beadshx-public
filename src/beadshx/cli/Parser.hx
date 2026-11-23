package beadshx.cli;

import beadshx.cli.DepListSelection.selectDepList;
import beadshx.cli.Invocation.CommentsInvocation;
import beadshx.cli.Invocation.DepTreeInvocation;
import beadshx.cli.Invocation.EventsInvocation;
import beadshx.cli.Invocation.GraphInvocation;
import beadshx.cli.Invocation.HistoryInvocation;
import beadshx.cli.PflagValue.Int64FlagValue;
import beadshx.cli.PflagValue.IntFlagValue;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.config.LayeredConfig.goQuote;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.CustomConfig.isGoSpace;
import beadshx.store.OptionalInt;
import beadshx.store.CountGroup;
import beadshx.store.IssueListMetadataFilter;
import beadshx.store.IssueListTimeFilter;
import beadshx.store.ReadySort;
import beadshx.store.StaleRequest;
import beadshx.query.QueryCommandRequest;
import haxe.Int64;

private enum ListTimeField {
	TimeCreatedAfter;
	TimeCreatedBefore;
	TimeUpdatedAfter;
	TimeUpdatedBefore;
	TimeClosedAfter;
	TimeClosedBefore;
	TimeDeferAfter;
	TimeDeferBefore;
	TimeDueAfter;
	TimeDueBefore;
}

/** The flags that are int flags on a ported command. list and search read the priority flags as strings. */
private enum IntegerFlag {
	LimitFlag;
	OffsetFlag;
	MaxRowsFlag;
	PriorityFlag;
	PriorityMinFlag;
	PriorityMaxFlag;
	DaysFlag;
	MaxDepthFlag;
}

private enum ExpectedValue {
	Actor;
	ShortDirectory;
	LongDirectory;
	DatabasePath;
	DatabaseName;
	OutputFormat;
	DoltAutoCommit;
	MemProfile;
	IssueID;
	ShortS;
	ListStatus;
	ListAssignee;
	ListIssueType;
	ListSort;
	ListTitle;
	ListSpec;
	ListLabel;
	ListLabelAny;
	ListExcludeLabel;
	ListLabelPattern;
	ListLabelRegex;
	ListTitleContains;
	ListDescriptionContains;
	ListNotesContains;
	ListExternalContains;
	ListExternalRef;
	ListExcludeType;
	ListParent;
	ListMoleculeType;
	ListWispType;
	ListMetadataField;
	ListHasMetadataKey;
	ListTime(field:ListTimeField);

	/** The value of an int flag, or of a priority flag, as `typed` (such as `-n` or `--limit`). */
	IntegerValue(flag:IntegerFlag, typed:String);

	ReadyMolecule;
	SearchQuery;
	DepDirection;
	EventsSince;
	EventsBefore;
	ConfigShowSource;

	/** The argument after a flag that no command has, which cobra skips when it looks for the command. */
	UnknownFlagValue;
}

/** What pflag reports for one flag once cobra has found the command. */
private enum FlagCheck {
	/** A flag that only some commands have: pflag reports it as unknown on the others. */
	CommandFlag;

	/** pflag's error for a value that the flag rejects. A command flag comes after its CommandFlag. */
	RejectedValue(message:String);

	/** An int flag's value, which pflag parses with the flag of the command found. */
	IntegerArgument(flag:IntegerFlag, raw:String);

	/** An error on every command: a flag that no command has, or a flag with no value after it. */
	FlagFailure(message:String);
}

/**
	Why: pflag parses the arguments in order once cobra has found the command,
	and stops at the first problem.

	What: one flag, in argument order, with what pflag checks for it.
**/
private typedef FlagUse = {
	/** The flag as typed, without a value: `--limit` or `-n`. */
	final typed:String;

	/** The argument that holds the flag, which pflag quotes in a shorthand error. */
	final argument:String;

	final check:FlagCheck;
}

/** Upstream validateCommentsArgs for `bd comments` with more than one argument. */
private final COMMENTS_TAKES_ONE_ID = '"bd comments" takes a single issue id and lists its comments.\n\n'
	+ 'To list comments:\n  bd comments <issue-id>\n\nTo add a comment:\n  bd comments add <issue-id> <text>\n\nSee: bd comments --help';

/** Parses the bounded read-only command profile without Cobra; it reaches the process only through its ports. */
final class Parser {
	final environment:EnvironmentPort;
	final jsonSetting:JsonSettingPort;

	public function new(environment:EnvironmentPort, jsonSetting:JsonSettingPort) {
		this.environment = environment;
		this.jsonSetting = jsonSetting;
	}

	public function parse(args:Array<String>):ParseResult {
		final positional = new Array<String>();
		return switch parseCommand(args, positional) {
			// `bd events` has no SilenceUsage, unlike its subcommands; every usage failure there is a flag error.
			case UsageFailure(message)
				if (positional.length > 0
					&& positional[0] == "events"
					&& !(positional.length > 1 && (positional[1] == "tail" || positional[1] == "export" || positional[1] == "prune"))):
				GroupUsageFailure(message, Command.Events);
			case result: result;
		};
	}

	/** Parses `args`, leaving the positional arguments read so far in `positional`. */
	function parseCommand(args:Array<String>, positional:Array<String>):ParseResult {
		// The last --json value and the last --format value; outputMode() reads them after the loop.
		var jsonFlagSet = false;
		var jsonFlagValue = false;
		var formatFlagSet = false;
		var formatFlagValue = "";
		var versionFlag = false;
		var actor = "";
		var directory = "";
		var databasePath = "";
		var databaseName = "";
		var global = false;
		// Null while --readonly is absent: upstream then takes the readonly setting.
		var readonly:Null<Bool> = null;
		var ignoreSchemaSkew = false;
		var cpuProfile = false;
		var memProfilePath = "";
		var expectedValue:Null<ExpectedValue> = null;
		var showHelp = false;
		var infoSchema = false;
		var infoWhatsNew = false;
		var statusSkipBlocked = false;
		var statusAssigned = false;
		// Each flag in argument order, which the pflag pass checks once the command is known.
		final flagUses = new Array<FlagUse>();
		// The argument of the flag that the loop reads now, also while it reads the flag's value.
		var flagArgument = "";
		// A flag that only some commands have, as typed: `-n` or `--limit`.
		function useCommandFlag(typed:String):Void {
			flagUses.push({typed: typed, argument: flagArgument, check: CommandFlag});
		}
		function rejectValue(typed:String, message:String):Void {
			flagUses.push({typed: typed, argument: flagArgument, check: RejectedValue(message)});
		}
		// A bool flag's value after "=", or null when pflag rejects it.
		function booleanValue(typed:String, value:String):Null<Bool> {
			if (isBooleanFlagValue(value))
				return booleanFlagValue(value);
			rejectValue(typed, PflagValue.invalidBoolean(typed, value));
			return null;
		}
		// Upstream checks these in its pre-run, after cobra's flag errors; the first one wins.
		var preRunFailure:Null<String> = null;
		function failPreRun(message:String):Void {
			if (preRunFailure == null)
				preRunFailure = message;
		}
		// The last value of each --by-* flag; upstream's count groups by the flags that end up true.
		final countGroupFlags = new Map<String, Bool>();
		function setCountGroupFlag(flag:String, enabled:Bool):Void {
			countGroupFlags.set(flag, enabled);
		}
		var listStatus = "";
		var listAssignee = "";
		var listIssueType = "";
		var depTypeRaw = "";
		var listTitle = "";
		var listSpec = "";
		// Upstream checks these filter values in the command body, so the parser keeps the last raw value.
		var listPriority = OptionalInt.IntAbsent;
		var listPriorityRaw:Null<String> = null;
		var listPriorityMin = OptionalInt.IntAbsent;
		var listPriorityMinRaw:Null<String> = null;
		var listPriorityMax = OptionalInt.IntAbsent;
		var listPriorityMaxRaw:Null<String> = null;
		var listMoleculeTypeRaw = "";
		var listWispTypeRaw = "";
		var listHasMetadataKeyRaw = "";
		final listMetadataFieldsRaw = new Array<String>();
		// By flag name without the dashes.
		final listTimeRaw = new Map<String, String>();
		var listLimit = OptionalInt.IntAbsent;
		var listOffset = OptionalInt.IntAbsent;
		var listMaxRows = OptionalInt.IntAbsent;
		var listMaxRowsSource = "";
		var listWarning = "";
		var listFormat = "";
		var listDepsMode = "";
		var listSort = "";
		var listLabelPattern = "";
		var listLabelRegex = "";
		var listTitleContains = "";
		var listDescriptionContains = "";
		var listNotesContains = "";
		var listExternalContains = "";
		var listExternalRef = "";
		var listParent = "";
		var listMoleculeType = "";
		var listWispType = "";
		var listHasMetadataKey = "";
		var listAll = false;
		var listReady = false;
		var listNoAssignee = false;
		var listNoLabels = false;
		var listEmptyDescription = false;
		var listSkipLabels = false;
		var listBrief = false;
		var listPinned = false;
		var listNoPinned = false;
		var listIncludeTemplates = false;
		var listIncludeGates = false;
		var listIncludeInfra = false;
		var listNoParent = false;
		var listDeferred = false;
		var listOverdue = false;
		var listReverse = false;
		var listFlat = false;
		var listLong = false;
		var listTree = true;
		var listPretty = false;
		var listPrettyChanged = false;
		var listNoPager = false;
		final listLabels = new Array<String>();
		final listLabelsAny = new Array<String>();
		final listExcludeLabels = new Array<String>();
		final listExcludeTypes = new Array<String>();
		final listMetadataFields = new Array<IssueListMetadataFilter>();
		final listTimeFilters = new Array<IssueListTimeFilter>();
		var shorthandS = "";
		var readyUnassigned = false;
		var readyIncludeDeferred = false;
		var readyIncludeEphemeral = false;
		var readyPlain = false;
		var readyClaim = false;
		var readyGated = false;
		var readyMolecule = "";
		var readyExplain = false;
		var searchQueryFlag = "";
		var queryParseOnly = false;
		var staleDays = 30;
		var orphansDetails = false;
		var typesSections = false;
		var configSource = "";
		var orphansFix = false;
		var depDirection = "down";
		var depDirectionUsed = false;
		var depTreeMaxDepth = 50;
		var deferredMaxRowsWarning = "";
		final graphViews = new Map<String, Bool>();
		var commentsLocalTime = false;
		var historyEvents = false;
		var eventsSince = Int64.ofInt(0);
		var eventsLimit = Int64.ofInt(0);
		var eventsFollow = false;
		// An int64 value of `events tail`, which pflag parses as it reads the flag.
		function readInt64Value(typed:String, raw:String):Null<Int64> {
			return switch PflagValue.parseInt64(typed, raw) {
				case Int64Rejected(message):
					rejectValue(typed, message);
					null;
				case Int64Accepted(value): value;
			};
		}
		// Upstream runs these checks in the command body, after its pre-run; the first one in its order wins.
		var deferredCheck = DeferredCheck.ChecksPassed;
		function deferCheck(failure:DeferredCheck):Void {
			if (checkPassed(deferredCheck))
				deferredCheck = failure;
		}
		// ready's --brief rules, which its command body checks before anything else.
		var readyModeCheck = DeferredCheck.ChecksPassed;
		// A negative --max-rows, which list and ready report where they read BEADS_MAX_ROWS.
		var maxRowsCheck = DeferredCheck.ChecksPassed;
		// ready's metadata filter and --sort checks, which come after it reads --max-rows.
		var readyFilterCheck = DeferredCheck.ChecksPassed;
		function deferFilterCheck(failure:DeferredCheck):Void {
			if (checkPassed(readyFilterCheck))
				readyFilterCheck = failure;
		}
		var showShort = false;
		var showLong = false;
		var showCurrent = false;
		var watchMode = false;
		var showThread = false;
		var showRefs = false;
		var showChildren = false;
		var showIncludeDependents = false;
		var showIncludeComments = false;
		var showBriefDependencies = false;
		var showIds = new Array<String>();
		final issueFlagIds = new Array<String>();
		var flagsEnded = false;
		// The shorthands of the int flags. The pflag pass reads -d as --max-depth in `dep tree`.
		function integerShorthand(typed:String):Null<IntegerFlag> {
			return switch typed {
				case "-n": LimitFlag;
				case "-p": PriorityFlag;
				case "-d": DaysFlag;
				case _: null;
			};
		}
		// Takes a value for the command found, which has the flag: pflag parses an int flag's value.
		function applyIntegerValue(flag:IntegerFlag, typed:String, raw:String):Null<String> {
			final name = integerFlagName(flag, typed, positional);
			if (name == null) {
				// A string flag of this command.
				switch flag {
					case PriorityFlag:
						listPriorityRaw = raw;
					case PriorityMinFlag:
						listPriorityMinRaw = raw;
					case PriorityMaxFlag:
						listPriorityMaxRaw = raw;
					case _:
				}
				return null;
			}
			switch PflagValue.parseInt(name, raw) {
				case IntRejected(message):
					return message;
				case IntAccepted(value):
					switch flag {
						case LimitFlag:
							listLimit = IntPresent(value);
						case OffsetFlag:
							listOffset = IntPresent(value);
						case MaxRowsFlag:
							// Each command checks the sign itself, after its pre-run.
							listMaxRows = IntPresent(value);
							listMaxRowsSource = "--max-rows";
						case PriorityFlag:
							listPriority = IntPresent(value);
						case PriorityMinFlag:
							listPriorityMin = IntPresent(value);
						case PriorityMaxFlag:
							listPriorityMax = IntPresent(value);
						case DaysFlag:
							staleDays = value;
						case MaxDepthFlag:
							depTreeMaxDepth = value;
					}
			}
			return null;
		}
		// An int flag's value, which the pflag pass parses with the flag of the command found.
		function readIntegerValue(flag:IntegerFlag, typed:String, raw:String):Void {
			flagUses.push({typed: typed, argument: flagArgument, check: IntegerArgument(flag, raw)});
		}
		for (argument in args) {
			if (expectedValue != null) {
				switch expectedValue {
					case Actor:
						if (argument == "")
							failPreRun("--actor requires a non-empty value");
						actor = argument;
					case ShortDirectory | LongDirectory:
						directory = argument;
					case DatabasePath:
						databasePath = argument;
					case DatabaseName:
						databaseName = argument;
					case OutputFormat:
						formatFlagSet = true;
						formatFlagValue = argument;
					case DoltAutoCommit:
						if (!isDoltAutoCommitValue(argument))
							failPreRun('invalid --dolt-auto-commit="${argument}" (valid: off, on, batch)');
					case MemProfile:
						memProfilePath = argument;
					case IssueID:
						issueFlagIds.push(argument);
					case ShortS:
						shorthandS = argument;
					case ListStatus:
						listStatus = argument;
					case ListAssignee:
						listAssignee = argument;
					case ListIssueType:
						depTypeRaw = argument;
						listIssueType = normalizeIssueType(argument);
					case IntegerValue(flag, typed):
						readIntegerValue(flag, typed, argument);
					case ListSort:
						listSort = argument;
					case ListTitle:
						listTitle = argument;
					case ListSpec:
						listSpec = argument;
					case ListLabel:
						addCommaSeparated(listLabels, argument);
					case ListLabelAny:
						addCommaSeparated(listLabelsAny, argument);
					case ListExcludeLabel:
						addCommaSeparated(listExcludeLabels, argument);
					case ListLabelPattern:
						listLabelPattern = argument;
					case ListLabelRegex:
						listLabelRegex = argument;
					case ListTitleContains:
						listTitleContains = argument;
					case ListDescriptionContains:
						listDescriptionContains = argument;
					case ListNotesContains:
						listNotesContains = argument;
					case ListExternalContains:
						listExternalContains = argument;
					case ListExternalRef:
						listExternalRef = argument;
					case ListExcludeType:
						addCommaSeparated(listExcludeTypes, argument);
					case ListParent:
						listParent = argument;
					case ListMoleculeType:
						listMoleculeTypeRaw = argument;
					case ListWispType:
						listWispTypeRaw = argument;
					case ListMetadataField:
						listMetadataFieldsRaw.push(argument);
					case ListHasMetadataKey:
						listHasMetadataKeyRaw = argument;
					case ListTime(field):
						listTimeRaw.set(listTimeFlag(field), argument);
					case ReadyMolecule:
						readyMolecule = argument;
					case SearchQuery:
						searchQueryFlag = argument;
					case DepDirection:
						depDirection = argument;
					case EventsSince:
						final value = readInt64Value("--since", argument);
						if (value != null)
							eventsSince = value;
					case EventsBefore:
						readInt64Value("--before", argument);
					case ConfigShowSource:
						configSource = argument;
					case UnknownFlagValue:
				}
				expectedValue = null;
				continue;
			}
			flagArgument = argument;
			if (argument == "--") {
				flagsEnded = true;
				continue;
			}
			if (flagsEnded) {
				positional.push(argument);
				continue;
			}
			if (StringTools.startsWith(argument, "--actor=")) {
				actor = argument.substr(8);
				if (actor == "")
					failPreRun("--actor requires a non-empty value");
				continue;
			}
			if (StringTools.startsWith(argument, "--directory=")) {
				directory = argument.substr(12);
				continue;
			}
			if (StringTools.startsWith(argument, "--database=")) {
				databaseName = argument.substr(11);
				continue;
			}
			if (StringTools.startsWith(argument, "--db=")) {
				databasePath = argument.substr(5);
				continue;
			}
			if (StringTools.startsWith(argument, "--format=")) {
				formatFlagSet = true;
				formatFlagValue = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--json=")) {
				final value = booleanValue("--json", argument.substr(7));
				if (value != null) {
					jsonFlagSet = true;
					jsonFlagValue = value;
				}
				continue;
			}
			if (StringTools.startsWith(argument, "--dolt-auto-commit=")) {
				final value = argument.substr(19);
				if (!isDoltAutoCommitValue(value))
					failPreRun('invalid --dolt-auto-commit="${value}" (valid: off, on, batch)');
				continue;
			}
			if (StringTools.startsWith(argument, "--mem-profile=")) {
				memProfilePath = argument.substr(14);
				continue;
			}
			if (StringTools.startsWith(argument, "--query=")) {
				useCommandFlag("--query");
				searchQueryFlag = argument.substr(8);
				continue;
			}
			if (StringTools.startsWith(argument, "--days=")) {
				useCommandFlag("--days");
				readIntegerValue(DaysFlag, "--days", argument.substr(7));
				continue;
			}
			if (StringTools.startsWith(argument, "--direction=")) {
				useCommandFlag("--direction");
				depDirectionUsed = true;
				depDirection = argument.substr(12);
				continue;
			}
			if (StringTools.startsWith(argument, "--source=")) {
				useCommandFlag("--source");
				configSource = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--details=")
				|| StringTools.startsWith(argument, "--fix=")
				|| StringTools.startsWith(argument, "-f=")
				|| StringTools.startsWith(argument, "--sections=")) {
				final separator = argument.indexOf("=");
				final flag = argument.substr(0, separator);
				useCommandFlag(flag);
				final value = booleanValue(flag, argument.substr(separator + 1));
				if (value == null)
					continue;
				if (flag == "--details")
					orphansDetails = value;
				else if (flag == "--sections")
					typesSections = value;
				else
					orphansFix = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--id=")) {
				useCommandFlag("--id");
				issueFlagIds.push(argument.substr(5));
				continue;
			}
			if (StringTools.startsWith(argument, "--status=")) {
				useCommandFlag("--status");
				listStatus = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--assignee=")) {
				useCommandFlag("--assignee");
				listAssignee = argument.substr(11);
				continue;
			}
			if (StringTools.startsWith(argument, "--type=")) {
				useCommandFlag("--type");
				depTypeRaw = argument.substr(7);
				listIssueType = normalizeIssueType(depTypeRaw);
				continue;
			}
			if (StringTools.startsWith(argument, "--priority=")) {
				useCommandFlag("--priority");
				readIntegerValue(PriorityFlag, "--priority", argument.substr(11));
				continue;
			}
			if (StringTools.startsWith(argument, "--limit=")) {
				useCommandFlag("--limit");
				readIntegerValue(LimitFlag, "--limit", argument.substr(8));
				continue;
			}
			if (StringTools.startsWith(argument, "--sort=")) {
				useCommandFlag("--sort");
				listSort = argument.substr(7);
				continue;
			}
			if (StringTools.startsWith(argument, "-s=")) {
				useCommandFlag("-s");
				shorthandS = argument.substr(3);
				continue;
			}
			if (StringTools.startsWith(argument, "--title=")) {
				useCommandFlag("--title");
				listTitle = argument.substr(8);
				continue;
			}
			if (StringTools.startsWith(argument, "--spec=")) {
				useCommandFlag("--spec");
				listSpec = argument.substr(7);
				continue;
			}
			if (StringTools.startsWith(argument, "--label=")) {
				useCommandFlag("--label");
				addCommaSeparated(listLabels, argument.substr(8));
				continue;
			}
			if (StringTools.startsWith(argument, "-l=")) {
				useCommandFlag("-l");
				addCommaSeparated(listLabels, argument.substr(3));
				continue;
			}
			if (StringTools.startsWith(argument, "--label-any=")) {
				useCommandFlag("--label-any");
				addCommaSeparated(listLabelsAny, argument.substr(12));
				continue;
			}
			if (StringTools.startsWith(argument, "--exclude-label=")) {
				useCommandFlag("--exclude-label");
				addCommaSeparated(listExcludeLabels, argument.substr(16));
				continue;
			}
			if (StringTools.startsWith(argument, "--label-pattern=")) {
				useCommandFlag("--label-pattern");
				listLabelPattern = argument.substr(16);
				continue;
			}
			if (StringTools.startsWith(argument, "--label-regex=")) {
				useCommandFlag("--label-regex");
				listLabelRegex = argument.substr(14);
				continue;
			}
			if (StringTools.startsWith(argument, "--title-contains=")) {
				useCommandFlag("--title-contains");
				listTitleContains = argument.substr(17);
				continue;
			}
			if (StringTools.startsWith(argument, "--desc-contains=")) {
				useCommandFlag("--desc-contains");
				listDescriptionContains = argument.substr(16);
				continue;
			}
			if (StringTools.startsWith(argument, "--notes-contains=")) {
				useCommandFlag("--notes-contains");
				listNotesContains = argument.substr(17);
				continue;
			}
			if (StringTools.startsWith(argument, "--external-contains=")) {
				useCommandFlag("--external-contains");
				listExternalContains = argument.substr(20);
				continue;
			}
			if (StringTools.startsWith(argument, "--external-ref=")) {
				useCommandFlag("--external-ref");
				listExternalRef = argument.substr(15);
				continue;
			}
			if (StringTools.startsWith(argument, "--priority-min=")) {
				useCommandFlag("--priority-min");
				readIntegerValue(PriorityMinFlag, "--priority-min", argument.substr(15));
				continue;
			}
			if (StringTools.startsWith(argument, "--priority-max=")) {
				useCommandFlag("--priority-max");
				readIntegerValue(PriorityMaxFlag, "--priority-max", argument.substr(15));
				continue;
			}
			if (StringTools.startsWith(argument, "--exclude-type=")) {
				useCommandFlag("--exclude-type");
				addCommaSeparated(listExcludeTypes, argument.substr(15));
				continue;
			}
			if (StringTools.startsWith(argument, "--parent=")) {
				useCommandFlag("--parent");
				listParent = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--mol-type=")) {
				useCommandFlag("--mol-type");
				listMoleculeTypeRaw = argument.substr(11);
				continue;
			}
			if (StringTools.startsWith(argument, "--mol=")) {
				useCommandFlag("--mol");
				readyMolecule = argument.substr(6);
				continue;
			}
			if (StringTools.startsWith(argument, "--wisp-type=")) {
				useCommandFlag("--wisp-type");
				listWispTypeRaw = argument.substr(12);
				continue;
			}
			if (StringTools.startsWith(argument, "--metadata-field=")) {
				useCommandFlag("--metadata-field");
				listMetadataFieldsRaw.push(argument.substr(17));
				continue;
			}
			if (StringTools.startsWith(argument, "--has-metadata-key=")) {
				useCommandFlag("--has-metadata-key");
				listHasMetadataKeyRaw = argument.substr(19);
				continue;
			}
			if (StringTools.startsWith(argument, "--offset=")) {
				useCommandFlag("--offset");
				readIntegerValue(OffsetFlag, "--offset", argument.substr(9));
				continue;
			}
			if (StringTools.startsWith(argument, "--max-rows=")) {
				useCommandFlag("--max-rows");
				readIntegerValue(MaxRowsFlag, "--max-rows", argument.substr(11));
				continue;
			}
			if (StringTools.startsWith(argument, "--max-depth=")) {
				useCommandFlag("--max-depth");
				readIntegerValue(MaxDepthFlag, "--max-depth", argument.substr(12));
				continue;
			}
			if (StringTools.startsWith(argument, "--show-all-paths=")) {
				useCommandFlag("--show-all-paths");
				booleanValue("--show-all-paths", argument.substr(17));
				continue;
			}
			final graphFlag = argument.indexOf("=") > 0 ? argument.substr(0, argument.indexOf("=")) : "";
			if (isGraphViewFlag(graphFlag)) {
				useCommandFlag(graphFlag);
				final value = booleanValue(graphFlag, argument.substr(graphFlag.length + 1));
				if (value != null)
					graphViews.set(graphFlag, value);
				continue;
			}
			if (StringTools.startsWith(argument, "--deps=")) {
				useCommandFlag("--deps");
				listDepsMode = argument.substr(7);
				continue;
			}
			final equalsIndex = argument.indexOf("=");
			if (equalsIndex > 0) {
				final flag = argument.substr(0, equalsIndex);
				if (countGroupFlag(flag) != null) {
					useCommandFlag(flag);
					final value = booleanValue(flag, argument.substr(equalsIndex + 1));
					if (value != null)
						setCountGroupFlag(flag, value);
					continue;
				}
				switch listTimeField(flag) {
					case null:
					case field:
						useCommandFlag(flag);
						listTimeRaw.set(listTimeFlag(field), argument.substr(equalsIndex + 1));
						continue;
				}
				if (isListBooleanFlag(flag)) {
					useCommandFlag(flag);
					final value = booleanValue(flag, argument.substr(equalsIndex + 1));
					if (value == null)
						continue;
					final enabled:Bool = value;
					switch flag {
						case "--all":
							listAll = enabled;
						case "--reverse":
							listReverse = enabled;
						case "--ready":
							listReady = enabled;
						case "--no-assignee":
							listNoAssignee = enabled;
						case "--no-labels":
							listNoLabels = enabled;
						case "--empty-description":
							listEmptyDescription = enabled;
						case "--skip-labels":
							listSkipLabels = enabled;
						case "--brief":
							listBrief = enabled;
						case "--pinned":
							listPinned = enabled;
						case "--no-pinned":
							listNoPinned = enabled;
						case "--include-templates":
							listIncludeTemplates = enabled;
						case "--include-gates":
							listIncludeGates = enabled;
						case "--include-infra":
							listIncludeInfra = enabled;
						case "--no-parent":
							listNoParent = enabled;
						case "--deferred":
							listDeferred = enabled;
						case "--overdue":
							listOverdue = enabled;
						case "--flat":
							listFlat = enabled;
						case "--long":
							listLong = enabled;
							showLong = enabled;
						case "--tree":
							listTree = enabled;
						case "--pretty":
							listPretty = enabled;
							listPrettyChanged = true;
						case "--no-pager":
							listNoPager = enabled;
						case "--unassigned":
							readyUnassigned = enabled;
						case "--include-deferred":
							readyIncludeDeferred = enabled;
						case "--include-ephemeral":
							readyIncludeEphemeral = enabled;
						case "--plain":
							readyPlain = enabled;
						case "--claim":
							readyClaim = enabled;
						case "--gated":
							readyGated = enabled;
						case "--explain":
							readyExplain = enabled;
						case "--parse-only":
							queryParseOnly = enabled;
					}
					continue;
				}
			}
			if (StringTools.startsWith(argument, "--cpu-profile=")) {
				final value = booleanValue("--cpu-profile", argument.substr(14));
				if (value != null)
					cpuProfile = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--ignore-schema-skew=")) {
				final value = booleanValue("--ignore-schema-skew", argument.substr(21));
				if (value != null)
					ignoreSchemaSkew = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--global=")) {
				final value = booleanValue("--global", argument.substr(9));
				if (value != null)
					global = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--readonly=")) {
				final value = booleanValue("--readonly", argument.substr(11));
				if (value != null)
					readonly = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--watch=")
				|| StringTools.startsWith(argument, "--thread=")
				|| StringTools.startsWith(argument, "--refs=")
				|| StringTools.startsWith(argument, "--children=")
				|| StringTools.startsWith(argument, "--include-dependents=")
				|| StringTools.startsWith(argument, "--include-comments=")
				|| StringTools.startsWith(argument, "--brief-deps=")) {
				final flag = argument.substr(0, argument.indexOf("="));
				useCommandFlag(flag);
				final value = booleanValue(flag, argument.substr(argument.indexOf("=") + 1));
				if (value == null)
					continue;
				final enabled:Bool = value;
				if (StringTools.startsWith(argument, "--watch="))
					watchMode = enabled;
				else if (StringTools.startsWith(argument, "--thread="))
					showThread = enabled;
				else if (StringTools.startsWith(argument, "--refs="))
					showRefs = enabled;
				else if (StringTools.startsWith(argument, "--children="))
					showChildren = enabled;
				else if (StringTools.startsWith(argument, "--include-dependents="))
					showIncludeDependents = enabled;
				else if (StringTools.startsWith(argument, "--include-comments="))
					showIncludeComments = enabled;
				else
					showBriefDependencies = enabled;
				continue;
			}
			if (StringTools.startsWith(argument, "--since=") || StringTools.startsWith(argument, "--before=")) {
				final separator = argument.indexOf("=");
				final flag = argument.substr(0, separator);
				useCommandFlag(flag);
				final value = readInt64Value(flag, argument.substr(separator + 1));
				if (value != null && flag == "--since")
					eventsSince = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--follow=")) {
				useCommandFlag("--follow");
				final value = booleanValue("--follow", argument.substr(9));
				if (value != null)
					eventsFollow = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--events=")) {
				useCommandFlag("--events");
				final value = booleanValue("--events", argument.substr(9));
				if (value != null)
					historyEvents = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--local-time=")) {
				useCommandFlag("--local-time");
				final value = booleanValue("--local-time", argument.substr(13));
				if (value != null)
					commentsLocalTime = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--verbose=") || StringTools.startsWith(argument, "-v=")) {
				final value = argument.substr(argument.indexOf("=") + 1);
				if (!isBooleanFlagValue(value))
					rejectValue("--verbose", PflagValue.invalidBoolean("-v, --verbose", value));
				continue;
			}
			if (argument != "-C" && StringTools.startsWith(argument, "-C")) {
				directory = argument.substr(2);
				continue;
			}
			// pflag also takes a shorthand's value from the rest of its argument, after an optional "=".
			final shorthand = argument.substr(0, 2);
			final shorthandFlag = argument.length > 2 ? integerShorthand(shorthand) : null;
			if (shorthandFlag != null) {
				useCommandFlag(shorthand);
				readIntegerValue(shorthandFlag, shorthand, argument.charAt(2) == "=" ? argument.substr(3) : argument.substr(2));
				continue;
			}
			switch argument {
				case "--help" | "-h":
					showHelp = true;
				case "--json":
					jsonFlagSet = true;
					jsonFlagValue = true;
				case "--schema":
					useCommandFlag(argument);
					infoSchema = true;
				case "--whats-new":
					useCommandFlag(argument);
					infoWhatsNew = true;
				case "--actor":
					expectedValue = Actor;
				case "-C":
					expectedValue = ShortDirectory;
				case "--directory":
					expectedValue = LongDirectory;
				case "--db":
					expectedValue = DatabasePath;
				case "--database":
					expectedValue = DatabaseName;
				case "--format":
					expectedValue = OutputFormat;
				case "--dolt-auto-commit":
					expectedValue = DoltAutoCommit;
				case "--global":
					global = true;
				case "--cpu-profile":
					cpuProfile = true;
				case "--mem-profile":
					expectedValue = MemProfile;
				case "--id":
					useCommandFlag(argument);
					expectedValue = IssueID;
				case "--by-status" | "--by-priority" | "--by-type" | "--by-assignee" | "--by-label":
					useCommandFlag(argument);
					setCountGroupFlag(argument, true);
				case "--status":
					useCommandFlag(argument);
					expectedValue = ListStatus;
				case "-s":
					useCommandFlag(argument);
					expectedValue = ShortS;
				case "--assignee" | "-a":
					useCommandFlag(argument);
					if (argument == "-a" && positional.length > 0 && positional[0] == "query")
						listAll = true;
					else
						expectedValue = ListAssignee;
				case "--type" | "-t":
					useCommandFlag(argument);
					expectedValue = ListIssueType;
				case "--priority" | "-p":
					useCommandFlag(argument);
					expectedValue = IntegerValue(PriorityFlag, argument);
				case "--limit" | "-n":
					useCommandFlag(argument);
					expectedValue = IntegerValue(LimitFlag, argument);
				case "--sort":
					useCommandFlag(argument);
					expectedValue = ListSort;
				case "--title":
					useCommandFlag(argument);
					expectedValue = ListTitle;
				case "--spec":
					useCommandFlag(argument);
					expectedValue = ListSpec;
				case "--label" | "-l":
					useCommandFlag(argument);
					expectedValue = ListLabel;
				case "--label-any":
					useCommandFlag(argument);
					expectedValue = ListLabelAny;
				case "--exclude-label":
					useCommandFlag(argument);
					expectedValue = ListExcludeLabel;
				case "--label-pattern":
					useCommandFlag(argument);
					expectedValue = ListLabelPattern;
				case "--label-regex":
					useCommandFlag(argument);
					expectedValue = ListLabelRegex;
				case "--title-contains":
					useCommandFlag(argument);
					expectedValue = ListTitleContains;
				case "--desc-contains":
					useCommandFlag(argument);
					expectedValue = ListDescriptionContains;
				case "--notes-contains":
					useCommandFlag(argument);
					expectedValue = ListNotesContains;
				case "--external-contains":
					useCommandFlag(argument);
					expectedValue = ListExternalContains;
				case "--external-ref":
					useCommandFlag(argument);
					expectedValue = ListExternalRef;
				case "--priority-min":
					useCommandFlag(argument);
					expectedValue = IntegerValue(PriorityMinFlag, argument);
				case "--priority-max":
					useCommandFlag(argument);
					expectedValue = IntegerValue(PriorityMaxFlag, argument);
				case "--exclude-type":
					useCommandFlag(argument);
					expectedValue = ListExcludeType;
				case "--parent":
					useCommandFlag(argument);
					expectedValue = ListParent;
				case "--mol-type":
					useCommandFlag(argument);
					expectedValue = ListMoleculeType;
				case "--mol":
					useCommandFlag(argument);
					expectedValue = ReadyMolecule;
				case "--wisp-type":
					useCommandFlag(argument);
					expectedValue = ListWispType;
				case "--metadata-field":
					useCommandFlag(argument);
					expectedValue = ListMetadataField;
				case "--query":
					useCommandFlag(argument);
					expectedValue = SearchQuery;
				case "--parse-only":
					useCommandFlag(argument);
					queryParseOnly = true;
				case "--days" | "-d":
					// The pflag pass reads -d as --max-depth in `dep tree`.
					useCommandFlag(argument);
					expectedValue = IntegerValue(DaysFlag, argument);
				case "--max-depth":
					useCommandFlag(argument);
					expectedValue = IntegerValue(MaxDepthFlag, argument);
				case "--show-all-paths":
					// Deprecated upstream no-op: accepted and ignored.
					useCommandFlag(argument);
				case "--open" | "--dot" | "--html" | "--compact" | "--box":
					useCommandFlag(argument);
					graphViews.set(argument, true);
				case "--has-metadata-key":
					useCommandFlag(argument);
					expectedValue = ListHasMetadataKey;
				case "--created-after":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeCreatedAfter);
				case "--created-before":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeCreatedBefore);
				case "--updated-after":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeUpdatedAfter);
				case "--updated-before":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeUpdatedBefore);
				case "--closed-after":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeClosedAfter);
				case "--closed-before":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeClosedBefore);
				case "--defer-after":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeDeferAfter);
				case "--defer-before":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeDeferBefore);
				case "--due-after":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeDueAfter);
				case "--due-before":
					useCommandFlag(argument);
					expectedValue = ListTime(TimeDueBefore);
				case "--offset":
					useCommandFlag(argument);
					expectedValue = IntegerValue(OffsetFlag, argument);
				case "--max-rows":
					useCommandFlag(argument);
					expectedValue = IntegerValue(MaxRowsFlag, argument);
				case "--reverse" | "-r":
					useCommandFlag(argument);
					listReverse = true;
				case "--ready":
					useCommandFlag(argument);
					listReady = true;
				case "--no-assignee":
					useCommandFlag(argument);
					listNoAssignee = true;
				case "--no-labels":
					useCommandFlag(argument);
					listNoLabels = true;
				case "--empty-description":
					useCommandFlag(argument);
					listEmptyDescription = true;
				case "--skip-labels":
					useCommandFlag(argument);
					listSkipLabels = true;
				case "--brief":
					useCommandFlag(argument);
					listBrief = true;
				case "--pinned":
					useCommandFlag(argument);
					listPinned = true;
				case "--no-pinned":
					useCommandFlag(argument);
					listNoPinned = true;
				case "--include-templates":
					useCommandFlag(argument);
					listIncludeTemplates = true;
				case "--include-gates":
					useCommandFlag(argument);
					listIncludeGates = true;
				case "--include-infra":
					useCommandFlag(argument);
					listIncludeInfra = true;
				case "--no-parent":
					useCommandFlag(argument);
					listNoParent = true;
				case "--deferred":
					useCommandFlag(argument);
					listDeferred = true;
				case "--overdue":
					useCommandFlag(argument);
					listOverdue = true;
				case "--flat":
					useCommandFlag(argument);
					listFlat = true;
				case "--long":
					useCommandFlag(argument);
					listLong = true;
					showLong = true;
				case "--tree":
					useCommandFlag(argument);
					listTree = true;
				case "--pretty":
					useCommandFlag(argument);
					listPretty = true;
					listPrettyChanged = true;
				case "--plain":
					useCommandFlag(argument);
					readyPlain = true;
				case "--unassigned" | "-u":
					useCommandFlag(argument);
					readyUnassigned = true;
				case "--include-deferred":
					useCommandFlag(argument);
					readyIncludeDeferred = true;
				case "--include-ephemeral":
					useCommandFlag(argument);
					readyIncludeEphemeral = true;
				case "--claim":
					useCommandFlag(argument);
					readyClaim = true;
				case "--gated":
					useCommandFlag(argument);
					readyGated = true;
				case "--explain":
					useCommandFlag(argument);
					readyExplain = true;
				case "--details":
					useCommandFlag(argument);
					orphansDetails = true;
				case "--sections":
					useCommandFlag(argument);
					typesSections = true;
				case "--fix" | "-f":
					useCommandFlag(argument);
					orphansFix = true;
				case "--no-pager":
					useCommandFlag(argument);
					listNoPager = true;
				case "--deps":
					useCommandFlag(argument);
					listDepsMode = "scheduling";
				case "--direction":
					useCommandFlag(argument);
					depDirectionUsed = true;
					expectedValue = DepDirection;
				case "--source":
					useCommandFlag(argument);
					expectedValue = ConfigShowSource;
				case "--no-blocked":
					useCommandFlag(argument);
					statusSkipBlocked = true;
				case "--assigned":
					useCommandFlag(argument);
					statusAssigned = true;
				case "--short":
					useCommandFlag(argument);
					showShort = true;
				case "--current":
					useCommandFlag(argument);
					showCurrent = true;
				case "--watch" | "-w":
					useCommandFlag(argument);
					watchMode = true;
				case "--thread":
					useCommandFlag(argument);
					showThread = true;
				case "--refs":
					useCommandFlag(argument);
					showRefs = true;
				case "--children":
					useCommandFlag(argument);
					showChildren = true;
				case "--include-dependents":
					useCommandFlag(argument);
					showIncludeDependents = true;
				case "--include-comments":
					useCommandFlag(argument);
					showIncludeComments = true;
				case "--local-time":
					useCommandFlag(argument);
					commentsLocalTime = true;
				case "--events":
					useCommandFlag(argument);
					historyEvents = true;
				case "--since":
					useCommandFlag(argument);
					expectedValue = EventsSince;
				case "--before":
					useCommandFlag(argument);
					expectedValue = EventsBefore;
				case "--follow":
					useCommandFlag(argument);
					eventsFollow = true;
				case "--brief-deps":
					useCommandFlag(argument);
					showBriefDependencies = true;
				case "--all":
					useCommandFlag(argument);
					listAll = true;
				case "--no-activity":
					// Accepted compatibility flags; recent activity is currently absent.
				case "--readonly":
					// Strict read-only mode changes only how upstream opens a store that lacks its database.
					readonly = true;
				case "--ignore-schema-skew":
					ignoreSchemaSkew = true;
				case "--sandbox" | "--no-color" | "--quiet" | "-q" | "--verbose" | "-v":
					// This command profile is already read-only, unstyled, and synchronous.
				case "--version" | "-V":
					versionFlag = true;
					positional.push("version");
				case value if (value != "-" && StringTools.startsWith(value, "-")):
					final long = StringTools.startsWith(value, "--");
					final typed = long ? value.split("=")[0] : value.substr(0, 2);
					flagUses.push({typed: typed, argument: value, check: FlagFailure(unknownFlag(typed, value))});
					// Cobra's command search takes the next argument as the value of a flag that it does not know.
					if (value.indexOf("=") < 0 && (long || value.length == 2))
						expectedValue = UnknownFlagValue;
				case value:
					positional.push(value);
			}
		}
		// The last flag has no value after it.
		if (expectedValue != null)
			flagUses.push({typed: flagArgument, argument: flagArgument, check: FlagFailure(missingArgument(flagArgument))});

		// Cobra finds the command before pflag parses a flag, so an unknown command comes first.
		if (positional.length > 0 && !isCommandName(positional[0]))
			return UnknownCommand(positional[0]);
		// pflag then parses the flags with those of the command found, and stops at the first problem.
		function firstFlagFailure():Null<String> {
			final command = positional.length > 0 ? positional[0] : "";
			final depTree = command == "dep" && positional.length > 1 && positional[1] == "tree";
			for (use in flagUses)
				switch use.check {
					case CommandFlag:
						if (lacksCommandFlag(use.typed, positional))
							return unknownFlag(use.typed, use.argument);
					case RejectedValue(message) | FlagFailure(message):
						return message;
					// `events tail` and `export` declare --limit as an int64 flag without -n.
					case IntegerArgument(_, raw) if (command == "events"):
						switch PflagValue.parseInt64(use.typed, raw) {
							case Int64Rejected(message):
								return message;
							case Int64Accepted(value):
								eventsLimit = value;
						}
					case IntegerArgument(flag, raw):
						// -d is --max-depth in `dep tree` and --days elsewhere.
						final failure = applyIntegerValue(use.typed == "-d" && depTree ? MaxDepthFlag : flag, use.typed, raw);
						if (failure != null)
							return failure;
				}
			return null;
		}
		// The root command has no SilenceUsage: it prints its usage after a flag error.
		switch firstFlagFailure() {
			case null:
			case failure:
				return positional.length == 0 ? GroupUsageFailure(failure, Command.RootHelp) : UsageFailure(failure);
		}
		if (preRunFailure != null)
			return UsageFailure(preRunFailure);

		// Cobra reports the flag errors above before upstream's pre-run loads the selected
		// workspace's .beads/.env, which comes before any setting or variable is read below.
		final variableUse = positional.length > 0 && positional[0] == "where" ? BeforeWorkspace : WithoutWorkspace;
		final databaseVariable = environment.selectWorkspace({directory: directory, databasePath: databasePath}, variableUse);
		// A path from BEADS_DB or BD_DB selects the workspace from here on, as if --db had named it.
		switch databaseVariable {
			case VariablePath(_, path, _):
				databasePath = path;
			case NoVariable | UnsupportedPath(_):
		}

		// Upstream countGroupFlag: the --by-* flags that end up true, in its order.
		var countGroup = CountGroup.Ungrouped;
		var countGroupsSelected = 0;
		for (flag in ["--by-status", "--by-priority", "--by-type", "--by-assignee", "--by-label"])
			if (countGroupFlags.get(flag) == true) {
				countGroupsSelected++;
				switch countGroupFlag(flag) {
					case null:
					case group:
						countGroup = group;
				}
			}

		final formatJson = formatFlagSet && isJsonFormat(formatFlagValue);
		if (formatFlagSet && !formatJson)
			listFormat = formatFlagValue;
		var selectedOutput = OutputMode.Human;
		var outputSelected = false;
		// Upstream's JSON switch, decided once the first parsed command or command check needs it.
		// --version prints text before anything reads the switch, and --format json always selects
		// JSON. Otherwise the last --json value or a root --format decides; the --format of list and
		// dep tree is their own flag and does not count. Help prints text. Only then does the `json`
		// setting of the selected workspace's config apply.
		function outputMode():OutputMode {
			if (outputSelected)
				return selectedOutput;
			outputSelected = true;
			final ownFormat = positional.length > 0
				&& (positional[0] == "list" || (positional[0] == "dep" && positional.length > 1 && positional[1] == "tree"));
			final helpPage = showHelp || positional.length == 0 || positional[0] == "help";
			selectedOutput = if (versionFlag) {
				OutputMode.Human;
			} else if (formatJson || (jsonFlagSet && jsonFlagValue)) {
				OutputMode.Json;
			} else if (jsonFlagSet || (formatFlagSet && !ownFormat) || helpPage) {
				OutputMode.Human;
			} else if (jsonSetting.enabled({directory: directory, databasePath: databasePath})) {
				OutputMode.Json;
			} else {
				OutputMode.Human;
			}
			return selectedOutput;
		}

		// Cobra checks a command's arguments before the pre-run reads the switch or --format, so an
		// argument check that prints JSON (bd comments) follows the --json flag alone.
		final argumentCheckOutput = jsonFlagSet && jsonFlagValue ? OutputMode.Json : OutputMode.Human;

		function makeListRequest(idFilter:String):beadshx.store.IssueListRequest {
			return {
				status: listStatus,
				issueType: listIssueType,
				assignee: listAssignee,
				titleSearch: listTitle,
				specPrefix: listSpec,
				idFilter: idFilter,
				labels: listLabels,
				labelsAny: listLabelsAny,
				excludeLabels: listExcludeLabels,
				labelPattern: listLabelPattern,
				labelRegex: listLabelRegex,
				titleContains: listTitleContains,
				descriptionContains: listDescriptionContains,
				notesContains: listNotesContains,
				externalContains: listExternalContains,
				externalRef: listExternalRef,
				timeFilters: listTimeFilters,
				priority: listPriority,
				priorityMin: listPriorityMin,
				priorityMax: listPriorityMax,
				all: listAll,
				ready: listReady,
				noAssignee: listNoAssignee,
				noLabels: listNoLabels,
				emptyDescription: listEmptyDescription,
				skipLabels: listSkipLabels,
				brief: listBrief,
				pinned: listPinned,
				noPinned: listNoPinned,
				includeTemplates: listIncludeTemplates,
				includeGates: listIncludeGates,
				includeInfra: listIncludeInfra,
				excludeTypes: listExcludeTypes,
				parentId: listParent,
				noParent: listNoParent,
				moleculeType: listMoleculeType,
				wispType: listWispType,
				deferred: listDeferred,
				overdue: listOverdue,
				metadataFields: listMetadataFields,
				hasMetadataKey: listHasMetadataKey,
				format: outputMode() == OutputMode.Human ? listFormat : "",
				sortBy: listSort,
				reverse: listReverse,
				limit: listLimit,
				offset: listOffset,
				maxRows: listMaxRows,
				maxRowsSource: listMaxRowsSource,
				skipCounts: outputMode() == OutputMode.Human,
				blockingAnnotations: outputMode() == OutputMode.Human
				&& !(listPretty || watchMode || listDepsMode != "" || (listTree && !listFlat))
				&& !listLong};
		}

		function makeCountRequest(idFilter:String):beadshx.store.CountRequest {
			return {
				status: listStatus,
				issueType: listIssueType,
				assignee: listAssignee,
				priority: listPriority,
				priorityMin: listPriorityMin,
				priorityMax: listPriorityMax,
				labels: listLabels,
				labelsAny: listLabelsAny,
				titleSearch: listTitle,
				idFilter: idFilter,
				titleContains: listTitleContains,
				descriptionContains: listDescriptionContains,
				notesContains: listNotesContains,
				timeFilters: listTimeFilters,
				emptyDescription: listEmptyDescription,
				noAssignee: listNoAssignee,
				noLabels: listNoLabels,
				includeInfra: listIncludeInfra
			};
		}

		function makeReadyRequest():beadshx.store.ReadyRequest {
			final sort = switch listSort {
				case "hybrid": ReadySort.Hybrid;
				case "oldest": ReadySort.Oldest;
				case _: ReadySort.Priority;
			};
			return {
				issueType: listIssueType,
				assignee: listAssignee,
				unassigned: readyUnassigned,
				labels: listLabels,
				labelsAny: listLabelsAny,
				excludeLabels: listExcludeLabels,
				labelPattern: listLabelPattern,
				labelRegex: listLabelRegex,
				priority: listPriority,
				parentId: listParent,
				moleculeType: listMoleculeType,
				includeDeferred: readyIncludeDeferred,
				includeEphemeral: readyIncludeEphemeral,
				excludeTypes: listExcludeTypes,
				metadataFields: listMetadataFields,
				hasMetadataKey: listHasMetadataKey,
				sort: sort,
				limit: listLimit,
				offset: listOffset,
				brief: listBrief,
				maxRows: listMaxRows,
				maxRowsSource: listMaxRowsSource
			};
		}

		function makeDepTreeInvocation():DepTreeInvocation {
			// Upstream applies --reverse only when --direction is empty.
			final explicitDirection = depDirectionUsed ? depDirection : "";
			return {
				root: positional.length > 2 ? positional[2] : "",
				direction: explicitDirection != "" ? explicitDirection : (listReverse ? "up" : "down"),
				maxDepth: depTreeMaxDepth,
				status: listStatus,
				format: listFormat,
				maxRows: listMaxRows,
				maxRowsSource: listMaxRowsSource,
				maxRowsWarning: deferredMaxRowsWarning
			};
		}

		function makeHistoryInvocation():HistoryInvocation {
			return {
				issueId: positional.length > 1 && positional[0] == "history" ? positional[1] : "",
				limit: switch listLimit {
					case IntAbsent: 0;
					case IntPresent(value): value;
				},
				events: historyEvents
			};
		}

		function makeEventsInvocation():EventsInvocation {
			return {since: eventsSince, limit: eventsLimit};
		}

		function makeCommentsInvocation():CommentsInvocation {
			final misplacedList = positional.length > 1 && positional[0] == "comments" && positional[1] == "list";
			return {
				issueId: positional.length > 1 && !misplacedList ? positional[1] : "",
				misplacedList: misplacedList,
				localTime: commentsLocalTime
			};
		}

		function makeGraphInvocation():GraphInvocation {
			var view = "";
			// Upstream renders --all in another branch, where --html outranks --dot.
			final order = listAll ? ["--open", "--html", "--dot", "--compact", "--box"] : ["--open", "--dot", "--html", "--compact", "--box"];
			for (flag in order)
				if (view == "" && graphViews.get(flag) == true)
					view = flag;
			return {
				ids: positional.length > 1 ? positional.slice(1) : [],
				all: listAll,
				view: view,
				maxRows: listMaxRows,
				maxRowsSource: listMaxRowsSource,
				maxRowsWarning: deferredMaxRowsWarning
			};
		}

		if (positional.length == 0 || (positional.length == 1 && positional[0] == "help")) {
			return Parsed({
				command: Command.RootHelp,
				output: outputMode(),
				actor: actor,
				directory: directory,
				databasePath: databasePath,
				databaseVariable: databaseVariable,
				databaseName: databaseName,
				global: global,
				readonly: readonly,
				ignoreSchemaSkew: ignoreSchemaSkew,
				cpuProfile: cpuProfile,
				memProfilePath: memProfilePath,
				showHelp: showHelp,
				helpCommand: false,
				infoSchema: infoSchema,
				infoWhatsNew: infoWhatsNew,
				statusSkipBlocked: statusSkipBlocked,
				statusAssigned: statusAssigned,
				countRequest: makeCountRequest(""),
				countGroup: countGroup,
				readyRequest: makeReadyRequest(),
				readyPretty: listPrettyChanged ? listPretty : true,
				readyPlain: readyPlain,
				readyClaim: readyClaim,
				readyGated: readyGated,
				readyMolecule: readyMolecule,
				readyExplain: readyExplain,
				searchQuery: searchQueryFlag,
				queryRequest: {
					expression: "",
					provided: false,
					includeClosed: listAll,
					sortBy: listSort,
					reverse: listReverse,
					limit: 50,
					offset: 0,
					longFormat: listLong,
					parseOnly: queryParseOnly
				},
				staleRequest: {
					days: staleDays,
					status: listStatus,
					limit: switch listLimit {
						case IntAbsent: 50;
						case IntPresent(value): value;
					}
				},
				orphansDetails: orphansDetails,
				orphansFix: orphansFix,
				listRequest: makeListRequest(""),
				listWarning: listWarning,
				deferredCheck: deferredCheck,
				readyModeCheck: readyModeCheck,
				maxRowsCheck: maxRowsCheck,
				readyFilterCheck: readyFilterCheck,
				listFlat: !(listPretty || watchMode || listDepsMode != "" || (listTree && !listFlat)),
				listLong: listLong,
				listNoPager: listNoPager,
				listDepsMode: listDepsMode,
				listAgentMode: environment.value("BD_AGENT_MODE") == "1" || environment.value("CLAUDE_CODE") != "",
				showShort: showShort,
				showLong: showLong,
				showCurrent: showCurrent,
				watchMode: watchMode,
				showThread: showThread,
				showRefs: showRefs,
				showChildren: showChildren,
				showIncludeDependents: showIncludeDependents,
				showIncludeComments: showIncludeComments,
				showBriefDependencies: showBriefDependencies,
				showIds: showIds,
				depType: depTypeRaw,
				depListSelection: selectDepList(depDirection, showIds.length),
				depTree: makeDepTreeInvocation(),
				graph: makeGraphInvocation(),
				comments: makeCommentsInvocation(),
				history: makeHistoryInvocation(),
				events: makeEventsInvocation(),
				typesSections: typesSections,
				configKey: "",
				configSource: configSource
			});
		}
		var helpCommand = false;
		if (positional[0] == "help") {
			positional.shift();
			showHelp = true;
			helpCommand = true;
		}
		final name = positional[0];
		final depCycles = name == "dep" && positional.length > 1 && positional[1] == "cycles";
		final depTree = name == "dep" && positional.length > 1 && positional[1] == "tree";
		// Upstream `bd graph check` takes any arguments and ignores them.
		final graphCheck = name == "graph" && positional.length > 1 && positional[1] == "check";
		final graphView = name == "graph" && !graphCheck;
		if (name == "dep" && !depCycles && !depTree) {
			if (positional.length < 2) {
				if (!showHelp)
					return UsageFailure("dep requires the read-only subcommand 'list', 'cycles' or 'tree'");
			} else if (positional[1] != "list") {
				return UsageFailure("dep requires the read-only subcommand 'list', 'cycles' or 'tree'");
			} else if (!showHelp && positional.length < 3) {
				return UsageFailure("requires at least 1 arg(s), only received 0");
			}
			showIds = positional.length > 2 ? positional.slice(2) : [];
		}
		if (name == "children" && !showHelp) {
			final received = positional.length - 1;
			if (received != 1)
				return UsageFailure('accepts 1 arg(s), received ${received}');
			listParent = positional[1];
			listAll = true;
		}
		if (shorthandS != "") {
			if (name == "ready")
				listSort = shorthandS;
			else
				listStatus = shorthandS;
		}
		// The filter values that upstream checks in the command body. Each command reports a failure in its own order.
		// list and search read --priority-min and --priority-max as strings; count takes them as int flags, above.
		var priorityMinFailure = "";
		if (listPriorityMinRaw != null) {
			final priority = goPriority(listPriorityMinRaw);
			if (priority < 0)
				priorityMinFailure = 'parsing --priority-min: ${invalidPriority(listPriorityMinRaw)}';
			else
				listPriorityMin = IntPresent(priority);
		}
		var priorityMaxFailure = "";
		if (listPriorityMaxRaw != null) {
			final priority = goPriority(listPriorityMaxRaw);
			if (priority < 0)
				priorityMaxFailure = 'parsing --priority-max: ${invalidPriority(listPriorityMaxRaw)}';
			else
				listPriorityMax = IntPresent(priority);
		}
		var moleculeTypeFailure = "";
		if (listMoleculeTypeRaw != "") {
			if (isMoleculeType(listMoleculeTypeRaw))
				listMoleculeType = listMoleculeTypeRaw;
			else
				moleculeTypeFailure = 'invalid mol-type ${goQuote(listMoleculeTypeRaw)} (must be swarm, patrol, or work)';
		}
		var wispTypeFailure = "";
		if (listWispTypeRaw != "") {
			if (isWispType(listWispTypeRaw))
				listWispType = listWispTypeRaw;
			else
				wispTypeFailure = 'invalid wisp-type ${goQuote(listWispTypeRaw)} (must be heartbeat, ping, patrol, gc_report, recovery, error, or escalation)';
		}
		// Upstream parses the date filters in this order and stops at the first that fails.
		var timeFailure = "";
		for (field in [
			TimeCreatedAfter,
			TimeCreatedBefore,
			TimeUpdatedAfter,
			TimeUpdatedBefore,
			TimeClosedAfter,
			TimeClosedBefore,
			TimeDeferAfter,
			TimeDeferBefore,
			TimeDueAfter,
			TimeDueBefore
		]) {
			final raw = listTimeRaw.get(listTimeFlag(field));
			if (timeFailure != "" || raw == null || raw == "")
				continue;
			final timeError = addListTimeFilter(listTimeFilters, field, raw);
			if (timeError != null)
				timeFailure = timeError;
		}
		var metadataFieldFailure = "";
		for (raw in listMetadataFieldsRaw) {
			final metadataError = addMetadataFilter(listMetadataFields, raw);
			if (metadataError != null) {
				metadataFieldFailure = metadataError;
				break;
			}
		}
		var hasMetadataKeyFailure = "";
		if (listHasMetadataKeyRaw != "") {
			final metadataError = validateMetadataKey("--has-metadata-key", listHasMetadataKeyRaw);
			if (metadataError != null)
				hasMetadataKeyFailure = metadataError;
			else
				listHasMetadataKey = listHasMetadataKeyRaw;
		}
		// Upstream resolveMaxRowsEnvOnly reads BEADS_MAX_ROWS with strconv.Atoi. Any other value, or a
		// negative one, sets no cap; the warning that it prints is returned.
		function readMaxRowsVariable():String {
			final raw = environment.value("BEADS_MAX_ROWS");
			if (raw == "")
				return "";
			final parsed = PflagValue.goAtoi(raw);
			if (parsed == null || parsed < 0)
				return 'Warning: BEADS_MAX_ROWS=${goQuote(raw)} is not a non-negative integer; ignoring.\n';
			listMaxRows = IntPresent(parsed);
			listMaxRowsSource = "BEADS_MAX_ROWS";
			return "";
		}
		// Upstream resolveMaxRows: a --max-rows value wins; otherwise a malformed BEADS_MAX_ROWS warns and sets no cap.
		function resolveMaxRows():Void {
			switch listMaxRows {
				case IntPresent(value) if (value < 0):
					maxRowsCheck = OutputCheckFailure('--max-rows must be non-negative; got ${value}');
				case IntPresent(_):
				case IntAbsent:
					final warning = readMaxRowsVariable();
					if (warning != "")
						listWarning = warning;
			}
		}
		final eventsSubcommand = name == "events" && positional.length > 1 ? positional[1] : "";
		if (depTree && !showHelp && positional.length != 3)
			return UsageFailure('accepts 1 arg(s), received ${positional.length - 2}');
		if (graphView && !showHelp && positional.length > 2)
			return UsageFailure('accepts between 0 and 1 arg(s), received ${positional.length - 1}');
		if ((depTree || graphView) && !showHelp) {
			switch listMaxRows {
				case IntPresent(_):
				case IntAbsent:
					final warning = readMaxRowsVariable();
					if (warning != "")
						deferredMaxRowsWarning = warning;
			}
		}
		if (name == "list") {
			// Upstream gatherListInput, in its order.
			if (listSkipLabels) {
				final conflicts = skipLabelsConflicts(listLabels, listLabelsAny, listLabelPattern, listLabelRegex, listExcludeLabels, listNoLabels);
				if (conflicts.length > 0)
					deferCheck(ExactCheckFailure(formatSkipLabelsConflict(conflicts), 2));
			}
			if (listPriorityRaw != null) {
				final priority = goPriority(listPriorityRaw);
				if (priority < 0)
					deferCheck(PlainCheckFailure(invalidPriority(listPriorityRaw)));
				else
					listPriority = IntPresent(priority);
			}
			if (priorityMinFailure != "")
				deferCheck(PlainCheckFailure(priorityMinFailure));
			if (priorityMaxFailure != "")
				deferCheck(PlainCheckFailure(priorityMaxFailure));
			if (listPinned && listNoPinned)
				deferCheck(PlainCheckFailure("--pinned and --no-pinned are mutually exclusive"));
			if (listParent != "" && listNoParent)
				deferCheck(PlainCheckFailure("--parent and --no-parent are mutually exclusive"));
			if (moleculeTypeFailure != "")
				deferCheck(PlainCheckFailure(moleculeTypeFailure));
			if (wispTypeFailure != "")
				deferCheck(PlainCheckFailure(wispTypeFailure));
			if (timeFailure != "")
				deferCheck(PlainCheckFailure(timeFailure));
			if (metadataFieldFailure != "")
				deferCheck(OutputCheckFailure(metadataFieldFailure));
			if (hasMetadataKeyFailure != "")
				deferCheck(OutputCheckFailure(hasMetadataKeyFailure));
			if (listBrief) {
				// Upstream's pretty view: the tree unless --flat, outside --json and --format, and always with --watch.
				final pretty = ((listPretty || (listTree && !listFlat))
					&& outputMode() != OutputMode.Json
					&& listFormat == "")
					|| watchMode;
				if (watchMode)
					deferCheck(PlainCheckFailure("--watch cannot be combined with --brief"));
				else if (listFormat != "")
					deferCheck(PlainCheckFailure("--format cannot be combined with --brief; a template can print a field --brief omits, with nothing to mark it"));
				else if (listParent != "" && pretty)
					deferCheck(PlainCheckFailure("--parent with --pretty cannot be combined with --brief; the hierarchical walk is a different query"));
			}
			if (listDepsMode != "") {
				if (listDepsMode != "scheduling" && listDepsMode != "all")
					deferCheck(OutputCheckFailure('invalid --deps value "${listDepsMode}" (valid: scheduling, all)'));
				if (outputMode() == OutputMode.Json)
					deferCheck(OutputCheckFailure("--deps is not supported with --json output"));
				if (listFormat != "")
					deferCheck(OutputCheckFailure("--deps is not supported with --format output"));
				if (listFlat)
					deferCheck(OutputCheckFailure("--deps requires the tree view and cannot be combined with --flat"));
				if (watchMode)
					deferCheck(OutputCheckFailure("--deps is not supported with --watch"));
			}
			if (listSort != "" && !isListSort(listSort))
				deferCheck(PlainCheckFailure(invalidListSort(listSort)));
			switch listOffset {
				case IntPresent(value) if (value < 0):
					deferCheck(PlainCheckFailure("--offset must be >= 0"));
				case IntPresent(value) if (value > 0 && listSort == "id"):
					deferCheck(PlainCheckFailure("--offset is not supported with --sort id (sort requires fetching the full result set)"));
				case IntAbsent | IntPresent(_):
			}
			// Then upstream reads --max-rows and BEADS_MAX_ROWS (the command reports them after the checks above).
			if (!showHelp)
				resolveMaxRows();
		}
		if (name == "ready") {
			// Upstream briefModeConflict, which the command body checks before it picks a route or a view.
			if (listBrief) {
				final conflict = if (readyClaim) {
					"--claim cannot be combined with --brief";
				} else if (readyGated) {
					"--gated cannot be combined with --brief";
				} else if (readyMolecule != "") {
					"--mol cannot be combined with --brief";
				} else if (readyExplain) {
					"--explain cannot be combined with --brief";
				} else if (outputMode() != OutputMode.Json) {
					"--brief requires --json; the text renderings print none of the fields it omits";
				} else {
					"";
				}
				if (conflict != "")
					readyModeCheck = OutputCheckFailure(conflict);
			}
			// Upstream gatherReadyInput, in its order, up to where it reads --max-rows and BEADS_MAX_ROWS.
			if (moleculeTypeFailure != "")
				deferCheck(OutputCheckFailure(moleculeTypeFailure));
			if (readyClaim && listAssignee != "")
				deferCheck(OutputCheckFailure("--claim cannot be combined with --assignee"));
			if (readyClaim && readyGated)
				deferCheck(OutputCheckFailure("--claim cannot be combined with --gated"));
			if (readyClaim && readyMolecule != "")
				deferCheck(OutputCheckFailure("--claim cannot be combined with --mol"));
			if (readyClaim && readyExplain)
				deferCheck(OutputCheckFailure("--claim cannot be combined with --explain"));
			final positiveOffset = switch listOffset {
				case IntPresent(value): value > 0;
				case IntAbsent: false;
			};
			if (positiveOffset && readyClaim)
				deferCheck(OutputCheckFailure("--offset cannot be combined with --claim"));
			if (positiveOffset && readyGated)
				deferCheck(OutputCheckFailure("--offset cannot be combined with --gated"));
			if (positiveOffset && readyMolecule != "")
				deferCheck(OutputCheckFailure("--offset cannot be combined with --mol"));
			if (positiveOffset && readyExplain)
				deferCheck(OutputCheckFailure("--offset cannot be combined with --explain"));
			if (!showHelp)
				resolveMaxRows();
			if (metadataFieldFailure != "")
				deferFilterCheck(OutputCheckFailure(metadataFieldFailure));
			if (hasMetadataKeyFailure != "")
				deferFilterCheck(OutputCheckFailure(hasMetadataKeyFailure));
			if (listSort != "" && !isReadySort(listSort))
				deferFilterCheck(OutputCheckFailure('invalid sort policy \'${listSort}\'. Valid values: hybrid, priority, oldest'));
		}
		if (name == "count") {
			// Upstream parseCountRequest, in its order.
			if (countGroupsSelected > 1)
				deferCheck(OutputCheckFailure("only one --by-* flag can be specified"));
			if (timeFailure != "")
				deferCheck(OutputCheckFailure(timeFailure));
		}
		if (name == "search") {
			// Upstream search's command body, in its order, after it checks --status. It takes any --sort value.
			if (timeFailure != "")
				deferCheck(PlainCheckFailure(timeFailure));
			if (priorityMinFailure != "")
				deferCheck(PlainCheckFailure(priorityMinFailure));
			if (priorityMaxFailure != "")
				deferCheck(PlainCheckFailure(priorityMaxFailure));
			if (metadataFieldFailure != "")
				deferCheck(PlainCheckFailure(metadataFieldFailure));
			if (hasMetadataKeyFailure != "")
				deferCheck(PlainCheckFailure(hasMetadataKeyFailure));
			switch listLimit {
				case IntAbsent:
					listLimit = IntPresent(50);
				case IntPresent(_):
			}
		}
		if (name == "query") {
			switch listLimit {
				case IntAbsent:
					listLimit = IntPresent(50);
				case IntPresent(_):
			}
			// Upstream gatherQueryInput asks for the expression first; the command checks that.
			switch listOffset {
				case IntPresent(value) if (value < 0):
					deferCheck(OutputCheckFailure("--offset must be non-negative"));
				case IntAbsent | IntPresent(_):
			}
		}
		if (name == "stale") {
			switch listLimit {
				case IntAbsent:
					listLimit = IntPresent(50);
				case IntPresent(_):
			}
		}
		if (name == "show" || name == "view") {
			showIds = positional.slice(1);
			for (id in issueFlagIds)
				showIds.push(id);
		}
		final listIdFilter = name == "list" && issueFlagIds.length > 0 ? issueFlagIds[issueFlagIds.length - 1] : "";
		final countIdFilter = name == "count" && issueFlagIds.length > 0 ? issueFlagIds[issueFlagIds.length - 1] : "";

		function parsedCommand(command:Command):ParseResult {
			final queryLimit = switch listLimit {
				case IntPresent(value): value;
				case IntAbsent: 50;
			};
			final queryOffset = switch listOffset {
				case IntPresent(value): value;
				case IntAbsent: 0;
			};
			return Parsed({
				command: command,
				// The snapshot is JSON Lines in every mode, and its errors never reach stdout.
				output: command == Command.Snapshot ? OutputMode.Human : outputMode(),
				actor: actor,
				directory: directory,
				databasePath: databasePath,
				databaseVariable: databaseVariable,
				databaseName: databaseName,
				global: global,
				readonly: readonly,
				ignoreSchemaSkew: ignoreSchemaSkew,
				cpuProfile: cpuProfile,
				memProfilePath: memProfilePath,
				showHelp: showHelp,
				helpCommand: helpCommand,
				infoSchema: infoSchema,
				infoWhatsNew: infoWhatsNew,
				statusSkipBlocked: statusSkipBlocked,
				statusAssigned: statusAssigned,
				countRequest: makeCountRequest(countIdFilter),
				countGroup: countGroup,
				readyRequest: makeReadyRequest(),
				readyPretty: listPrettyChanged ? listPretty : true,
				readyPlain: readyPlain,
				readyClaim: readyClaim,
				readyGated: readyGated,
				readyMolecule: readyMolecule,
				readyExplain: readyExplain,
				searchQuery: positional.length > 1 ? positional.slice(1).join(" ") : searchQueryFlag,
				queryRequest: {
					expression: positional.length > 1 ? positional.slice(1).join(" ") : "",
					provided: positional.length > 1,
					includeClosed: listAll,
					sortBy: listSort,
					reverse: listReverse,
					limit: queryLimit,
					offset: queryOffset,
					longFormat: listLong,
					parseOnly: queryParseOnly
				},
				staleRequest: {
					days: staleDays,
					status: listStatus,
					limit: switch listLimit {
						case IntAbsent: 50;
						case IntPresent(value): value;
					}
				},
				orphansDetails: orphansDetails,
				orphansFix: orphansFix,
				listRequest: makeListRequest(listIdFilter),
				listWarning: listWarning,
				deferredCheck: deferredCheck,
				readyModeCheck: readyModeCheck,
				maxRowsCheck: maxRowsCheck,
				readyFilterCheck: readyFilterCheck,
				listFlat: !(listPretty || watchMode || listDepsMode != "" || (listTree && !listFlat)),
				listLong: listLong,
				listNoPager: listNoPager,
				listDepsMode: listDepsMode,
				listAgentMode: environment.value("BD_AGENT_MODE") == "1" || environment.value("CLAUDE_CODE") != "",
				showShort: showShort,
				showLong: showLong,
				showCurrent: showCurrent,
				watchMode: watchMode,
				showThread: showThread,
				showRefs: showRefs,
				showChildren: showChildren,
				showIncludeDependents: showIncludeDependents,
				showIncludeComments: showIncludeComments,
				showBriefDependencies: showBriefDependencies,
				showIds: showIds,
				depType: depTypeRaw,
				depListSelection: selectDepList(depDirection, showIds.length),
				depTree: makeDepTreeInvocation(),
				graph: makeGraphInvocation(),
				comments: makeCommentsInvocation(),
				history: makeHistoryInvocation(),
				events: makeEventsInvocation(),
				typesSections: typesSections,
				configKey: name == "config" && positional.length > 2 ? positional[2] : "",
				configSource: configSource
			});
		}
		if (name == "version")
			return parsedCommand(Command.Version);
		if (name == "where")
			return parsedCommand(Command.Where);
		if (name == "info")
			return parsedCommand(Command.Info);
		if (name == "ping")
			return parsedCommand(Command.Ping);
		if (name == "status" || name == "stats")
			return parsedCommand(Command.Status);
		if (name == "count")
			return parsedCommand(Command.Count);
		if (name == "ready")
			return parsedCommand(Command.Ready);
		if (name == "search")
			return parsedCommand(Command.Search);
		if (name == "query")
			return parsedCommand(Command.Query);
		if (name == "stale")
			return parsedCommand(Command.Stale);
		if (name == "orphans")
			return parsedCommand(Command.Orphans);
		if (name == "children")
			return parsedCommand(Command.Children);
		if (name == "dep")
			return parsedCommand(depCycles ? Command.DepCycles : (depTree ? Command.DepTree : Command.DepList));
		if (name == "blocked")
			return parsedCommand(Command.Blocked);
		if (name == "types")
			return parsedCommand(Command.Types);
		if (name == "statuses")
			return parsedCommand(Command.Statuses);
		if (graphCheck)
			return parsedCommand(Command.GraphCheck);
		if (graphView)
			return parsedCommand(Command.Graph);
		if (name == "comments") {
			final subcommand = positional.length > 1 ? positional[1] : "";
			if (subcommand == "add")
				return UsageFailure("comments add is not available yet in this build");
			// Upstream checks the arguments before it opens the store; `list` is a subcommand.
			if (!showHelp && subcommand != "list" && positional.length != 2) {
				if (positional.length < 2)
					return UsageFailure("requires at least 1 arg(s), only received 0");
				return OutputFailure(argumentCheckOutput, positional[2] == "add" ? misplacedCommentsAdd(subcommand) : COMMENTS_TAKES_ONE_ID);
			}
			return parsedCommand(Command.Comments);
		}
		if (name == "label") {
			final subcommand = positional.length > 1 ? positional[1] : "";
			switch subcommand {
				case "add" | "remove" | "propagate":
					return UsageFailure('label ${subcommand} is not available yet in this build');
				case "list":
					if (!showHelp && positional.length != 3)
						return UsageFailure('accepts 1 arg(s), received ${positional.length - 2}');
					showIds = positional.slice(2);
					return parsedCommand(Command.LabelList);
				// Upstream list-all accepts and ignores extra arguments.
				case "list-all":
					return parsedCommand(Command.LabelListAll);
				// With no subcommand or an unknown one, upstream prints the group help.
				case _:
					return parsedCommand(Command.Label);
			}
		}
		if (name == "events") {
			switch eventsSubcommand {
				case "prune":
					return UsageFailure("events prune is not available yet in this build");
				case "tail":
					if (eventsFollow && !showHelp)
						return UsageFailure("events tail --follow is not available yet in this build");
					return parsedCommand(Command.EventsTail);
				// Upstream tail and export accept and ignore extra arguments.
				case "export":
					return parsedCommand(Command.EventsExport);
				// With no subcommand or an unknown one, upstream prints the group help.
				case _:
					return parsedCommand(Command.Events);
			}
		}
		if (name == "config") {
			final subcommand = positional.length > 1 ? positional[1] : "";
			switch subcommand {
				case "get":
					if (!showHelp && positional.length != 3)
						return UsageFailure('accepts 1 arg(s), received ${positional.length - 2}');
					return parsedCommand(Command.ConfigGet);
				// Upstream list accepts and ignores extra arguments.
				case "list":
					return parsedCommand(Command.ConfigList);
				// Upstream show accepts and ignores extra arguments.
				case "show":
					return parsedCommand(Command.ConfigShow);
				// Upstream validate and drift accept and ignore extra arguments.
				case "validate":
					return parsedCommand(Command.ConfigValidate);
				case "drift":
					return parsedCommand(Command.ConfigDrift);
				case "set" | "set-many" | "unset" | "apply":
					return UsageFailure('config ${subcommand} is not available yet in this build');
				// With no subcommand or an unknown one, upstream prints the group help.
				case _:
					return parsedCommand(Command.Config);
			}
		}
		if (name == "history") {
			if (!showHelp && positional.length != 2)
				return UsageFailure('accepts 1 arg(s), received ${positional.length - 1}');
			return parsedCommand(Command.History);
		}
		if (name == "list") {
			// Upstream listCmd's cobra Args, which run after flag parsing and --help but before the pre-run.
			if (!showHelp && positional.length > 1)
				return UsageFailure(listArgumentsRefusal(positional.slice(1)));
			return parsedCommand(Command.List);
		}
		if (name == "show" || name == "view")
			return parsedCommand(Command.Show);
		// The hidden BeadsHX snapshot extension takes no argument (cobra.NoArgs).
		if (name == "snapshot") {
			if (!showHelp && positional.length > 1)
				return UsageFailure('unknown command "${positional[1]}" for "bd snapshot"');
			return parsedCommand(Command.Snapshot);
		}
		return helpCommand ? UsageFailure('unknown command "${name}"') : UnknownCommand(name);
	}

	/**
		Upstream listCmd's Args: the first argument that names a list flag
		(upstream knownListFlags) gets a hint, and other arguments the general
		refusal.
	**/
	static function listArgumentsRefusal(arguments:Array<String>):String {
		for (argument in arguments)
			switch argument {
				case "ready" | "tree" | "flat" | "all" | "long" | "watch" | "pretty" | "pinned" | "overdue":
					return 'unknown argument "${argument}"; did you mean "--${argument}" or \'bd ${argument}\'?';
				case _:
			}
		return "bd list does not accept positional arguments; use flags instead (see bd list --help)";
	}

	/** Upstream validateCommentsArgs for `bd comments <id> add ...`. */
	static function misplacedCommentsAdd(issueId:String):String {
		return '"bd comments <issue-id> add ..." is not valid — the subcommand must come first.\n\n'
			+ 'To add a comment, run:\n  bd comments add <issue-id> <text>\n\n'
			+ 'Example:\n  bd comments add ${issueId} "your comment"\n\nSee: bd comments --help';
	}

	static function isBooleanFlagValue(value:String):Bool {
		return switch value {
			case "1" | "t" | "T" | "true" | "TRUE" | "True" | "0" | "f" | "F" | "false" | "FALSE" | "False": true;
			case _: false;
		};
	}

	static function isListBooleanFlag(flag:String):Bool {
		return switch flag {
			case "--all" | "--reverse" | "--ready" | "--no-assignee" | "--no-labels" | "--empty-description" | "--skip-labels" | "--brief" | "--pinned" |
				"--no-pinned" | "--include-templates" | "--include-gates" | "--include-infra" | "--no-parent" | "--deferred" | "--overdue" | "--flat" |
				"--long" | "--tree" | "--pretty" | "--no-pager" | "--plain" | "--unassigned" | "--include-deferred" | "--include-ephemeral" | "--claim" |
				"--gated" | "--explain" | "--parse-only": true;
			case _: false;
		};
	}

	static function countGroupFlag(flag:String):Null<CountGroup> {
		return switch flag {
			case "--by-status": CountGroup.ByStatus;
			case "--by-priority": CountGroup.ByPriority;
			case "--by-type": CountGroup.ByType;
			case "--by-assignee": CountGroup.ByAssignee;
			case "--by-label": CountGroup.ByLabel;
			case _: null;
		};
	}

	static function isCountFilterFlag(flag:String):Bool {
		return switch flag {
			case "--status" | "-s" | "--priority" | "-p" | "--assignee" | "-a" | "--type" | "-t" | "--label" | "-l" | "--label-any" | "--title" | "--id" |
				"--title-contains" | "--desc-contains" | "--notes-contains" | "--created-after" | "--created-before" | "--updated-after" |
				"--updated-before" | "--closed-after" | "--closed-before" | "--empty-description" | "--no-assignee" | "--no-labels" | "--priority-min" |
				"--priority-max" | "--include-infra": true;
			case _: false;
		};
	}

	/** The flags of ready that list does not have. */
	static function isReadyOnlyFlag(flag:String):Bool {
		return switch flag {
			case "--mol" | "--plain" | "--unassigned" | "-u" | "--include-deferred" | "--include-ephemeral" | "--claim" | "--gated" | "--explain": true;
			case _: false;
		};
	}

	static function isReadyFilterFlag(flag:String):Bool {
		return switch flag {
			case "--assignee" | "-a" | "--priority" | "-p" | "--sort" | "-s" | "--type" | "-t" | "--label" | "-l" | "--label-any" | "--exclude-label" |
				"--label-pattern" | "--label-regex" | "--limit" | "-n" | "--parent" | "--mol-type" | "--exclude-type" | "--metadata-field" |
				"--has-metadata-key" | "--offset" | "--max-rows" | "--brief" | "--pretty" | "--plain" | "--unassigned" | "-u" | "--include-deferred" |
				"--include-ephemeral" | "--claim" | "--gated" | "--mol" | "--explain": true;
			case _: false;
		};
	}

	static function isSearchFilterFlag(flag:String):Bool {
		return switch flag {
			case "--status" | "-s" | "--assignee" | "-a" | "--type" | "-t" | "--label" | "-l" | "--label-any" | "--limit" | "-n" | "--long" | "--sort" |
				"--reverse" | "-r" | "--created-after" | "--created-before" | "--updated-after" | "--updated-before" | "--closed-after" | "--closed-before" |
				"--priority-min" | "--priority-max" | "--desc-contains" | "--notes-contains" | "--external-contains" | "--empty-description" |
				"--no-assignee" | "--no-labels" | "--metadata-field" | "--has-metadata-key": true;
			case _: false;
		};
	}

	static function isQueryFilterFlag(flag:String):Bool {
		return switch flag {
			case "--all" | "-a" | "--limit" | "-n" | "--long" | "--offset" | "--reverse" | "-r" | "--sort" | "--parse-only": true;
			case _: false;
		};
	}

	static function isStaleFilterFlag(flag:String):Bool {
		return switch flag {
			case "--status" | "-s" | "--limit" | "-n": true;
			case _: false;
		};
	}

	static function isGraphViewFlag(flag:String):Bool {
		return flag == "--open" || flag == "--dot" || flag == "--html" || flag == "--compact" || flag == "--box";
	}

	static function isDepTreeFilterFlag(flag:String):Bool {
		return flag == "--status" || flag == "--reverse" || flag == "--max-rows";
	}

	/**
		pflag's name for an int flag of the command in `path`: `-s, --name` when the
		flag has a shorthand. Null when the command has no such int flag, and when
		`typed` is a shorthand that its flag lacks.
	**/
	static function integerFlagName(flag:IntegerFlag, typed:String, path:Array<String>):Null<String> {
		final command = path.length > 0 ? path[0] : "";
		final subcommand = path.length > 1 ? path[1] : "";
		final name:Null<String> = switch [flag, command] {
			case [LimitFlag, "list" | "ready" | "search" | "query" | "stale"]: "-n, --limit";
			// `bd history` declares --limit without the -n shorthand.
			case [LimitFlag, "history"]: "--limit";
			case [OffsetFlag, "list" | "ready" | "query"]: "--offset";
			case [MaxRowsFlag, "list" | "ready"]: "--max-rows";
			case [MaxRowsFlag, "graph"] if (subcommand != "check"): "--max-rows";
			case [MaxRowsFlag, "dep"] if (subcommand == "tree"): "--max-rows";
			case [PriorityFlag, "ready" | "count"]: "-p, --priority";
			case [PriorityMinFlag, "count"]: "--priority-min";
			case [PriorityMaxFlag, "count"]: "--priority-max";
			case [DaysFlag, "stale"]: "-d, --days";
			case [MaxDepthFlag, "dep"] if (subcommand == "tree"): "-d, --max-depth";
			case _: null;
		};
		if (name == null || (!StringTools.startsWith(typed, "--") && !StringTools.startsWith(name, typed + ",")))
			return null;
		return name;
	}

	/** pflag's error for a flag, as typed, that has no value after it. */
	static function missingArgument(typed:String):String {
		return StringTools.startsWith(typed, "--") ? 'flag needs an argument: ${typed}' : 'flag needs an argument: \'${typed.charAt(1)}\' in ${typed}';
	}

	/**
		pflag's error for a flag, as typed, that the command does not have. A
		shorthand error quotes the whole `argument`, such as `-n5`.
	**/
	static function unknownFlag(typed:String, argument:String):String {
		return StringTools.startsWith(typed, "--") ? 'unknown flag: ${typed}' : 'unknown shorthand flag: \'${typed.charAt(1)}\' in ${argument}';
	}

	/** The commands of this profile: cobra reports any other first argument as an unknown command. */
	static function isCommandName(name:String):Bool {
		return switch name {
			case "help" | "version" | "where" | "info" | "ping" | "status" | "stats" | "count" | "ready" | "search" | "query" | "stale" | "orphans" |
				"children" | "dep" | "blocked" | "types" | "statuses" | "graph" | "comments" | "label" | "events" | "config" | "history" | "list" | "show" |
				"view" | "snapshot": true;
			case _: false;
		};
	}

	/**
		Whether the command in `path` lacks `typed`, a flag that only some
		commands have. The root command (an empty path) and `bd help` have none
		of them. Flags of list that other commands share are the default case.
	**/
	static function lacksCommandFlag(typed:String, path:Array<String>):Bool {
		final name = path.length > 0 ? path[0] : "";
		final subcommand = path.length > 1 ? path[1] : "";
		final depTree = name == "dep" && subcommand == "tree";
		final graphView = name == "graph" && subcommand != "check";
		if (countGroupFlag(typed) != null)
			return name != "count";
		return switch typed {
			case "--query": name != "search";
			case "--parse-only": name != "query";
			case "--days": name != "stale";
			// -d is --days in `stale` and --max-depth in `dep tree`.
			case "-d": name != "stale" && !depTree;
			case "--details" | "--fix" | "-f": name != "orphans";
			case "--sections": name != "types";
			case "--source": !(name == "config" && subcommand == "show");
			case "--events": name != "history";
			case "--since" | "--follow": !(name == "events" && subcommand == "tail");
			case "--before": !(name == "events" && subcommand == "prune");
			case "--direction": name != "dep";
			case "--max-depth" | "--show-all-paths": !depTree;
			case "--open" | "--dot" | "--html" | "--compact" | "--box": !graphView;
			// --local-time belongs to the listing alone, not to its `list` or `add` subcommands.
			case "--local-time": name != "comments" || subcommand == "list" || subcommand == "add";
			case "--id": name != "show" && name != "view" && name != "list" && name != "count";
			case "--no-blocked" | "--assigned": name != "status" && name != "stats";
			case "--schema" | "--whats-new": name != "info";
			case "--watch" | "-w": name != "show" && name != "view" && name != "list";
			case "--short" | "--current" | "--thread" | "--refs" | "--children" | "--include-dependents" | "--include-comments" | "--brief-deps":
				name != "show" && name != "view";
			// The other flags are list's, which some commands share, and ready's own flags.
			case _ if (name == "list"): isReadyOnlyFlag(typed);
			case _:
				!(name == "children" && typed == "--pretty")
				&& !(name == "show" && typed == "--long")
				&& !(name == "count" && isCountFilterFlag(typed))
				&& !(name == "ready" && isReadyFilterFlag(typed))
				&& !(name == "search" && isSearchFilterFlag(typed))
				&& !(name == "query" && isQueryFilterFlag(typed))
				&& !(name == "stale" && isStaleFilterFlag(typed))
				&& !(name == "orphans" && isOrphansFilterFlag(typed))
				&& !(name == "dep" && !depTree && (typed == "--type" || typed == "-t"))
				&& !(depTree && isDepTreeFilterFlag(typed))
				&& !(graphView && (typed == "--all" || typed == "--max-rows"))
				&& !(name == "blocked" && typed == "--parent")
				&& !(name == "history" && typed == "--limit")
				&& !(name == "events" && typed == "--limit" && (subcommand == "tail" || subcommand == "export"));
		};
	}

	/**
		Go's strings.EqualFold(value, "json"), which upstream applies to --format.
		Besides the ASCII case pairs, only ſ (U+017F) folds to one of these letters.
	**/
	static function isJsonFormat(value:String):Bool {
		return StringTools.replace(value, String.fromCharCode(0x17F), "s").toLowerCase() == "json";
	}

	static function isOrphansFilterFlag(flag:String):Bool {
		return switch flag {
			case "--label" | "-l" | "--label-any": true;
			case _: false;
		};
	}

	static function isReadySort(value:String):Bool {
		return value == "priority" || value == "hybrid" || value == "oldest";
	}

	static function skipLabelsConflicts(labels:Array<String>, labelsAny:Array<String>, labelPattern:String, labelRegex:String, excludeLabels:Array<String>,
			noLabels:Bool):Array<String> {
		final conflicts = new Array<String>();
		if (labels.length > 0)
			conflicts.push("--label");
		if (labelsAny.length > 0)
			conflicts.push("--label-any");
		if (labelPattern != "")
			conflicts.push("--label-pattern");
		if (labelRegex != "")
			conflicts.push("--label-regex");
		if (excludeLabels.length > 0)
			conflicts.push("--exclude-label");
		if (noLabels)
			conflicts.push("--no-labels");
		return conflicts;
	}

	static function formatSkipLabelsConflict(conflicts:Array<String>):String {
		return "error: --skip-labels cannot be combined with --label,\n"
			+ "       --label-any, --label-pattern, --label-regex,\n"
			+ "       --exclude-label, or --no-labels (the filter).\n"
			+ '       (got: --skip-labels ${conflicts.join(" ")})\n'
			+ "reason: --skip-labels suppresses the labels JOIN that those\n"
			+ "        filters depend on.\n\n"
			+ "To filter by labels: drop --skip-labels.\n"
			+ "To get a label-free result fast: drop --label flags.\n";
	}

	static function listTimeField(flag:String):Null<ListTimeField> {
		return switch flag {
			case "--created-after": TimeCreatedAfter;
			case "--created-before": TimeCreatedBefore;
			case "--updated-after": TimeUpdatedAfter;
			case "--updated-before": TimeUpdatedBefore;
			case "--closed-after": TimeClosedAfter;
			case "--closed-before": TimeClosedBefore;
			case "--defer-after": TimeDeferAfter;
			case "--defer-before": TimeDeferBefore;
			case "--due-after": TimeDueAfter;
			case "--due-before": TimeDueBefore;
			case _: null;
		};
	}

	static function listTimeFlag(field:ListTimeField):String {
		return switch field {
			case TimeCreatedAfter: "created-after";
			case TimeCreatedBefore: "created-before";
			case TimeUpdatedAfter: "updated-after";
			case TimeUpdatedBefore: "updated-before";
			case TimeClosedAfter: "closed-after";
			case TimeClosedBefore: "closed-before";
			case TimeDeferAfter: "defer-after";
			case TimeDeferBefore: "defer-before";
			case TimeDueAfter: "due-after";
			case TimeDueBefore: "due-before";
		};
	}

	static function addListTimeFilter(filters:Array<IssueListTimeFilter>, field:ListTimeField, raw:String):Null<String> {
		final outcome = NativeListTimeParser.parse(raw);
		if (outcome.failed())
			return 'parsing --${listTimeFlag(field)}: ${outcome.message()}';
		final value = outcome.value();
		filters.push(switch field {
			case TimeCreatedAfter: CreatedAfter(value);
			case TimeCreatedBefore: CreatedBefore(value);
			case TimeUpdatedAfter: UpdatedAfter(value);
			case TimeUpdatedBefore: UpdatedBefore(value);
			case TimeClosedAfter: ClosedAfter(value);
			case TimeClosedBefore: ClosedBefore(value);
			case TimeDeferAfter: DeferAfter(value);
			case TimeDeferBefore: DeferBefore(value);
			case TimeDueAfter: DueAfter(value);
			case TimeDueBefore: DueBefore(value);
		});
		return null;
	}

	static function isMoleculeType(value:String):Bool {
		return value == "swarm" || value == "patrol" || value == "work";
	}

	static function isWispType(value:String):Bool {
		return switch value {
			case "heartbeat" | "ping" | "patrol" | "gc_report" | "recovery" | "error" | "escalation": true;
			case _: false;
		};
	}

	static function addMetadataFilter(filters:Array<IssueListMetadataFilter>, raw:String):Null<String> {
		final separator = raw.indexOf("=");
		if (separator <= 0)
			return 'invalid --metadata-field: expected key=value, got ${goQuote(raw)}';
		final key = raw.substr(0, separator);
		final keyError = validateMetadataKey("--metadata-field key", key);
		if (keyError != null)
			return keyError;
		filters.push({key: key, value: raw.substr(separator + 1)});
		return null;
	}

	static function validateMetadataKey(flag:String, key:String):Null<String> {
		var valid = key.length > 0 && (isAsciiLetter(key.charAt(0)) || key.charAt(0) == "_");
		for (index in 1...key.length) {
			final character = key.charAt(index);
			if (!isAsciiLetter(character) && "0123456789_./".indexOf(character) < 0) {
				valid = false;
				break;
			}
		}
		if (!valid)
			return 'invalid ${flag}: invalid metadata key ${goQuote(key)}: must match ^[a-zA-Z_][a-zA-Z0-9_./]*$$';
		return null;
	}

	static function isAsciiLetter(character:String):Bool {
		return (character >= "a" && character <= "z") || (character >= "A" && character <= "Z");
	}

	static function booleanFlagValue(value:String):Bool {
		return switch value {
			case "1" | "t" | "T" | "true" | "TRUE" | "True": true;
			case _: false;
		};
	}

	static function isDoltAutoCommitValue(value:String):Bool {
		return value == "" || value == "off" || value == "on" || value == "batch";
	}

	static function addCommaSeparated(target:Array<String>, value:String):Void {
		for (part in value.split(",")) {
			final normalized = StringTools.trim(part);
			if (normalized != "")
				target.push(normalized);
		}
	}

	static function normalizeIssueType(value:String):String {
		return switch value {
			case "mr": "merge-request";
			case "feat": "feature";
			case "mol": "molecule";
			case "dec" | "adr": "decision";
			case _: value;
		};
	}

	/**
		Upstream validation.ParsePriority: Go's strings.TrimSpace, one leading
		`P` or `p` dropped, then fmt.Sscanf with `%d`. That skips spaces (a
		newline fails), reads an optional sign and at least one digit, and
		ignores the rest, so `1x` and ` P2` are valid. Returns -1 unless the
		number is 0 to 4.
	**/
	static function goPriority(value:String):Int {
		var content = goTrimSpace(value);
		if (StringTools.startsWith(content, "P") || StringTools.startsWith(content, "p"))
			content = content.substr(1);
		var index = 0;
		while (index < content.length && isGoSpace(content.charCodeAt(index))) {
			if (content.charAt(index) == "\n")
				return -1;
			index++;
		}
		var negative = false;
		if (index < content.length && (content.charAt(index) == "+" || content.charAt(index) == "-")) {
			negative = content.charAt(index) == "-";
			index++;
		}
		var digits = 0;
		var priority = 0;
		while (index < content.length && content.charAt(index) >= "0" && content.charAt(index) <= "9") {
			// A value past 4 is invalid however long it gets, so it stops growing there.
			if (priority <= 4)
				priority = priority * 10 + content.charCodeAt(index) - "0".code;
			digits++;
			index++;
		}
		if (digits == 0 || priority > 4 || (negative && priority != 0))
			return -1;
		return priority;
	}

	/** Upstream validation.ValidatePriority's error. */
	static function invalidPriority(value:String):String {
		return 'invalid priority ${goQuote(value)} (expected 0-4 or P0-P4, not words like high/medium/low)';
	}

	static function checkPassed(check:DeferredCheck):Bool {
		return switch check {
			case ChecksPassed: true;
			case PlainCheckFailure(_) | OutputCheckFailure(_) | ExactCheckFailure(_, _): false;
		};
	}

	static function isListSort(value:String):Bool {
		return switch value {
			case "priority" | "created" | "updated" | "closed" | "status" | "id" | "title" | "type" | "assignee": true;
			case _: false;
		};
	}

	static function invalidListSort(value:String):String {
		return 'invalid sort field "${value}" (valid: priority, created, updated, closed, status, id, title, type, assignee)';
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("ListTimeParseOutcome")
private extern class NativeListTimeParseOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("Value") function value():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
private extern class NativeListTimeParser {
	@:go.name("ParseListTime") static function parse(value:String):NativeListTimeParseOutcome;
}
