package beadshx.cli;

import beadshx.store.OptionalInt;
import beadshx.store.CountGroup;
import beadshx.store.IssueListMetadataFilter;
import beadshx.store.IssueListTimeFilter;
import beadshx.store.ReadySort;
import beadshx.store.StaleRequest;
import beadshx.query.QueryCommandRequest;

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
	ListPriority;
	ListLimit;
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
	ListPriorityMin;
	ListPriorityMax;
	ListExcludeType;
	ListParent;
	ListMoleculeType;
	ListWispType;
	ListMetadataField;
	ListHasMetadataKey;
	ListTime(field:ListTimeField);
	ListOffset;
	ListMaxRows;
	ReadyMolecule;
	SearchQuery;
	StaleDays;
	DepDirection;
}

/** Parses the bounded read-only command profile without Cobra or process-global access. */
final class Parser {
	final environment:EnvironmentPort;

	public function new(environment:EnvironmentPort) {
		this.environment = environment;
	}

	public function parse(args:Array<String>):ParseResult {
		var output = OutputMode.Human;
		var actor = "";
		var directory = "";
		var databasePath = "";
		var databaseName = "";
		var global = false;
		var cpuProfile = false;
		var memProfilePath = "";
		var expectedValue:Null<ExpectedValue> = null;
		var showHelp = false;
		var infoSchema = false;
		var infoWhatsNew = false;
		var statusSkipBlocked = false;
		var statusAssigned = false;
		var countGroup = CountGroup.Ungrouped;
		var countGroupConflict = false;
		final countOnlyFlags = new Array<String>();
		function selectCountGroup(flag:String, group:CountGroup):Void {
			countOnlyFlags.push(flag);
			if (countGroup != CountGroup.Ungrouped && countGroup != group)
				countGroupConflict = true;
			countGroup = group;
		}
		var listStatus = "";
		var listAssignee = "";
		var listIssueType = "";
		var depTypeRaw = "";
		var listTitle = "";
		var listSpec = "";
		var listPriority = OptionalInt.IntAbsent;
		var listPriorityRaw = "";
		var listPriorityMin = OptionalInt.IntAbsent;
		var listPriorityMax = OptionalInt.IntAbsent;
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
		final listOnlyFlags = new Array<String>();
		function markListOnly(flag:String):Void {
			listOnlyFlags.push(flag);
		}
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
		var searchQueryUsed = false;
		var queryParseOnly = false;
		var queryParseOnlyUsed = false;
		var staleDays = 30;
		var staleDaysUsed = false;
		var orphansDetails = false;
		var orphansDetailsUsed = false;
		var orphansFix = false;
		var orphansFixUsed = false;
		var depDirection = "down";
		var depDirectionUsed = false;
		var readyAwareUsageFailure = "";
		function rememberReadyAwareUsageFailure(message:String):Void {
			if (readyAwareUsageFailure == "")
				readyAwareUsageFailure = message;
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
		final positional = new Array<String>();
		for (argument in args) {
			if (expectedValue != null) {
				switch expectedValue {
					case Actor:
						if (argument == "")
							return UsageFailure("--actor requires a non-empty value");
						actor = argument;
					case ShortDirectory | LongDirectory:
						directory = argument;
					case DatabasePath:
						databasePath = argument;
					case DatabaseName:
						databaseName = argument;
					case OutputFormat:
						if (argument.toLowerCase() == "json")
							output = OutputMode.Json;
						else
							listFormat = argument;
					case DoltAutoCommit:
						if (!isDoltAutoCommitValue(argument))
							return UsageFailure('invalid --dolt-auto-commit="${argument}" (valid: off, on, batch)');
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
					case ListPriority:
						listPriorityRaw = argument;
					case ListLimit:
						final limit = parseSignedInt(argument);
						if (limit == null)
							return UsageFailure('invalid argument "${argument}" for "-n, --limit" flag: expected an integer');
						listLimit = IntPresent(limit);
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
					case ListPriorityMin:
						final priority = parsePriority(argument);
						if (priority < 0)
							return UsageFailure('parsing --priority-min: invalid priority: ${argument} (must be 0-4 or P0-P4)');
						listPriorityMin = IntPresent(priority);
					case ListPriorityMax:
						final priority = parsePriority(argument);
						if (priority < 0)
							return UsageFailure('parsing --priority-max: invalid priority: ${argument} (must be 0-4 or P0-P4)');
						listPriorityMax = IntPresent(priority);
					case ListExcludeType:
						addCommaSeparated(listExcludeTypes, argument);
					case ListParent:
						listParent = argument;
					case ListMoleculeType:
						if (!isMoleculeType(argument))
							rememberReadyAwareUsageFailure('invalid mol-type "${argument}" (must be swarm, patrol, or work)');
						else
							listMoleculeType = argument;
					case ListWispType:
						if (!isWispType(argument))
							return UsageFailure('invalid wisp-type "${argument}" (must be heartbeat, ping, patrol, gc_report, recovery, error, or escalation)');
						listWispType = argument;
					case ListMetadataField:
						final metadataError = addMetadataFilter(listMetadataFields, argument);
						if (metadataError != null)
							rememberReadyAwareUsageFailure(metadataError);
					case ListHasMetadataKey:
						final metadataError = validateMetadataKey("--has-metadata-key", argument);
						if (metadataError != null)
							rememberReadyAwareUsageFailure(metadataError);
						else
							listHasMetadataKey = argument;
					case ListTime(field):
						final timeError = addListTimeFilter(listTimeFilters, field, argument);
						if (timeError != null)
							return UsageFailure(timeError);
					case ListOffset:
						final offset = parseSignedInt(argument);
						if (offset == null)
							return UsageFailure('invalid argument "${argument}" for "--offset" flag: expected an integer');
						listOffset = IntPresent(offset);
					case ListMaxRows:
						final maxRows = parseSignedInt(argument);
						if (maxRows == null)
							return UsageFailure('invalid argument "${argument}" for "--max-rows" flag: expected an integer');
						if (maxRows < 0)
							return UsageFailure('--max-rows must be non-negative; got ${maxRows}');
						listMaxRows = IntPresent(maxRows);
						listMaxRowsSource = "--max-rows";
					case ReadyMolecule:
						readyMolecule = argument;
					case SearchQuery:
						searchQueryFlag = argument;
					case StaleDays:
						final days = parseSignedInt(argument);
						if (days == null)
							return UsageFailure('invalid argument "${argument}" for "-d, --days" flag: expected an integer');
						staleDays = days;
					case DepDirection:
						depDirection = argument;
				}
				expectedValue = null;
				continue;
			}
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
					return UsageFailure("--actor requires a non-empty value");
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
				final value = argument.substr(9);
				if (value.toLowerCase() == "json")
					output = OutputMode.Json;
				else
					listFormat = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--dolt-auto-commit=")) {
				final value = argument.substr(19);
				if (!isDoltAutoCommitValue(value))
					return UsageFailure('invalid --dolt-auto-commit="${value}" (valid: off, on, batch)');
				continue;
			}
			if (StringTools.startsWith(argument, "--mem-profile=")) {
				memProfilePath = argument.substr(14);
				continue;
			}
			if (StringTools.startsWith(argument, "--query=")) {
				searchQueryUsed = true;
				searchQueryFlag = argument.substr(8);
				continue;
			}
			if (StringTools.startsWith(argument, "--days=")) {
				staleDaysUsed = true;
				final raw = argument.substr(7);
				final days = parseSignedInt(raw);
				if (days == null)
					return UsageFailure('invalid argument "${raw}" for "-d, --days" flag: expected an integer');
				staleDays = days;
				continue;
			}
			if (StringTools.startsWith(argument, "--direction=")) {
				depDirectionUsed = true;
				depDirection = argument.substr(12);
				continue;
			}
			if (StringTools.startsWith(argument, "--details=")
				|| StringTools.startsWith(argument, "--fix=")
				|| StringTools.startsWith(argument, "-f=")) {
				final separator = argument.indexOf("=");
				final flag = argument.substr(0, separator);
				final value = argument.substr(separator + 1);
				if (!isBooleanFlagValue(value))
					return UsageFailure('invalid argument "${value}" for "${flag}" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				if (flag == "--details") {
					orphansDetailsUsed = true;
					orphansDetails = booleanFlagValue(value);
				} else {
					orphansFixUsed = true;
					orphansFix = booleanFlagValue(value);
				}
				continue;
			}
			if (StringTools.startsWith(argument, "--id=")) {
				issueFlagIds.push(argument.substr(5));
				continue;
			}
			if (StringTools.startsWith(argument, "--status=")) {
				markListOnly("--status");
				listStatus = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--assignee=")) {
				markListOnly("--assignee");
				listAssignee = argument.substr(11);
				continue;
			}
			if (StringTools.startsWith(argument, "--type=")) {
				markListOnly("--type");
				depTypeRaw = argument.substr(7);
				listIssueType = normalizeIssueType(depTypeRaw);
				continue;
			}
			if (StringTools.startsWith(argument, "--priority=")) {
				markListOnly("--priority");
				listPriorityRaw = argument.substr(11);
				continue;
			}
			if (StringTools.startsWith(argument, "--limit=")) {
				markListOnly("--limit");
				final raw = argument.substr(8);
				final limit = parseSignedInt(raw);
				if (limit == null)
					return UsageFailure('invalid argument "${raw}" for "-n, --limit" flag: expected an integer');
				listLimit = IntPresent(limit);
				continue;
			}
			if (StringTools.startsWith(argument, "--sort=")) {
				markListOnly("--sort");
				listSort = argument.substr(7);
				continue;
			}
			if (StringTools.startsWith(argument, "-s=")) {
				markListOnly("-s");
				shorthandS = argument.substr(3);
				continue;
			}
			if (StringTools.startsWith(argument, "--title=")) {
				markListOnly("--title");
				listTitle = argument.substr(8);
				continue;
			}
			if (StringTools.startsWith(argument, "--spec=")) {
				markListOnly("--spec");
				listSpec = argument.substr(7);
				continue;
			}
			if (StringTools.startsWith(argument, "--label=")) {
				markListOnly("--label");
				addCommaSeparated(listLabels, argument.substr(8));
				continue;
			}
			if (StringTools.startsWith(argument, "-l=")) {
				markListOnly("-l");
				addCommaSeparated(listLabels, argument.substr(3));
				continue;
			}
			if (StringTools.startsWith(argument, "--label-any=")) {
				markListOnly("--label-any");
				addCommaSeparated(listLabelsAny, argument.substr(12));
				continue;
			}
			if (StringTools.startsWith(argument, "--exclude-label=")) {
				markListOnly("--exclude-label");
				addCommaSeparated(listExcludeLabels, argument.substr(16));
				continue;
			}
			if (StringTools.startsWith(argument, "--label-pattern=")) {
				markListOnly("--label-pattern");
				listLabelPattern = argument.substr(16);
				continue;
			}
			if (StringTools.startsWith(argument, "--label-regex=")) {
				markListOnly("--label-regex");
				listLabelRegex = argument.substr(14);
				continue;
			}
			if (StringTools.startsWith(argument, "--title-contains=")) {
				markListOnly("--title-contains");
				listTitleContains = argument.substr(17);
				continue;
			}
			if (StringTools.startsWith(argument, "--desc-contains=")) {
				markListOnly("--desc-contains");
				listDescriptionContains = argument.substr(16);
				continue;
			}
			if (StringTools.startsWith(argument, "--notes-contains=")) {
				markListOnly("--notes-contains");
				listNotesContains = argument.substr(17);
				continue;
			}
			if (StringTools.startsWith(argument, "--external-contains=")) {
				markListOnly("--external-contains");
				listExternalContains = argument.substr(20);
				continue;
			}
			if (StringTools.startsWith(argument, "--external-ref=")) {
				markListOnly("--external-ref");
				listExternalRef = argument.substr(15);
				continue;
			}
			if (StringTools.startsWith(argument, "--priority-min=")) {
				markListOnly("--priority-min");
				final raw = argument.substr(15);
				final priority = parsePriority(raw);
				if (priority < 0)
					return UsageFailure('parsing --priority-min: invalid priority: ${raw} (must be 0-4 or P0-P4)');
				listPriorityMin = IntPresent(priority);
				continue;
			}
			if (StringTools.startsWith(argument, "--priority-max=")) {
				markListOnly("--priority-max");
				final raw = argument.substr(15);
				final priority = parsePriority(raw);
				if (priority < 0)
					return UsageFailure('parsing --priority-max: invalid priority: ${raw} (must be 0-4 or P0-P4)');
				listPriorityMax = IntPresent(priority);
				continue;
			}
			if (StringTools.startsWith(argument, "--exclude-type=")) {
				markListOnly("--exclude-type");
				addCommaSeparated(listExcludeTypes, argument.substr(15));
				continue;
			}
			if (StringTools.startsWith(argument, "--parent=")) {
				markListOnly("--parent");
				listParent = argument.substr(9);
				continue;
			}
			if (StringTools.startsWith(argument, "--mol-type=")) {
				markListOnly("--mol-type");
				final value = argument.substr(11);
				if (!isMoleculeType(value))
					rememberReadyAwareUsageFailure('invalid mol-type "${value}" (must be swarm, patrol, or work)');
				else
					listMoleculeType = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--mol=")) {
				markListOnly("--mol");
				readyMolecule = argument.substr(6);
				continue;
			}
			if (StringTools.startsWith(argument, "--wisp-type=")) {
				markListOnly("--wisp-type");
				final value = argument.substr(12);
				if (!isWispType(value))
					return UsageFailure('invalid wisp-type "${value}" (must be heartbeat, ping, patrol, gc_report, recovery, error, or escalation)');
				listWispType = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--metadata-field=")) {
				markListOnly("--metadata-field");
				final metadataError = addMetadataFilter(listMetadataFields, argument.substr(17));
				if (metadataError != null)
					rememberReadyAwareUsageFailure(metadataError);
				continue;
			}
			if (StringTools.startsWith(argument, "--has-metadata-key=")) {
				markListOnly("--has-metadata-key");
				final value = argument.substr(19);
				final metadataError = validateMetadataKey("--has-metadata-key", value);
				if (metadataError != null)
					rememberReadyAwareUsageFailure(metadataError);
				else
					listHasMetadataKey = value;
				continue;
			}
			if (StringTools.startsWith(argument, "--offset=")) {
				markListOnly("--offset");
				final raw = argument.substr(9);
				final offset = parseSignedInt(raw);
				if (offset == null)
					return UsageFailure('invalid argument "${raw}" for "--offset" flag: expected an integer');
				listOffset = IntPresent(offset);
				continue;
			}
			if (StringTools.startsWith(argument, "--max-rows=")) {
				markListOnly("--max-rows");
				final raw = argument.substr(11);
				final maxRows = parseSignedInt(raw);
				if (maxRows == null)
					return UsageFailure('invalid argument "${raw}" for "--max-rows" flag: expected an integer');
				if (maxRows < 0)
					return UsageFailure('--max-rows must be non-negative; got ${maxRows}');
				listMaxRows = IntPresent(maxRows);
				listMaxRowsSource = "--max-rows";
				continue;
			}
			if (StringTools.startsWith(argument, "--deps=")) {
				markListOnly("--deps");
				listDepsMode = argument.substr(7);
				continue;
			}
			final equalsIndex = argument.indexOf("=");
			if (equalsIndex > 0) {
				final flag = argument.substr(0, equalsIndex);
				switch countGroupFlag(flag) {
					case null:
					case group:
						final value = argument.substr(equalsIndex + 1);
						if (!isBooleanFlagValue(value))
							return UsageFailure('invalid argument "${value}" for "${flag}" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
						if (booleanFlagValue(value))
							selectCountGroup(flag, group);
						else
							countOnlyFlags.push(flag);
						continue;
				}
				switch listTimeField(flag) {
					case null:
					case field:
						markListOnly(flag);
						final timeError = addListTimeFilter(listTimeFilters, field, argument.substr(equalsIndex + 1));
						if (timeError != null)
							return UsageFailure(timeError);
						continue;
				}
				if (isListBooleanFlag(flag)) {
					markListOnly(flag);
					final value = argument.substr(equalsIndex + 1);
					if (!isBooleanFlagValue(value))
						return UsageFailure('invalid argument "${value}" for "${flag}" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
					final enabled = booleanFlagValue(value);
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
							queryParseOnlyUsed = true;
							queryParseOnly = enabled;
					}
					continue;
				}
			}
			if (StringTools.startsWith(argument, "--cpu-profile=")) {
				final value = argument.substr(14);
				if (!isBooleanFlagValue(value))
					return UsageFailure('invalid argument "${value}" for "--cpu-profile" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				cpuProfile = booleanFlagValue(value);
				continue;
			}
			if (StringTools.startsWith(argument, "--ignore-schema-skew=")) {
				final value = argument.substr(21);
				if (!isBooleanFlagValue(value))
					return UsageFailure('invalid argument "${value}" for "--ignore-schema-skew" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				continue;
			}
			if (StringTools.startsWith(argument, "--global=")) {
				final value = argument.substr(9);
				if (!isBooleanFlagValue(value))
					return UsageFailure('invalid argument "${value}" for "--global" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				global = booleanFlagValue(value);
				continue;
			}
			if (StringTools.startsWith(argument, "--watch=")
				|| StringTools.startsWith(argument, "--thread=")
				|| StringTools.startsWith(argument, "--refs=")
				|| StringTools.startsWith(argument, "--children=")
				|| StringTools.startsWith(argument, "--include-dependents=")
				|| StringTools.startsWith(argument, "--include-comments=")
				|| StringTools.startsWith(argument, "--brief-deps=")) {
				final value = argument.substr(argument.indexOf("=") + 1);
				if (!isBooleanFlagValue(value)) {
					final flag = argument.substr(0, argument.indexOf("="));
					return UsageFailure('invalid argument "${value}" for "${flag}" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				}
				final enabled = booleanFlagValue(value);
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
			if (StringTools.startsWith(argument, "--verbose=") || StringTools.startsWith(argument, "-v=")) {
				final value = argument.substr(argument.indexOf("=") + 1);
				if (!isBooleanFlagValue(value))
					return UsageFailure('invalid argument "${value}" for "-v, --verbose" flag: strconv.ParseBool: parsing "${value}": invalid syntax');
				continue;
			}
			if (argument != "-C" && StringTools.startsWith(argument, "-C")) {
				directory = argument.substr(2);
				continue;
			}
			switch argument {
				case "--help" | "-h":
					showHelp = true;
				case "--json":
					output = OutputMode.Json;
				case "--schema":
					infoSchema = true;
				case "--whats-new":
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
					expectedValue = IssueID;
				case "--by-status":
					selectCountGroup(argument, CountGroup.ByStatus);
				case "--by-priority":
					selectCountGroup(argument, CountGroup.ByPriority);
				case "--by-type":
					selectCountGroup(argument, CountGroup.ByType);
				case "--by-assignee":
					selectCountGroup(argument, CountGroup.ByAssignee);
				case "--by-label":
					selectCountGroup(argument, CountGroup.ByLabel);
				case "--status":
					markListOnly(argument);
					expectedValue = ListStatus;
				case "-s":
					markListOnly(argument);
					expectedValue = ShortS;
				case "--assignee" | "-a":
					markListOnly(argument);
					if (argument == "-a" && positional.length > 0 && positional[0] == "query")
						listAll = true;
					else
						expectedValue = ListAssignee;
				case "--type" | "-t":
					markListOnly(argument);
					expectedValue = ListIssueType;
				case "--priority" | "-p":
					markListOnly(argument);
					expectedValue = ListPriority;
				case "--limit" | "-n":
					markListOnly(argument);
					expectedValue = ListLimit;
				case "--sort":
					markListOnly(argument);
					expectedValue = ListSort;
				case "--title":
					markListOnly(argument);
					expectedValue = ListTitle;
				case "--spec":
					markListOnly(argument);
					expectedValue = ListSpec;
				case "--label" | "-l":
					markListOnly(argument);
					expectedValue = ListLabel;
				case "--label-any":
					markListOnly(argument);
					expectedValue = ListLabelAny;
				case "--exclude-label":
					markListOnly(argument);
					expectedValue = ListExcludeLabel;
				case "--label-pattern":
					markListOnly(argument);
					expectedValue = ListLabelPattern;
				case "--label-regex":
					markListOnly(argument);
					expectedValue = ListLabelRegex;
				case "--title-contains":
					markListOnly(argument);
					expectedValue = ListTitleContains;
				case "--desc-contains":
					markListOnly(argument);
					expectedValue = ListDescriptionContains;
				case "--notes-contains":
					markListOnly(argument);
					expectedValue = ListNotesContains;
				case "--external-contains":
					markListOnly(argument);
					expectedValue = ListExternalContains;
				case "--external-ref":
					markListOnly(argument);
					expectedValue = ListExternalRef;
				case "--priority-min":
					markListOnly(argument);
					expectedValue = ListPriorityMin;
				case "--priority-max":
					markListOnly(argument);
					expectedValue = ListPriorityMax;
				case "--exclude-type":
					markListOnly(argument);
					expectedValue = ListExcludeType;
				case "--parent":
					markListOnly(argument);
					expectedValue = ListParent;
				case "--mol-type":
					markListOnly(argument);
					expectedValue = ListMoleculeType;
				case "--mol":
					markListOnly(argument);
					expectedValue = ReadyMolecule;
				case "--wisp-type":
					markListOnly(argument);
					expectedValue = ListWispType;
				case "--metadata-field":
					markListOnly(argument);
					expectedValue = ListMetadataField;
				case "--query":
					searchQueryUsed = true;
					expectedValue = SearchQuery;
				case "--parse-only":
					queryParseOnlyUsed = true;
					queryParseOnly = true;
				case "--days" | "-d":
					staleDaysUsed = true;
					expectedValue = StaleDays;
				case "--has-metadata-key":
					markListOnly(argument);
					expectedValue = ListHasMetadataKey;
				case "--created-after":
					markListOnly(argument);
					expectedValue = ListTime(TimeCreatedAfter);
				case "--created-before":
					markListOnly(argument);
					expectedValue = ListTime(TimeCreatedBefore);
				case "--updated-after":
					markListOnly(argument);
					expectedValue = ListTime(TimeUpdatedAfter);
				case "--updated-before":
					markListOnly(argument);
					expectedValue = ListTime(TimeUpdatedBefore);
				case "--closed-after":
					markListOnly(argument);
					expectedValue = ListTime(TimeClosedAfter);
				case "--closed-before":
					markListOnly(argument);
					expectedValue = ListTime(TimeClosedBefore);
				case "--defer-after":
					markListOnly(argument);
					expectedValue = ListTime(TimeDeferAfter);
				case "--defer-before":
					markListOnly(argument);
					expectedValue = ListTime(TimeDeferBefore);
				case "--due-after":
					markListOnly(argument);
					expectedValue = ListTime(TimeDueAfter);
				case "--due-before":
					markListOnly(argument);
					expectedValue = ListTime(TimeDueBefore);
				case "--offset":
					markListOnly(argument);
					expectedValue = ListOffset;
				case "--max-rows":
					markListOnly(argument);
					expectedValue = ListMaxRows;
				case "--reverse" | "-r":
					markListOnly(argument);
					listReverse = true;
				case "--ready":
					markListOnly(argument);
					listReady = true;
				case "--no-assignee":
					markListOnly(argument);
					listNoAssignee = true;
				case "--no-labels":
					markListOnly(argument);
					listNoLabels = true;
				case "--empty-description":
					markListOnly(argument);
					listEmptyDescription = true;
				case "--skip-labels":
					markListOnly(argument);
					listSkipLabels = true;
				case "--brief":
					markListOnly(argument);
					listBrief = true;
				case "--pinned":
					markListOnly(argument);
					listPinned = true;
				case "--no-pinned":
					markListOnly(argument);
					listNoPinned = true;
				case "--include-templates":
					markListOnly(argument);
					listIncludeTemplates = true;
				case "--include-gates":
					markListOnly(argument);
					listIncludeGates = true;
				case "--include-infra":
					markListOnly(argument);
					listIncludeInfra = true;
				case "--no-parent":
					markListOnly(argument);
					listNoParent = true;
				case "--deferred":
					markListOnly(argument);
					listDeferred = true;
				case "--overdue":
					markListOnly(argument);
					listOverdue = true;
				case "--flat":
					markListOnly(argument);
					listFlat = true;
				case "--long":
					markListOnly(argument);
					listLong = true;
					showLong = true;
				case "--tree":
					markListOnly(argument);
					listTree = true;
				case "--pretty":
					markListOnly(argument);
					listPretty = true;
					listPrettyChanged = true;
				case "--plain":
					markListOnly(argument);
					readyPlain = true;
				case "--unassigned" | "-u":
					markListOnly(argument);
					readyUnassigned = true;
				case "--include-deferred":
					markListOnly(argument);
					readyIncludeDeferred = true;
				case "--include-ephemeral":
					markListOnly(argument);
					readyIncludeEphemeral = true;
				case "--claim":
					markListOnly(argument);
					readyClaim = true;
				case "--gated":
					markListOnly(argument);
					readyGated = true;
				case "--explain":
					markListOnly(argument);
					readyExplain = true;
				case "--details":
					orphansDetailsUsed = true;
					orphansDetails = true;
				case "--fix" | "-f":
					orphansFixUsed = true;
					orphansFix = true;
				case "--no-pager":
					markListOnly(argument);
					listNoPager = true;
				case "--deps":
					markListOnly(argument);
					listDepsMode = "scheduling";
				case "--direction":
					depDirectionUsed = true;
					expectedValue = DepDirection;
				case "--no-blocked":
					statusSkipBlocked = true;
				case "--assigned":
					statusAssigned = true;
				case "--short":
					showShort = true;
				case "--current":
					showCurrent = true;
				case "--watch" | "-w":
					watchMode = true;
				case "--thread":
					showThread = true;
				case "--refs":
					showRefs = true;
				case "--children":
					showChildren = true;
				case "--include-dependents":
					showIncludeDependents = true;
				case "--include-comments":
					showIncludeComments = true;
				case "--brief-deps":
					showBriefDependencies = true;
				case "--all":
					markListOnly(argument);
					listAll = true;
				case "--no-activity":
					// Accepted compatibility flags; recent activity is currently absent.
				case "--readonly" | "--sandbox" | "--no-color" | "--quiet" | "-q" | "--verbose" | "-v" | "--ignore-schema-skew":
					// This command profile is already read-only, unstyled, and synchronous.
				case "--version" | "-V":
					positional.push("version");
				case value:
					if (StringTools.startsWith(value, "--")) {
						final flag = value.split("=")[0];
						return UsageFailure('unknown flag: ${flag}');
					}
					if (value != "-" && StringTools.startsWith(value, "-"))
						return UsageFailure('unknown shorthand flag: \'${value.charAt(1)}\' in ${value}');
					positional.push(value);
			}
		}
		if (expectedValue != null) {
			return switch expectedValue {
				case Actor: UsageFailure("--actor requires a value");
				case ShortDirectory: UsageFailure("flag needs an argument: 'C' in -C");
				case LongDirectory: UsageFailure("flag needs an argument: --directory");
				case DatabasePath: UsageFailure("flag needs an argument: --db");
				case DatabaseName: UsageFailure("flag needs an argument: --database");
				case OutputFormat: UsageFailure("flag needs an argument: --format");
				case DoltAutoCommit: UsageFailure("flag needs an argument: --dolt-auto-commit");
				case MemProfile: UsageFailure("flag needs an argument: --mem-profile");
				case IssueID: UsageFailure("flag needs an argument: --id");
				case ShortS: UsageFailure("flag needs an argument: 's' in -s");
				case ListStatus: UsageFailure("flag needs an argument: --status");
				case ListAssignee: UsageFailure("flag needs an argument: --assignee");
				case ListIssueType: UsageFailure("flag needs an argument: --type");
				case ListPriority: UsageFailure("flag needs an argument: --priority");
				case ListLimit: UsageFailure("flag needs an argument: --limit");
				case ListSort: UsageFailure("flag needs an argument: --sort");
				case ListTitle: UsageFailure("flag needs an argument: --title");
				case ListSpec: UsageFailure("flag needs an argument: --spec");
				case ListLabel: UsageFailure("flag needs an argument: --label");
				case ListLabelAny: UsageFailure("flag needs an argument: --label-any");
				case ListExcludeLabel: UsageFailure("flag needs an argument: --exclude-label");
				case ListLabelPattern: UsageFailure("flag needs an argument: --label-pattern");
				case ListLabelRegex: UsageFailure("flag needs an argument: --label-regex");
				case ListTitleContains: UsageFailure("flag needs an argument: --title-contains");
				case ListDescriptionContains: UsageFailure("flag needs an argument: --desc-contains");
				case ListNotesContains: UsageFailure("flag needs an argument: --notes-contains");
				case ListExternalContains: UsageFailure("flag needs an argument: --external-contains");
				case ListExternalRef: UsageFailure("flag needs an argument: --external-ref");
				case ListPriorityMin: UsageFailure("flag needs an argument: --priority-min");
				case ListPriorityMax: UsageFailure("flag needs an argument: --priority-max");
				case ListExcludeType: UsageFailure("flag needs an argument: --exclude-type");
				case ListParent: UsageFailure("flag needs an argument: --parent");
				case ListMoleculeType: UsageFailure("flag needs an argument: --mol-type");
				case ListWispType: UsageFailure("flag needs an argument: --wisp-type");
				case ListMetadataField: UsageFailure("flag needs an argument: --metadata-field");
				case ListHasMetadataKey: UsageFailure("flag needs an argument: --has-metadata-key");
				case ListTime(field): UsageFailure('flag needs an argument: --${listTimeFlag(field)}');
				case ListOffset: UsageFailure("flag needs an argument: --offset");
				case ListMaxRows: UsageFailure("flag needs an argument: --max-rows");
				case ReadyMolecule: UsageFailure("flag needs an argument: --mol");
				case SearchQuery: UsageFailure("flag needs an argument: --query");
				case StaleDays: UsageFailure("flag needs an argument: --days");
				case DepDirection: UsageFailure("flag needs an argument: --direction");
			};
		}

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
				format: output == OutputMode.Human ? listFormat : "",
				sortBy: listSort,
				reverse: listReverse,
				limit: listLimit,
				offset: listOffset,
				maxRows: listMaxRows,
				maxRowsSource: listMaxRowsSource,
				skipCounts: output == OutputMode.Human,
				blockingAnnotations: output == OutputMode.Human
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

		if (positional.length == 0 || (positional.length == 1 && positional[0] == "help")) {
			return Parsed({
				command: Command.RootHelp,
				output: output,
				actor: actor,
				directory: directory,
				databasePath: databasePath,
				databaseName: databaseName,
				global: global,
				cpuProfile: cpuProfile,
				memProfilePath: memProfilePath,
				showHelp: showHelp,
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
				depType: depTypeRaw
			});
		}
		var helpCommand = false;
		if (positional[0] == "help") {
			positional.shift();
			showHelp = true;
			helpCommand = true;
		}
		final name = positional[0];
		if (name == "dep") {
			if (positional.length < 2) {
				if (!showHelp)
					return UsageFailure("dep requires the read-only subcommand 'list'");
			} else if (positional[1] != "list") {
				return UsageFailure("dep requires the read-only subcommand 'list'");
			} else if (!showHelp && positional.length < 3) {
				return UsageFailure("requires at least 1 arg(s), only received 0");
			}
			if (depDirection == "up")
				return OutputFailure(output, "dep list --direction=up is not yet available in the read-only profile");
			showIds = positional.length > 2 ? positional.slice(2) : [];
		}
		if (name == "children" && !showHelp) {
			final received = positional.length - 1;
			if (received != 1)
				return UsageFailure('accepts 1 arg(s), received ${received}');
			listParent = positional[1];
			listAll = true;
		}
		if (readyAwareUsageFailure != "")
			return name == "ready" ? OutputFailure(output, readyAwareUsageFailure) : UsageFailure(readyAwareUsageFailure);
		if (shorthandS != "") {
			if (name == "ready")
				listSort = shorthandS;
			else
				listStatus = shorthandS;
		}
		if (listPriorityRaw != "") {
			if (name == "ready") {
				final priority = parseSignedInt(listPriorityRaw);
				if (priority == null)
					return UsageFailure('invalid argument "${listPriorityRaw}" for "-p, --priority" flag: expected an integer');
				listPriority = IntPresent(priority);
			} else {
				final priority = parsePriority(listPriorityRaw);
				if (priority < 0)
					return UsageFailure('invalid priority: ${listPriorityRaw} (must be 0-4 or P0-P4)');
				listPriority = IntPresent(priority);
			}
		}
		if (listSort != "") {
			if (name == "ready" && !isReadySort(listSort))
				return OutputFailure(output, 'invalid sort policy \'${listSort}\'. Valid values: hybrid, priority, oldest');
			if ((name == "list" || name == "search") && !isListSort(listSort))
				return UsageFailure('invalid sort field "${listSort}" (valid: priority, created, updated, closed, status, id, title, type, assignee)');
		}
		if (name != "count" && countOnlyFlags.length > 0)
			return UsageFailure('unknown flag: ${countOnlyFlags[0]}');
		if (name != "search" && searchQueryUsed)
			return UsageFailure("unknown flag: --query");
		if (name != "query" && queryParseOnlyUsed)
			return UsageFailure("unknown flag: --parse-only");
		if (name != "stale" && staleDaysUsed)
			return UsageFailure("unknown flag: --days");
		if (name != "orphans" && orphansDetailsUsed)
			return UsageFailure("unknown flag: --details");
		if (name != "orphans" && orphansFixUsed)
			return UsageFailure("unknown flag: --fix");
		if (name != "dep" && depDirectionUsed)
			return UsageFailure("unknown flag: --direction");
		if (name == "count" && countGroupConflict)
			return UsageFailure("only one --by-* flag can be specified");
		if (name != "list") {
			var incompatibleListFlag = "";
			for (flag in listOnlyFlags)
				if (!(name == "children" && flag == "--pretty")
					&& !(name == "show" && flag == "--long")
					&& !(name == "count" && isCountFilterFlag(flag))
					&& !(name == "ready" && isReadyFilterFlag(flag))
					&& !(name == "search" && isSearchFilterFlag(flag))
					&& !(name == "query" && isQueryFilterFlag(flag))
					&& !(name == "stale" && isStaleFilterFlag(flag))
					&& !(name == "orphans" && isOrphansFilterFlag(flag))
					&& !(name == "dep" && (flag == "--type" || flag == "-t"))) {
					incompatibleListFlag = flag;
					break;
				}
			if (incompatibleListFlag != "") {
				if (StringTools.startsWith(incompatibleListFlag, "--"))
					return UsageFailure('unknown flag: ${incompatibleListFlag}');
				return UsageFailure('unknown shorthand flag: \'${incompatibleListFlag.charAt(1)}\' in ${incompatibleListFlag}');
			}
		}
		if (name == "list") {
			switch listOffset {
				case IntPresent(value) if (value < 0):
					return UsageFailure("--offset must be >= 0");
				case IntAbsent | IntPresent(_):
			}
			if (listSkipLabels) {
				final conflicts = skipLabelsConflicts(listLabels, listLabelsAny, listLabelPattern, listLabelRegex, listExcludeLabels, listNoLabels);
				if (conflicts.length > 0)
					return ExactFailure(formatSkipLabelsConflict(conflicts), 2);
			}
			if (listPinned && listNoPinned)
				return UsageFailure("--pinned and --no-pinned are mutually exclusive");
			if (listParent != "" && listNoParent)
				return UsageFailure("--parent and --no-parent are mutually exclusive");
			if (listBrief && watchMode)
				return UsageFailure("--watch cannot be combined with --brief");
			if (listDepsMode != "") {
				if (listDepsMode != "scheduling" && listDepsMode != "all")
					return UsageFailure('invalid --deps value "${listDepsMode}" (valid: scheduling, all)');
				if (output == OutputMode.Json)
					return OutputFailure(output, "--deps is not supported with --json output");
				if (listFormat != "")
					return UsageFailure("--deps is not supported with --format output");
				if (listFlat)
					return UsageFailure("--deps requires the tree view and cannot be combined with --flat");
				if (watchMode)
					return OutputFailure(output, "--deps is not supported with --watch");
			}
			switch listOffset {
				case IntPresent(value) if (value > 0 && listSort == "id"):
					return UsageFailure("--offset is not supported with --sort id (sort requires fetching the full result set)");
				case IntAbsent | IntPresent(_):
			}
			if (!showHelp) {
				switch listMaxRows {
					case IntPresent(_):
					case IntAbsent:
						final rawMaxRows = environment.value("BEADS_MAX_ROWS");
						if (rawMaxRows != "") {
							final parsedMaxRows = parseSignedInt(rawMaxRows);
							if (parsedMaxRows == null || parsedMaxRows < 0) {
								listWarning = 'Warning: BEADS_MAX_ROWS=${haxe.Json.stringify(rawMaxRows)} is not a non-negative integer; ignoring.\n';
							} else {
								listMaxRows = IntPresent(parsedMaxRows);
								listMaxRowsSource = "BEADS_MAX_ROWS";
							}
						}
				}
			}
		}
		if (name == "ready") {
			if (listBrief && output != OutputMode.Json)
				return OutputFailure(output, "--brief requires --json; the text renderings print none of the fields it omits");
			if (listBrief && readyClaim)
				return OutputFailure(output, "--claim cannot be combined with --brief");
			if (listBrief && readyGated)
				return OutputFailure(output, "--gated cannot be combined with --brief");
			if (listBrief && readyMolecule != "")
				return OutputFailure(output, "--mol cannot be combined with --brief");
			if (listBrief && readyExplain)
				return OutputFailure(output, "--explain cannot be combined with --brief");
			if (!showHelp) {
				switch listMaxRows {
					case IntPresent(_):
					case IntAbsent:
						final rawMaxRows = environment.value("BEADS_MAX_ROWS");
						if (rawMaxRows != "") {
							final parsedMaxRows = parseSignedInt(rawMaxRows);
							if (parsedMaxRows == null || parsedMaxRows < 0) {
								listWarning = 'Warning: BEADS_MAX_ROWS=${haxe.Json.stringify(rawMaxRows)} is not a non-negative integer; ignoring.\n';
							} else {
								listMaxRows = IntPresent(parsedMaxRows);
								listMaxRowsSource = "BEADS_MAX_ROWS";
							}
						}
				}
			}
		}
		if (name == "search") {
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
			switch listOffset {
				case IntPresent(value) if (value < 0):
					return UsageFailure("--offset must be non-negative");
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
		if (name != "status" && name != "stats" && (statusSkipBlocked || statusAssigned))
			return UsageFailure('status flag used with command "${name}"');
		if (name != "info" && (infoSchema || infoWhatsNew))
			return UsageFailure('info flag used with command "${name}"');
		if (name != "show"
			&& name != "view"
			&& (showShort || showCurrent || showThread || showRefs || showChildren || showIncludeDependents || showIncludeComments || showBriefDependencies))
			return UsageFailure('show flag used with command "${name}"');
		if (name != "show" && name != "view" && name != "list" && watchMode)
			return UsageFailure('show flag used with command "${name}"');
		if (name != "show" && name != "view" && name != "list" && name != "count" && issueFlagIds.length > 0)
			return UsageFailure("unknown flag: --id");
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
				output: output,
				actor: actor,
				directory: directory,
				databasePath: databasePath,
				databaseName: databaseName,
				global: global,
				cpuProfile: cpuProfile,
				memProfilePath: memProfilePath,
				showHelp: showHelp,
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
				depType: depTypeRaw
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
			return parsedCommand(Command.DepList);
		if (name == "list")
			return parsedCommand(Command.List);
		if (name == "show" || name == "view")
			return parsedCommand(Command.Show);
		return helpCommand ? UsageFailure('unknown command "${name}"') : UnknownCommand(name);
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
			return 'invalid --metadata-field: expected key=value, got "${raw}"';
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
			return 'invalid ${flag}: invalid metadata key "${key}": must match ^[a-zA-Z_][a-zA-Z0-9_./]*$$';
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

	static function parsePriority(value:String):Int {
		final raw = value.length == 2 && (value.charAt(0) == "P" || value.charAt(0) == "p") ? value.substr(1) : value;
		final parsed = parseSignedInt(raw);
		return parsed != null && parsed >= 0 && parsed <= 4 ? parsed : -1;
	}

	static function parseSignedInt(value:String):Null<Int> {
		if (value == "")
			return null;
		var index = value.charAt(0) == "-" ? 1 : 0;
		if (index == value.length)
			return null;
		var result = 0;
		while (index < value.length) {
			final code = value.charCodeAt(index);
			if (code < 48 || code > 57)
				return null;
			result = result * 10 + code - 48;
			index++;
		}
		return value.charAt(0) == "-" ? -result : result;
	}

	static function isListSort(value:String):Bool {
		return switch value {
			case "priority" | "created" | "updated" | "closed" | "status" | "id" | "title" | "type" | "assignee": true;
			case _: false;
		};
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
