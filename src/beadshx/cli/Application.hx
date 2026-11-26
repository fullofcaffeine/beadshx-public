package beadshx.cli;

import beadshx.relation.RelationRead.prepareRelationRead;
import beadshx.relation.RelationRead.RelationDirection;
import beadshx.relation.RelatedIssue;
import beadshx.relation.DependencyCycle;
import beadshx.relation.DependencyTree.TreeDirection;
import beadshx.relation.DependencyTree.TreeNode;
import beadshx.relation.DependencyTree.parseTreeDirection;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.cli.ListFormatView.renderListDigraph;
import beadshx.cli.ListFormatView.renderListDot;
import beadshx.cli.ListTemplateView.renderListTemplate;
import beadshx.store.IssueListFormat.selectIssueListFormat;
import beadshx.relation.AllGraphs.AllGraphIssue;
import beadshx.relation.AllGraphs.groupAllGraphs;
import beadshx.relation.GraphLayout;
import beadshx.relation.GraphLayout.GraphEdge;
import beadshx.relation.GraphLayout.computeGraphLayout;
import beadshx.relation.GraphExternal.ExternalTargetLookup;
import beadshx.relation.GraphExternal.GraphRowSelection;
import beadshx.relation.GraphExternal.GRAPH_EXTERNAL_UNAVAILABLE;
import beadshx.relation.GraphExternal.selectGraphRows;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.workspace.PrefixRoutes.prefixRouteLeaves;
import beadshx.workspace.RoutePaths.expandRoutePath;
import beadshx.workspace.RoutePaths.sameDirectory;
import beadshx.relation.OpenGraph.OpenGraphIssue;
import beadshx.relation.OpenGraph.filterOpenGraph;
import beadshx.relation.OpenGraph.isOpenGraphStatus;
import beadshx.cli.AgentOutput.fitsMetadataLine;
import beadshx.cli.AgentOutput.markdownWrapWidth;
import beadshx.cli.LeaseLine.leaseLine;
import beadshx.cli.GraphViews.renderAllGraphViews;
import beadshx.cli.GraphViews.renderGraphBox;
import beadshx.cli.GraphViews.renderGraphCompact;
import beadshx.cli.GraphViews.renderGraphDot;
import beadshx.cli.GraphViews.renderGraphHtml;
import beadshx.cli.GraphViews.renderGraphVisual;
import beadshx.cli.StatusIcon.statusIcon;
import beadshx.cli.TerminalStyles.shouldUseColor;
import beadshx.cli.CatalogViews.renderStatusesJson;
import beadshx.cli.CatalogViews.renderStatusesText;
import beadshx.cli.CatalogViews.renderTypeSectionsJson;
import beadshx.cli.CatalogViews.renderTypeSectionsText;
import beadshx.cli.CatalogViews.renderTypesJson;
import beadshx.cli.CatalogViews.renderTypesText;
import beadshx.cli.ConfigView.configHelp;
import beadshx.cli.ConfigView.configSubcommandHelp;
import beadshx.cli.ConfigView.renderBackupEnabledJson;
import beadshx.cli.ConfigView.renderBackupEnabledText;
import beadshx.cli.ConfigView.renderConfigGetJson;
import beadshx.cli.ConfigView.renderConfigGetText;
import beadshx.cli.ConfigView.renderConfigListJson;
import beadshx.cli.ConfigView.renderConfigListText;
import beadshx.cli.ConfigView.configShowHelp;
import beadshx.cli.ConfigView.configDriftHelp;
import beadshx.cli.ConfigView.configValidateHelp;
import beadshx.config.ConfigDrift.DriftItem;
import beadshx.config.ConfigDrift.DriftStatus;
import beadshx.config.ConfigDrift.HookStatus;
import beadshx.config.ConfigDrift.GIT_HOOK_NAMES;
import beadshx.config.ConfigDrift.hasDrift;
import beadshx.config.ConfigDrift.hookStatus;
import beadshx.config.ConfigDrift.hookWarnings;
import beadshx.config.ConfigDrift.hooksDriftItems;
import beadshx.config.ConfigDrift.plainItem;
import beadshx.config.ConfigDrift.remoteOpenFailureItem;
import beadshx.config.ConfigDrift.renderDriftJson;
import beadshx.config.ConfigDrift.renderDriftText;
import beadshx.config.ConfigDrift.serverDriftItem;
import beadshx.config.ConfigProbes;
import beadshx.config.DeprecatedServerPort;
import beadshx.config.ConfigShow.WorkspaceMetadataFields;
import beadshx.config.ConfigShow.readMetadataFields;
import beadshx.config.ConfigShow.readLegacyConfigFields;
import beadshx.config.ConfigShow.metadataLoadFailure;
import beadshx.config.ConfigShow.SHARED_SERVER_EMBEDDED_NOTICE;
import beadshx.config.ConfigShow.pinsEmbeddedMode;
import beadshx.config.ConfigShow.metadataLoadWarning;
import beadshx.config.ConfigValidate.MetadataFacts;
import beadshx.config.ConfigValidate.metadataConfigIssues;
import beadshx.config.ConfigValidate.renderValidationJson;
import beadshx.config.ConfigValidate.renderValidationText;
import beadshx.config.ConfigValidate.syncConfigIssues;
import beadshx.config.ConfigValidate.validationIssues;
import beadshx.config.ConfigValidate.yamlConfigIssues;
import beadshx.cli.ConfigView.renderConfigShowJson;
import beadshx.cli.ConfigView.renderConfigShowText;
import beadshx.config.ConfigShow.ConfigShowEntry;
import beadshx.config.ConfigShow.filterConfigShowEntries;
import beadshx.config.ConfigShow.layeredEntries;
import beadshx.config.ConfigShow.readWorkspaceMetadata;
import beadshx.config.ConfigShow.sortConfigShowEntries;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.store.CustomConfig.effectiveCustomStatuses;
import beadshx.store.CustomConfig.effectiveCustomTypes;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.config.ConfigKeys.isKvPlaneKey;
import beadshx.config.ConfigKeys.isUserGlobalKey;
import beadshx.config.ConfigKeys.isYamlOnlyKey;
import beadshx.config.LayeredConfig;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.config.LayeredConfig.gitBeadsRole;
import beadshx.config.LayeredConfig.gitHasRemote;
import beadshx.config.LayeredConfig.goQuote;
import beadshx.config.LayeredConfig.userConfigYamlDisplayPath;
import beadshx.config.LayeredConfig.userConfigYamlPresent;
import beadshx.config.UserRole;
import beadshx.config.AutoRouting.AutoRoute;
import beadshx.config.AutoRouting.autoRouteNote;
import beadshx.config.AutoRouting.autoRouteTarget;
import beadshx.config.AutoRouting.routedListServerUnavailable;
import beadshx.config.AutoRouting.routedListUnavailable;
import beadshx.config.AutoRouting.routedLookupUnavailable;
import beadshx.config.ConfigKeys.CONFIG_ROUTE_UNAVAILABLE;
import beadshx.cli.CommentsView.MISPLACED_COMMENTS_LIST;
import beadshx.cli.CommentsView.commentTimestamp;
import beadshx.cli.CommentsView.rfc3339Millis;
import beadshx.cli.CommentsView.renderCommentsJson;
import beadshx.cli.EventsView.eventsExportHelp;
import beadshx.cli.EventsView.eventsHelp;
import beadshx.cli.EventsView.eventsTailHelp;
import beadshx.cli.EventsView.eventsTruncatedHint;
import beadshx.cli.EventsView.renderEventsRecords;
import beadshx.cli.EventsView.renderEventsTruncatedJson;
import beadshx.config.WorkspaceEnvironment;
import beadshx.store.EmbeddedDatabaseLookup.DEFAULT_EMBEDDED_DATABASE;
import beadshx.store.EmbeddedDatabaseLookup.embeddedDatabaseExists;
import beadshx.store.DoltStoreOpen;
import beadshx.store.EmbeddedDatabaseLookup.isEmbeddedDatabaseIdentifier;
import beadshx.store.EmbeddedDatabaseLookup.MissingDatabaseEntry;
import beadshx.store.EmbeddedDatabaseLookup.missingConfigurationWarning;
import beadshx.store.EmbeddedDatabaseLookup.missingDatabaseEntry;
import beadshx.store.EmbeddedDatabaseName.resolveEmbeddedDatabaseName;
import beadshx.store.EventsJournal.EventsJournalRead;
import beadshx.store.InvalidDatabaseName;
import beadshx.store.InvalidDatabaseName.InvalidDatabaseNameStep;
import beadshx.store.RemoteMigrateGate.RemoteGateStop;
import beadshx.store.RemoteMigrateGate.RemoteGateWrite;
import beadshx.store.RemoteMigrateGate.remoteGateJson;
import beadshx.store.RemoteMigrateGate.remoteGateReadOnlyWarning;
import beadshx.store.RemoteMigrateGate.remoteGateUserMessage;
import beadshx.store.SchemaSkew.EmbeddedOpenIntent;
import beadshx.store.SchemaSkew.SCHEMA_SKEW_ESCAPE_HINT;
import beadshx.store.SchemaSkew.SchemaSkewBoundary;
import beadshx.store.SchemaSkew.SchemaSkewWarning;
import beadshx.store.SchemaSkew.SchemaSkewRefusal;
import beadshx.store.SchemaSkew.schemaSkewOpenError;
import beadshx.store.SchemaSkew.schemaSkewRefusalError;
import beadshx.store.SchemaSkew.schemaSkewUserMessage;
import beadshx.store.TaskSnapshot;
import beadshx.store.EventsJournal.eventsTruncatedMessage;
import beadshx.cli.HistoryView.renderHistoryEventsJson;
import beadshx.cli.HistoryView.renderHistoryEventsText;
import beadshx.cli.HistoryView.renderHistoryJson;
import beadshx.cli.HistoryView.renderHistoryText;
import beadshx.store.IssueHistory.HISTORY_ROUTE_UNAVAILABLE;
import beadshx.cli.LabelsView.LABEL_LIST_ALL_ROUTE_UNAVAILABLE;
import beadshx.cli.LabelsView.countLabels;
import beadshx.cli.LabelsView.renderIssueLabelsHuman;
import beadshx.cli.LabelsView.renderIssueLabelsJson;
import beadshx.cli.LabelsView.renderLabelCountsHuman;
import beadshx.cli.LabelsView.renderLabelCountsJson;
import beadshx.store.SqlGraphReader.AllGraphLoad;
import beadshx.store.SqlGraphReader.GraphDependency;
import beadshx.store.SqlGraphReader.GraphSubgraph;
import beadshx.store.SqlBlockedReader.BlockedIssue;
import beadshx.store.GoReadonlyStore.BLOCKED_ROUTE_UNAVAILABLE;
import beadshx.identity.ActorPort;
import beadshx.git.GitHistoryPort;
import beadshx.cli.InfoChanges.VersionChange;
import beadshx.workspace.LegacyUpgradeGuard;
import beadshx.workspace.LegacyUpgradeGuard.LegacyGuardOutcome;
import beadshx.workspace.RedirectLookups;
import beadshx.workspace.RedirectSource;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspaceGate;
import beadshx.workspace.WorkspaceGate.WorkspaceGateOutcome;
import beadshx.workspace.WorkspaceLocation;
import beadshx.workspace.WorkspacePort;
import beadshx.store.InfoSnapshot;
import beadshx.store.EpicProgress;
import beadshx.store.IssueComment;
import beadshx.store.IssueDependency;
import beadshx.store.IssueDetails;
import beadshx.store.IssueDetailsLookup;
import beadshx.store.IssueDetailsRequest;
import beadshx.store.IssueLookup;
import beadshx.store.IssueQueryPort;
import beadshx.store.CountResult;
import beadshx.store.ReadyLoadResult;
import beadshx.store.ReadyResult;
import beadshx.store.ReadyTotal;
import beadshx.store.IssueListDependency;
import beadshx.store.IssueListItem;
import beadshx.store.IssueListPage;
import beadshx.store.IssueListRequest;
import beadshx.store.IssueListRequests;
import beadshx.store.IssueListResult;
import beadshx.store.IssueRecord;
import beadshx.store.IssueStatus;
import beadshx.store.IssueSummary;
import beadshx.store.IssueType;
import beadshx.store.OptionalInt;
import beadshx.store.PingSnapshot;
import beadshx.store.ReadonlyStorePort;
import beadshx.store.StatusSnapshot;
import beadshx.store.StoreResult;
import beadshx.store.IssueLongFields;
import beadshx.store.StaleIssue;
import beadshx.query.QuerySyntax;
import beadshx.query.QuerySyntax.QuerySyntaxResult;
import beadshx.query.QueryPage;
import beadshx.query.QueryPage.QueryPageResult;
import beadshx.query.QueryPlan.QueryExecutionPlan;
import beadshx.query.QueryPlanner;
import beadshx.store.OrphanCandidate;
import beadshx.store.OrphanCandidateScan;
import beadshx.store.OrphanIssue;
import beadshx.store.QueryRowResult;
import beadshx.store.QueryStorageRequest;
import beadshx.store.QueryStorageRequest.QueryFetch;
import beadshx.ready.MoleculeDependency;
import beadshx.ready.MoleculeParallelInfo;
import beadshx.ready.MoleculeReady;
import beadshx.ready.MoleculeReadyAnalysis;
import beadshx.ready.MoleculeStep;
import beadshx.ready.MoleculeSubgraph;
import beadshx.ready.GatedMolecule;
import beadshx.ready.GatedReady;
import beadshx.ready.ReadyExplain;
import beadshx.ready.ReadyExplain.BlockedEntry;
import beadshx.ready.ReadyExplanation;
import beadshx.relation.DependencyRead;
import beadshx.profile.ProfilePort;
import haxe.Json;
import haxe.io.Path;
import haxe.ds.StringMap;

/**
	A read that upstream may route to another repository (see
	Application.lookupIssueWithRouting): this store's answer, which upstream
	also gives after any routing that reads this store again, or the refusal
	of a read that upstream would answer from another repository.
**/
private enum RoutedRead<T> {
	ReadHere(value:T);
	ReadElsewhere;
}

/** The issues and complete rows that `bd graph` keeps from what it loaded (see Application.keepGraphRows). */
private typedef KeptGraph = {
	final issues:Array<RelatedIssue>;
	final rows:Array<GraphDependency>;
}

/** One group of `bd graph --all`: its root, its issues in walk order and its complete rows. */
private typedef AllGraph = {
	final root:RelatedIssue;
	final issues:Array<RelatedIssue>;
	final dependencies:Array<GraphDependency>;
}

private typedef CompatibilityIdentity = {
	final project:String;
	final version:String;
	final commit:String;
}

private typedef VersionDocument = {
	final schema_version:Int;
	final version:String;
	final build:String;
	final compatibility:CompatibilityIdentity;
	final identity:String;
}

private typedef DiagnosticDocument = {
	final schema_version:Int;
	final error:String;
	final message:String;
	final hint:String;
}

/** How upstream's root pre-run treats a selected workspace whose metadata.json does not load. */
private enum MetadataLoadRole {
	/** The pre-run warns, then stops the command; `opensStore` tells a store command from `where`. */
	MetadataStopsCommand(opensStore:Bool);

	/** The pre-run warns and the command runs: `version`, the root help and `bd help <command>`. */
	MetadataWarnsOnly;

	/** Cobra prints the help without the pre-run: a --help flag, or a command group without its own action. */
	MetadataUnread;
}

private enum DatabaseSelectionValidation {
	Accepted;
	PlainFailure(message:String);
	ModeAwareFailure(message:String);
}

private typedef PingDocument = {
	final schema_version:Int;
	final status:String;
	final resolve_ms:Int;
	final store_ms:Int;
	final query_ms:Int;
	final total_ms:Int;
}

private typedef WhatsNewDocument = {
	final schema_version:Int;
	final current_version:String;
	final recent_changes:Array<VersionChange>;
}

private typedef StatusSummaryCore = {
	final total_issues:Int;
	final open_issues:Int;
	final in_progress_issues:Int;
	final closed_issues:Int;
	final deferred_issues:Int;
	final pinned_issues:Int;
	final epics_eligible_for_closure:Int;
	final average_lead_time_hours:Float;
}

private typedef StatusSummaryDocument = {
	> StatusSummaryCore,
	final blocked_issues:Int;
	final ready_issues:Int;
}

private typedef SkippedStatusSummaryDocument = {
	> StatusSummaryCore,
	final blocked_issues:Null<Int>;
	final ready_issues:Null<Int>;
}

private typedef StatusDocument = {
	final schema_version:Int;
	final summary:StatusSummaryDocument;
}

private typedef SkippedStatusDocument = {
	final schema_version:Int;
	final summary:SkippedStatusSummaryDocument;
	final blocked_count_skipped:Bool;
}

private typedef HumanDependencyRelation = {
	final canonical:String;
	final outgoingHeading:String;
	final incomingHeading:String;
	final outgoingGlyph:String;
	final incomingGlyph:String;
	final order:Int;
	final related:Bool;
}

private typedef HumanDependencyGroup = {
	final relation:HumanDependencyRelation;
	final dependencies:Array<IssueDependency>;
}

private typedef ListChildGroup = {
	final parent:String;
	final children:Array<IssueListItem>;
}

private typedef ListDependencyPresentation = {
	final label:String;
	final scheduling:Bool;
}

private typedef ListDependencyRow = {
	final label:String;
	final target:String;
	final title:String;
}

private typedef ShowDependencyGroup = {
	final issueId:String;
	final items:Array<IssueDependency>;
}

private typedef ThreadEntry = {
	final issue:IssueDetails;
	final parentId:String;
}

/** An issue row with every field that upstream's full issue read fills. */
private typedef FullIssueRecord = {
	> IssueRecord,
	final longFields:IssueLongFields;
}

private enum HumanShowMode {
	StandardShow;
	WatchedShow;
}

/** Where show prints a closed issue's close reason. */
private enum HumanCloseReason {
	NoCloseReason;

	/** One metadata line, without its line feed. */
	CloseReasonLine(line:String);

	/** A CLOSE REASON section with its leading blank line and final line feed, after the metadata lines. */
	CloseReasonSection(section:String);
}

/** What a command that loads layered config checks before upstream's pre-run would open a store. */
private typedef ConfigPreflightInput = {
	/** The config reloaded for the selected workspace, which upstream's shared-server check reads. */
	final config:LayeredConfig;

	final location:WorkspaceLocation;

	/** Whether upstream's store open would reach the shared server in shared-server mode (see reachesSharedServer). */
	final reachesSharedServer:Bool;
}

/** One stored issue_prefix read: the workspace directory and database it came from, and the value. */
private typedef StoredPrefixRead = {
	final key:String;
	final value:String;
}

/** An embedded store that the command opened and no read checked yet; see `Application.uncheckedStore`. */
private typedef UncheckedStore = {
	final beadsDir:String;
	final databaseName:String;
}

/** What a stored issue_prefix read does when the dolt.shared-server setting turns on shared-server mode. */
private enum SharedServerSettingRead {
	/** Upstream's where still reads the embedded database. */
	ReadEmbedded;

	/** The commands that look up partial IDs refuse that mode before they get here; read nothing. */
	ReadNothing;
}

/** Haxe-owned read-only command application. */
final class Application {
	static final identity = "BeadsHX 0.0.0-development (compatible with Beads v1.2.1 at 634cbbc4bc580fa5124f63fdf65d137a46d5b4ff)";
	static final noWorkspaceMessage = "No active beads workspace found.";

	/** utils.ErrAmbiguousID, the one partial-ID resolution failure that `bd history` reports. */
	static final AMBIGUOUS_ISSUE_ID = "ambiguous issue ID: ";

	static final jsonDeprecation = "NOTE: bd --json output format will change in v2.0. Set BD_JSON_ENVELOPE=1 to opt in early. See docs/reference/json-schema.md for migration details.";

	final parser:Parser;
	final output:SchemaSkewWarningOutput;
	final actor:ActorPort;
	final gitHistory:GitHistoryPort;
	final workspace:WorkspacePort;
	final store:ReadonlyStorePort;
	final profiler:ProfilePort;
	final watch:WatchPort;

	/** Upstream's workspace lookups that follow a redirect, with their warnings; shared with the parser's `.env` step. */
	final lookups:RedirectLookups;

	/**
		The workspace that the command bound, which upstream's post-run reads
		to decide its auto-backup lookup (see postRunLookups); null for none.
	**/
	var boundWorkspace:Null<WorkspaceLocation> = null;

	/**
		The directory that BEADS_DIR names when the body of upstream's `where`
		looks its workspace up for the last time (resolveWhereBeadsDir,
		cmd/bd/where.go:54): the directory of its second setup (see
		prepareNoStoreWorkspace). Null when a --db, BEADS_DB or BD_DB path
		selects the workspace, which that lookup derives from the path again.
	**/
	var whereBeadsDir:Null<String> = null;

	var jsonDeprecationEmitted = false;
	var sharedServerNoticeEmitted = false;

	/**
		Whether upstream's internal/ui colors this process's output. `run`
		decides it from the environment before anything else, as upstream's
		package init does, so `.beads/.env` cannot change it; --no-color then
		turns it off.
	**/
	var colors = false;

	/**
		`colors` as `run` decided it, before --no-color. Upstream's cmd/bd
		package builds some styles from internal/ui's colors when the process
		starts, such as the thanks page's text styles, and --no-color does not
		change them.
	**/
	var startupColors = false;

	/**
		Whether the terminal has a dark background, as `run` asked it when the
		process started with colors on; true when colors were off, and unused
		then. Upstream asks once per process, in internal/ui's package init, and
		every colored view uses that one answer.
	**/
	var darkBackground = true;

	/** The styles for `colors`, built when a view first renders with them; see `terminalStyles`. */
	var builtStyles:Null<TerminalStyles> = null;

	/** The last stored issue_prefix read, so one command opens its database for the prefix at most once. */
	var storedPrefixRead:Null<StoredPrefixRead> = null;

	/**
		The embedded store that the command opened at upstream's pre-run point,
		until something checks its schema. Upstream checks at that open, before
		the command body; here the first read checks. A failure that the body
		reports before any read runs the check first (`checkSchemaBeforeFailure`).
	**/
	var uncheckedStore:Null<UncheckedStore> = null;

	/**
		Set by validateStoreSelection for a server-mode store, whose native open
		comes later: upstream's warnMultipleDatabases follows the open (see
		finishStoreOpen).
	**/
	var databaseLookupsAfterOpen = false;

	public function new(parser:Parser, output:OutputPort, actor:ActorPort, gitHistory:GitHistoryPort, workspace:WorkspacePort, store:ReadonlyStorePort,
			profiler:ProfilePort, watch:WatchPort, ?lookups:RedirectLookups) {
		this.lookups = lookups != null ? lookups : new RedirectLookups();
		this.parser = parser;
		this.output = new SchemaSkewWarningOutput(output);
		this.actor = actor;
		this.gitHistory = gitHistory;
		this.workspace = workspace;
		this.store = store;
		this.profiler = profiler;
		this.watch = watch;
	}

	/**
		Runs one process's command. With colors on, upstream's internal/ui
		package init first asks the terminal for its background, before any
		output, for every command. Upstream's cmd/bd package init then loads
		config.yaml before it parses any argument, so a file that does not parse
		prints its warning next, once, for every command, and the command
		continues with what loaded. That load reads the process's own directory,
		never -C.
	**/
	public function run(args:Array<String>):Int {
		colors = shouldUseColor(environmentValue, output.isStdoutTerminal());
		startupColors = colors;
		if (colors)
			darkBackground = output.hasDarkBackground();
		final startup = LayeredConfig.atStartup();
		if (startup.failure != null)
			output.writeStderr('Warning: failed to initialize config: ${startup.failure}\n');
		final parsed = parser.parse(args);
		// The parser's -C and .env steps ran upstream's first lookups; upstream prints them only when its pre-run runs.
		switch parsed {
			case Parsed(invocation) if (runsPreRun(invocation)):
				lookups.release(text -> output.writeStderr(text));
			case Parsed(_) | UsageFailure(_) | GroupUsageFailure(_, _) | OutputFailure(_, _) | ExactFailure(_, _) | UnknownCommand(_):
				lookups.discard();
		}
		return switch parsed {
			case UsageFailure(message):
				output.writeStderr('Error: ${message}\n');
				1;
			case GroupUsageFailure(message, group):
				final help = commandHelp(group);
				output.writeStderr('Error: ${message}\n${help.substr(help.indexOf("Usage:\n"))}\n');
				1;
			case OutputFailure(mode, message):
				runModeAwareFailure(mode, message);
			case ExactFailure(message, exitCode):
				output.writeStderr(message);
				exitCode;
			case UnknownCommand(name):
				output.writeStderr('Error: unknown command "${name}" for "bd"\n');
				output.writeStderr("Run 'bd --help' for usage.\n");
				1;
			case Parsed(invocation):
				if (invocation.cpuProfile && !invocation.showHelp && usesStore(invocation.command))
					profiler.startCpu(commandName(invocation.command));
				final exitCode = SchemaSkewBoundary.runCommand(() -> runInvocation(invocation), refusal -> runSchemaSkewRefusal(invocation, refusal));
				// A command that wrote nothing after its schema check still prints the escape-hatch warning.
				output.flushHeldWarning();
				if (exitCode == 0 && runsPreRun(invocation))
					postRunLookups(invocation);
				if (exitCode == 0 && !invocation.showHelp)
					profiler.finish(invocation.memProfilePath);
				exitCode;
		};
	}

	/**
		Whether upstream's root pre-run runs for the command, and so its
		workspace lookups: cobra shows help for --help and for the label,
		config and events groups without it. `bd help` is a command of its own,
		whose pre-run runs.
	**/
	static function runsPreRun(invocation:Invocation):Bool {
		if (invocation.helpCommand)
			return true;
		return !invocation.showHelp && switch invocation.command {
			case Label | Events | Config: false;
			case _: true;
		};
	}

	/**
		Upstream's PersistentPostRun lookups after a command that succeeded
		(cmd/bd/main.go:1755-1876). Strict read-only mode runs no maintenance.
		Under a proxied server only the events-journal prune looks up the
		workspace (:1771). Otherwise the auto-backup check (:1834,
		maybeAutoBackup) asks GetRepoContext, through primeHasGitRemote
		(cmd/bd/prime.go:347), unless BD_GIT_HOOK is 1, backup.enabled is set
		or the command uses a SQL server (backup_auto.go:40); then the prune
		finds the workspace again (:1875).
	**/
	function postRunLookups(invocation:Invocation):Void {
		if (lookups.followsNothing())
			return;
		final location = boundWorkspace;
		final config = location != null ? LayeredConfig.forWorkspace(location.path) : LayeredConfig.atStartup();
		if (strictReadonly(invocation, config))
			return;
		final proxied = location != null && location.proxiedServer;
		if (!proxied
			&& environmentValue("BD_GIT_HOOK") != "1"
			&& config.source("backup.enabled") == DefaultSource
			&& !config.sharedServerMode()
			&& (location == null || !opensServerStore(location)))
			lookups.getRepoContext();
		if (invocation.helpCommand || prunesEventsJournal(invocation.command))
			lookups.findBeadsDir();
	}

	/**
		Upstream shouldAutoPruneEventsJournal (cmd/bd/events_journal.go:145-156)
		for a command that may run maintenance: not one of upstream's read-only
		commands by cobra's leaf name (readOnlyCommands, cmd/bd/main.go:155-172),
		and not under `bd events`.
	**/
	static function prunesEventsJournal(command:Command):Bool {
		return command != Events && !isReadOnlyCommand(command);
	}

	/** Upstream isReadOnlyCommand (cmd/bd/main.go:155-179): the command is in readOnlyCommands by cobra's leaf name. */
	static function isReadOnlyCommand(command:Command):Bool {
		return switch command {
			case List | Ready | Show | Count | Search | Query | Graph | Blocked | Comments | Ping | DepList | ConfigList | ConfigShow | LabelList |
				EventsTail | EventsExport: true;
			case RootHelp | Version | Where | Info | Status | Stale | Orphans | Children | DepCycles | DepTree | GraphCheck | History | Types | Statuses |
				Config | ConfigGet | ConfigValidate | ConfigDrift | Label | LabelListAll | Snapshot | Events: false;
		};
	}

	/**
		How upstream's pre-run opens the embedded store (cmd/bd/store_factory.go):
		none for a SQL server, then strict read-only mode for the bound
		workspace, then the command's classification as a read.
	**/
	function embeddedOpenIntent(invocation:Invocation):EmbeddedOpenIntent {
		final location = boundWorkspace;
		if (invocation.global || (location != null && (location.proxiedServer || opensServerStore(location))))
			return NoEmbeddedOpen;
		final config = location != null ? LayeredConfig.forWorkspace(location.path) : LayeredConfig.atStartup();
		if (strictReadonly(invocation, config))
			return StrictReadOnlyOpen;
		return isReadOnlyCommand(invocation.command) ? ReadOnlyCommandOpen : PlainOpen;
	}

	static function usesStore(command:Command):Bool {
		return switch command {
			case Info | Ping | Status | Count | Ready | Search | Query | Stale | Orphans | Children | DepList | DepCycles | DepTree | GraphCheck | Graph |
				Blocked | Comments | History | EventsTail | EventsExport | LabelList | LabelListAll | List | Show | Types | Statuses | ConfigGet |
				ConfigList | ConfigShow | ConfigValidate | ConfigDrift | Snapshot: true;
			case RootHelp | Version | Where | Label | Events | Config: false;
		};
	}

	static function commandName(command:Command):String {
		return switch command {
			case Info: "info";
			case Ping: "ping";
			case Status: "status";
			case Count: "count";
			case Ready: "ready";
			case Search: "search";
			case Query: "query";
			case Stale: "stale";
			case Orphans: "orphans";
			case Children: "children";
			case DepList: "dep-list";
			case DepCycles: "dep-cycles";
			case DepTree: "dep-tree";
			case GraphCheck: "graph-check";
			case Graph: "graph";
			case Blocked: "blocked";
			case Comments: "comments";
			case History: "history";
			case Events: "events";
			case EventsTail: "tail";
			case EventsExport: "export";
			case Types: "types";
			case Statuses: "statuses";
			case Config: "config";
			// Upstream names a profile after cobra's leaf command name.
			case ConfigGet: "get";
			case ConfigList: "list";
			case ConfigShow: "show";
			case ConfigValidate: "validate";
			case ConfigDrift: "drift";
			case Label: "label";
			case LabelList: "list";
			case LabelListAll: "list-all";
			case List: "list";
			case Show: "show";
			case Snapshot: "snapshot";
			case RootHelp: "bd";
			case Version: "version";
			case Where: "where";
		};
	}

	/** The full command name, such as `dep tree` or `config get`, as the store refusals print it. */
	static function commandPath(command:Command):String {
		return switch command {
			case DepList: "dep list";
			case DepCycles: "dep cycles";
			case DepTree: "dep tree";
			case GraphCheck: "graph check";
			case EventsTail: "events tail";
			case EventsExport: "events export";
			case ConfigGet: "config get";
			case ConfigList: "config list";
			case ConfigShow: "config show";
			case ConfigValidate: "config validate";
			case ConfigDrift: "config drift";
			case LabelList: "label list";
			case LabelListAll: "label list-all";
			case Info | Ping | Status | Count | Ready | Search | Query | Stale | Orphans | Children | Graph | Blocked | Comments | History | Events | Types |
				Statuses | Config | Label | List | Show | Snapshot | RootHelp | Version | Where:
				commandName(command);
		};
	}

	function runInvocation(invocation:Invocation):Int {
		// Upstream's pre-run turns colors off for --no-color first (applyNoColorFlag).
		if (invocation.noColor)
			colors = false;
		// Upstream's pre-run sets the escape hatch for every store open, before it opens any.
		if (invocation.ignoreSchemaSkew)
			SchemaSkewBoundary.ignoreForProcess();
		SchemaSkewBoundary.useOpenIntent(() -> embeddedOpenIntent(invocation));
		final metadataExit = checkWorkspaceMetadata(invocation);
		if (metadataExit != null)
			return metadataExit;
		if (invocation.showHelp) {
			output.writeStdout(commandHelp(invocation.command));
			return 0;
		}
		if (usesStore(invocation.command) && databaseSettingSelects(invocation)) {
			// Upstream sets up the directory that the path selects once, as for `where`, before it opens the database there.
			prepareNoStoreWorkspace(invocation, 1);
			return runModeAwareFailure(invocation.output, databaseSettingRefusal(commandPath(invocation.command)));
		}
		switch invocation.databaseVariable {
			case UnsupportedPath(name) if (usesStore(invocation.command)):
				return refuseDatabaseVariablePath(invocation, name);
			// `where` set up its directory in checkWorkspaceMetadata; `version` and the help pages show nothing of it.
			case UnsupportedPath(name) if (invocation.command == Where):
				return runModeAwareFailure(invocation.output, databaseVariableRefusal(invocation.command, name));
			case NoVariable | VariablePath(_, _, _) | UnsupportedPath(_):
		}
		return switch invocation.command {
			case RootHelp:
				runRootHelp(invocation);
			case Version:
				runVersion(invocation);
			case Where:
				runWhere(invocation);
			case Info:
				runInfo(invocation);
			case Ping:
				runPing(invocation);
			case Status:
				runStatus(invocation);
			case Count:
				runCount(invocation);
			case Ready:
				runReady(invocation);
			case Search:
				runSearch(invocation);
			case Query:
				runQuery(invocation);
			case Stale:
				runStale(invocation);
			case Orphans:
				runOrphans(invocation);
			case Children:
				runList(invocation);
			case DepList:
				runDepList(invocation);
			case DepCycles:
				runDepCycles(invocation);
			case DepTree:
				runDepTree(invocation);
			case GraphCheck:
				runGraphCheck(invocation);
			case Graph:
				runGraph(invocation);
			case Blocked:
				runBlocked(invocation);
			case Comments:
				runComments(invocation);
			case History:
				runWithIssueQuery(invocation, (query, location) -> runHistoryQuery(invocation, location, query));
			case Events:
				output.writeStdout(eventsHelp(upstreamGlobalFlags()));
				0;
			case EventsTail | EventsExport:
				runWithIssueQuery(invocation, (query, location) -> runEventsRead(invocation, location, query));
			case Types:
				runTypes(invocation);
			case Statuses:
				runStatuses(invocation);
			case Label:
				output.writeStdout(labelHelp());
				0;
			case Config:
				output.writeStdout(configHelp(upstreamGlobalFlags()));
				0;
			case ConfigGet:
				runConfigGet(invocation);
			case ConfigList:
				runConfigList(invocation);
			case ConfigShow:
				runConfigShow(invocation);
			case ConfigValidate:
				runConfigValidate(invocation);
			case ConfigDrift:
				runConfigDrift(invocation);
			case LabelList | LabelListAll:
				runLabel(invocation);
			case List:
				runList(invocation);
			case Show:
				runShow(invocation);
			case Snapshot:
				runSnapshot(invocation);
		};
	}

	/**
		Upstream's root pre-run reads the selected workspace's metadata.json, or
		a legacy config.json, with configfile.LoadForDiscovery before any command
		body runs. When that fails it prints a warning. Its legacy-workspace guard
		then stops `where` and every command that opens a store with the load
		error, as text even under --json. `version`, the root help and `bd help`
		print only the warning. Returns the exit code when the command stops.

		Upstream names the workspace it selected. When a --db path selects it
		for a command that opens a store, that is the path as given, or another
		directory where upstream opens or creates a database, so this build
		refuses instead. `where`, `version` and help pages check the directory
		that upstream derives from the path (see checkNoStoreMetadata).

		When only a legacy config.json exists, upstream's store open rewrites it
		as metadata.json for `where` and every command that opens a store. This
		read-only build refuses those commands there until migration parity
		(M12); `version` and help pages run as upstream does. A command that
		opens a store refuses after its first setup, also when the target of
		the found workspace's own redirect is legacy-only; `where` without a
		database path refuses in its body (see runWhere).

		When the file loads, or there is none, the rest of that guard stops
		`where` and every command that opens a store in a historical SQLite
		workspace, a workspace with a removed or unknown backend, and a legacy
		Dolt workspace (see LegacyUpgradeGuard), also before the rewrite of a
		legacy config.json. Upstream then writes nothing. A command that opens a
		store with a BEADS_DB path first runs the guard's walk for a workspace
		that is not found (see guardUndiscoveredStoreWorkspace); with -C it
		checks the second target of a redirect chain, which upstream's first
		setup takes then.

		Upstream's setup for the selected directory reloads the config first,
		so its reinitialize warning comes before the metadata warning, once.
		When the file loads, `where`, `version` and help pages run that setup
		instead (see prepareNoStoreWorkspace). Commands that open a store run
		it when they take the workspace (see validateStoreSelection).
	**/
	function checkWorkspaceMetadata(invocation:Invocation):Null<Int> {
		var stops = true;
		var opensStore = false;
		switch metadataLoadRole(invocation) {
			case MetadataUnread:
				return null;
			case MetadataStopsCommand(store):
				opensStore = store;
			case MetadataWarnsOnly:
				stops = false;
		}
		// The db setting refusal follows: upstream would select the workspace from that path.
		if (opensStore && databaseSettingSelects(invocation))
			return null;
		if (!opensStore)
			return checkNoStoreMetadata(invocation, stops);
		// A BEADS_DB path selects the workspace only when upstream's FindBeadsDir found none, so its walk runs before FindDatabasePath reads the variable.
		if (invocation.databaseVariable.match(VariablePath(_, _, _))) {
			final stop = guardUndiscoveredStoreWorkspace(invocation);
			if (stop != null)
				return stop;
		}
		final location = switch workspace.discover(invocation.directory, invocation.databasePath) {
			case Found(location): location;
			case NotFound | InvalidSelection(_): return null;
		};
		// A command that opens a store binds the target of the found workspace's own redirect (see
		// discoverStoreWorkspace), whose legacy config.json upstream's FindDatabasePath rewrites too. With -C,
		// upstream's first setup already takes that target, so its first guard reads it.
		var checked = location;
		if (invocation.directory != ""
			|| legacyOnly(WorkspaceEnvironment.storeChainTarget({directory: invocation.directory, databasePath: invocation.databasePath}, location)))
			switch discoverStoreWorkspace(invocation) {
				case Found(target):
					checked = target;
				case NotFound | InvalidSelection(_):
			}
		return checkSelectedMetadata(invocation, location, checked, stops, true);
	}

	/**
		checkWorkspaceMetadata for `where`, `version` and help pages, which
		`stops` tells apart: only `where` runs upstream's legacy-workspace guard
		(guardLegacyNoStoreCommand, cmd/bd/main.go:845-867, :1166).

		Why: upstream's pre-run binds the directory that selectedNoDBBeadsDir
		selects (see noStoreSetupDirectory), loads its metadata.json in that
		setup, which prints the load warning, and guards that directory. For a
		database path it is the directory that resolveCommandBeadsDir derives,
		which can differ from the workspace that this build's discovery finds
		for the path. When it selects none, FindBeadsDir finds none either, and
		`where` runs guardUndiscoveredLegacyWorkspace instead.
		What: for a metadata.json there that does not load, one setup, the
		warning, and for `where` upstream's load error; for a refusal of the
		guard, one setup and that refusal. Then, unless BEADS_DB or BD_DB names
		a path that this build refuses for `where`, the checks of the workspace
		that discovery found (checkSelectedMetadata). How: it only reads.
	**/
	function checkNoStoreMetadata(invocation:Invocation, stops:Bool):Null<Int> {
		final location = switch noStoreMetadataWorkspace(invocation) {
			case Found(location): location;
			case NotFound: null;
			case InvalidSelection(_): return null;
		};
		if (location != null)
			boundWorkspace = location;
		final beadsDir = noStoreSetupDirectory(invocation);
		if (beadsDir == "") {
			prepareNoStoreWorkspace(invocation, 1);
			if (stops) {
				final stop = guardUndiscoveredWorkspace(invocation);
				if (stop != null)
					return stop;
			}
			// The body of `where` looks its directory up again (where.go:50).
			if (noStoreInitializations(invocation) > 1)
				noStoreLookups(invocation);
			return null;
		}
		switch readMetadataFields(beadsDir) {
			case MetadataFieldsUndecodable(error):
				prepareNoStoreWorkspace(invocation, 1);
				output.writeStderr(metadataLoadWarning(beadsDir, error));
				if (!stops)
					return null;
				output.writeStderr(metadataLoadFailure(error));
				return 1;
			case MetadataFields(_) | MetadataAbsent | MetadataFieldsLegacyOnly if (stops):
				switch LegacyUpgradeGuard.check(beadsDir, () -> LayeredConfig.forWorkspace(beadsDir).sharedServerMode()) {
					case GuardRefused(error):
						prepareNoStoreWorkspace(invocation, 1);
						output.writeStderr('Error: ${error}\n');
						return 1;
					case GuardPasses | GuardLoadFailed(_) | GuardUnknown:
				}
			case MetadataFields(_) | MetadataAbsent | MetadataFieldsLegacyOnly | MetadataFieldsUnsupported:
		}
		// The workspace that discovery found for a BEADS_DB or BD_DB path that `where` refuses is not the one upstream reads.
		if (location == null || invocation.databaseVariable.match(UnsupportedPath(_))) {
			prepareNoStoreWorkspace(invocation, noStoreInitializations(invocation));
			return null;
		}
		// With -C, upstream's FindBeadsDir finds the workspace through BEADS_DIR, after its redirect (see noStoreSetupDirectory).
		final pathSelects = WorkspaceEnvironment.noStorePathSelects({directory: invocation.directory, databasePath: invocation.databasePath});
		final checked = invocation.directory != ""
			&& !pathSelects
			&& beadsDir != location.path ? relocated(location, beadsDir, location.databaseName, null) : location;
		return checkSelectedMetadata(invocation, location, checked, stops, false);
	}

	/**
		checkWorkspaceMetadata's checks of the metadata.json, or legacy
		config.json, that upstream's first setup and the guard after it read
		for the workspace at `location` that discovery found for the command.
		`checked` is the workspace that the command binds: `location`, or the
		second target of a redirect chain (see discoverStoreWorkspace), whose
		found directory the first setup takes, except with -C.
	**/
	function checkSelectedMetadata(invocation:Invocation, location:WorkspaceLocation, checked:WorkspaceLocation, stops:Bool, opensStore:Bool):Null<Int> {
		// Upstream's first setup and the guard after it take the found workspace, or with -C that target (see loadStoreConfig).
		final found = checked.foundPath;
		final selected = found != null && invocation.directory == "" ? found : checked.path;
		final path = commandPath(invocation.command);
		var error = "";
		var refusal = "";
		var upgradeRefusal:Null<String> = null;
		final sharedServer = () -> LayeredConfig.forWorkspace(selected).sharedServerMode();
		switch readMetadataFields(selected) {
			case MetadataFieldsUndecodable(text):
				error = text;
				if (databasePathSelects(invocation, location, opensStore))
					refusal = '${path} is not available yet when a database path selects a workspace whose .beads/metadata.json does not decode in this build';
			case MetadataFieldsUnsupported:
				refusal = '${path} is not available yet when .beads/metadata.json does not decode in this build';
			case MetadataFieldsLegacyOnly if (stops):
				final legacyFields = readLegacyConfigFields(selected);
				if (legacyFields != null)
					upgradeRefusal = LegacyUpgradeGuard.refusal(selected, legacyFields, sharedServer);
				// A database path makes upstream rewrite the file before its setups; otherwise `where` rewrites it in its body (see runWhere).
				if (upgradeRefusal == null && (opensStore || databasePathSelects(invocation, location, false)))
					refusal = legacyOnlyRefusal(path);
			case MetadataFieldsLegacyOnly:
			case MetadataFields(fields):
				upgradeRefusal = stops ? LegacyUpgradeGuard.refusal(selected, fields, sharedServer) : null;
			case MetadataAbsent:
				upgradeRefusal = stops ? LegacyUpgradeGuard.refusal(selected, null, sharedServer) : null;
		}
		// After that guard, FindDatabasePath follows the found workspace's redirect and rewrites the target's legacy config.json.
		if (error == "" && refusal == "" && upgradeRefusal == null && checked.path != selected && legacyOnly(checked.path))
			refusal = legacyOnlyRefusal(path);
		if (error == "" && refusal == "" && upgradeRefusal == null) {
			if (!opensStore)
				prepareNoStoreWorkspace(invocation, noStoreInitializations(invocation));
			return null;
		}
		// One setup runs before the load error or the legacy-workspace guard stops the command, so `where` does not set up again.
		if (opensStore)
			loadStoreConfig(invocation, checked, 1, false);
		else
			prepareNoStoreWorkspace(invocation, 1);
		if (upgradeRefusal != null) {
			output.writeStderr('Error: ${upgradeRefusal}\n');
			return 1;
		}
		if (refusal != "") {
			// `version` and help pages run without the warning they cannot match.
			if (!stops)
				return null;
			return runModeAwareFailure(invocation.output, refusal);
		}
		output.writeStderr(metadataLoadWarning(selected, error));
		if (!stops)
			return null;
		output.writeStderr(metadataLoadFailure(error));
		return 1;
	}

	/** This build's refusal of `path` in a legacy-only workspace, whose config.json upstream rewrites as metadata.json. */
	static function legacyOnlyRefusal(path:String):String {
		return '${path} is not available yet when the workspace has only a legacy config.json in this build';
	}

	/** Whether `beadsDir` is a legacy-only workspace: no metadata.json, and a config.json that decodes. */
	static function legacyOnly(beadsDir:Null<String>):Bool {
		return beadsDir != null && readMetadataFields(beadsDir).match(MetadataFieldsLegacyOnly);
	}

	/**
		The workspace whose metadata upstream's pre-run checks for `where`,
		`version` and help pages: the directory that it sets up first. For a
		`db` setting that is the directory that the setting's path selects
		(see noStoreBeadsDir), which upstream's FindBeadsDir then finds
		through BEADS_DIR, or else the workspace found from the current
		directory.
	**/
	function noStoreMetadataWorkspace(invocation:Invocation):WorkspaceDiscovery {
		if (databaseSettingSelects(invocation))
			return WorkspaceEnvironment.discoverWithBeadsDir(workspace, noStoreBeadsDir(invocation));
		return workspace.discover(invocation.directory, invocation.databasePath);
	}

	/**
		Upstream warnSharedServerEmbeddedMismatch, which its selected-workspace
		setup runs for the `.beads` directory `beadsDir` that it selects: once
		per process, it prints a three-line notice on stderr when that
		directory's metadata.json loads and pins dolt_mode embedded, and
		shared-server mode is on in `config`, the config reloaded for the
		directory.
	**/
	function warnSharedServerMismatch(beadsDir:String, config:LayeredConfig):Void {
		if (sharedServerNoticeEmitted)
			return;
		final fields = switch readMetadataFields(beadsDir) {
			case MetadataFields(fields): fields;
			// LoadForDiscovery reads a legacy-only workspace's config.json as its config.
			case MetadataFieldsLegacyOnly: readLegacyConfigFields(beadsDir);
			case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported: null;
		};
		if (fields == null || !pinsEmbeddedMode(fields) || !config.sharedServerMode())
			return;
		sharedServerNoticeEmitted = true;
		output.writeStderr(SHARED_SERVER_EMBEDDED_NOTICE);
	}

	/**
		Upstream prepareSelectedCommandContext for the `.beads` directory
		`beadsDir`, which upstream runs once for each entry of `setups`, the
		directory as that setup names it. Each run reloads the layered config
		with BEADS_DIR set to that directory and prints upstream's reinitialize
		warning when a config file does not parse: the workspace's config.yaml
		or config.local.yaml, or the user config.yaml. Each run then prints the
		permissions warning for its name of the directory (see
		warnBeadsDirPermissions) and, until one run printed it, the
		shared-server notice for that directory's metadata.json. A run whose
		directory is not `beadsDir`, such as the other target of a redirect
		chain, reloads that directory's own config (cmd/bd/main.go:596-614);
		a name such as a relative path or a symbolic link for `beadsDir`
		itself takes `beadsDir`'s config, and such a later run prints the load
		warning of that directory's metadata.json when it does not load
		(loadServerModeFromBeadsDir, :612).
		Before the reload each run binds BEADS_DIR to that directory and
		follows its redirect (RedirectLookups.prepareSelectedContext).
		`afterFirstSetup` runs what upstream runs after the first setup.
		Returns `beadsDir`'s config, which keeps what loaded before the
		failure.
	**/
	function loadSelectedConfig(beadsDir:String, setups:Array<String>, ?afterFirstSetup:() -> Void):LayeredConfig {
		final config = LayeredConfig.forWorkspace(beadsDir);
		final selected = RedirectSource.canonicalizePath(beadsDir);
		for (index => setup in setups) {
			final own = RedirectSource.canonicalizePath(setup) == selected;
			final setupConfig = own ? config : LayeredConfig.forWorkspace(setup);
			lookups.prepareSelectedContext(setup);
			if (setupConfig.failure != null)
				output.writeStderr('Warning: failed to reinitialize config for selected beads dir: ${setupConfig.failure}\n');
			warnBeadsDirPermissions(setup);
			// The first setup's load warning comes from checkWorkspaceMetadata, which stops the command there.
			if (index > 0 && !own)
				switch readMetadataFields(setup) {
					case MetadataFieldsUndecodable(error):
						output.writeStderr(metadataLoadWarning(setup, error));
					case MetadataFields(_) | MetadataAbsent | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly:
				}
			if (!sharedServerNoticeEmitted)
				warnSharedServerMismatch(own ? beadsDir : setup, setupConfig);
			if (index == 0 && afterFirstSetup != null)
				afterFirstSetup();
		}
		return config;
	}

	/**
		Upstream config.CheckBeadsDirPermissions, which each selected-directory
		setup runs for `beadsDir` as upstream names it: a warning on stderr when
		group or others have a permission bit on the directory. It only reads.
	**/
	function warnBeadsDirPermissions(beadsDir:String):Void {
		final warning = ConfigProbes.beadsDirPermissions(beadsDir);
		if (warning != null)
			output.writeStderr(warning);
	}

	/**
		loadSelectedConfig for the workspace at `location` that a command which
		opens a store takes, set up `initializations` times (see
		storeInitializations). The first setup names the directory as upstream
		selects it (see WorkspaceEnvironment.storeSetupDirectory): for the
		target of a found directory's redirect, the found directory, unless -C
		selected it (see discoverStoreWorkspace). The second comes after
		upstream binds the database (see boundSetupDirectory).

		Without a --db path upstream first looks up the redirecting workspace
		(GetRedirectInfo and preserveRedirectSourceDatabase, cmd/bd/main.go:1210)
		and the workspace itself (FindBeadsDir, :1214), and after the first
		setup it looks for the database (FindDatabasePath, :1250) when it
		`bindsDatabase`; a metadata.json that does not load stops it before.
	**/
	function loadStoreConfig(invocation:Invocation, location:WorkspaceLocation, initializations:Int, bindsDatabase:Bool):LayeredConfig {
		final found = location.foundPath;
		final first = found != null && invocation.directory == "" ? found : location.path;
		final setups = [WorkspaceEnvironment.storeSetupDirectory(invocation.databaseVariable, first)];
		if (initializations > 1)
			setups.push(boundSetupDirectory(location));
		if (databaseFlagSelectsPath(invocation))
			return loadSelectedConfig(location.path, setups);
		lookups.preserveSourceDatabase(lookups.getRedirectInfo());
		lookups.findBeadsDir();
		return loadSelectedConfig(location.path, setups, bindsDatabase ? lookups.findDatabasePath : null);
	}

	/**
		The name of the workspace in upstream's second setup for a command that
		opens a store: resolveCommandBeadsDir of the database path that it
		binds. That path is the one that FindDatabasePath finds
		(`location.databasePath`), or the `.beads` directory itself: for a
		proxied-server workspace, for a workspace without metadata.json whose
		host implies server mode, and when FindDatabasePath finds no path, as
		for a backend that upstream does not support. So a `.beads` directory
		that is a symbolic link has its target's name here. For the target of
		a found directory's redirect (see discoverStoreWorkspace), the path
		is that target: FindDatabasePath followed one redirect to it.
	**/
	static function boundSetupDirectory(location:WorkspaceLocation):String {
		if (location.foundPath != null)
			return location.path;
		final bindsDirectory = location.proxiedServer || location.databasePath == "" || switch readMetadataFields(location.path) {
			case MetadataAbsent: LayeredConfig.forWorkspace(location.path).hostImpliesServerMode();
			case MetadataFields(_) | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: false;
		};
		return WorkspaceEnvironment.commandBeadsDir(bindsDirectory ? location.path : location.databasePath, location.path);
	}

	/**
		loadSelectedConfig for the directory that `where`, `version` and help
		pages set up (see noStoreBeadsDir), when upstream selects one. When
		`where` sets it up again, upstream's pre-run has set BEADS_DIR to it.
		Then a --db, BEADS_DB or BD_DB path still names the same directory.
		Otherwise upstream's FindBeadsDir finds the directory through BEADS_DIR
		(see findThroughBeadsDir): by its absolute path for a `db` setting, by
		its target for a `.beads` symbolic link, and the target of its redirect
		when it has one that FollowRedirect follows. `where` reports the
		workspace that it finds from there (see whereBeadsDir). With -C,
		BEADS_DIR names the -C workspace before the pre-run looks up, so its
		first setup takes that directory too.
	**/
	function prepareNoStoreWorkspace(invocation:Invocation, initializations:Int):Void {
		// Upstream selectedNoDBBeadsDir looks the directory up first (cmd/bd/main.go:1156), and `where` again before its second setup (where.go:50).
		noStoreLookups(invocation);
		final pathSelects = WorkspaceEnvironment.noStorePathSelects({directory: invocation.directory, databasePath: invocation.databasePath});
		final beadsDir = noStoreSetupDirectory(invocation);
		if (beadsDir == "") {
			// Without a directory BEADS_DIR stays unset: loadEnvironment and loadServerModeFromConfig look again (:1160-1161, :419, :493), and so does the pre-run (:1170).
			if (!lookups.beadsDirSet()) {
				lookups.findBeadsDir();
				lookups.findBeadsDir();
			}
			lookups.findBeadsDir();
			if (initializations > 1)
				noStoreLookups(invocation);
			return;
		}
		final setups = [beadsDir];
		if (initializations > 1) {
			final again = pathSelects ? beadsDir : findThroughBeadsDir(invocation, beadsDir);
			if (again != "") {
				setups.push(again);
				if (!pathSelects)
					whereBeadsDir = again;
			}
		}
		final second = setups.length > 1 ? setups[1] : null;
		loadSelectedConfig(beadsDir, setups, initializations > 1 ? () -> {
			noStoreLookups(invocation);
			// The body's setup loads that directory's .env file first (where.go:51, cmd/bd/main.go:598).
			if (second != null)
				WorkspaceEnvironment.loadFile(second);
		} : null);
	}

	/**
		Upstream FindBeadsDir while BEADS_DIR names `beadsDir`, the directory
		that a setup of `where`, `version` or help pages bound (see
		prepareNoStoreWorkspace), or "" when it finds none.

		Why: upstream's later lookups through BEADS_DIR canonicalize that
		directory and follow its redirect (internal/beads/beads.go:759-770),
		which the first lookup may have ignored as a chain.
		What: for a directory that discovery found, the target of its redirect
		when FollowRedirect follows it, or else its canonical path; discovery
		only finds a directory with project files. For a `db` setting, whose
		path need not name a workspace, the native discovery's answer.
		How: only a `db` setting costs a native discovery.
	**/
	function findThroughBeadsDir(invocation:Invocation, beadsDir:String):String {
		if (databaseSettingSelects(invocation))
			return WorkspaceEnvironment.findWithBeadsDir(workspace, beadsDir);
		final canonical = RedirectSource.canonicalizePath(beadsDir);
		final target = RedirectSource.followedTarget(canonical);
		return target != null ? target : canonical;
	}

	/**
		The lookups of upstream selectedNoDBBeadsDir (cmd/bd/main.go:509-539):
		none when a --db, BEADS_DB or BD_DB path selects the directory, which
		resolveCommandBeadsDir derives from the path; else FindBeadsDir, through
		BEADS_DIR once a setup or -C set it (:529), and then, when that finds
		none, again unless a `db` setting selects the directory (:533, :538).
	**/
	function noStoreLookups(invocation:Invocation):Void {
		final selection:WorkspaceSelection = {directory: invocation.directory, databasePath: invocation.databasePath};
		if (WorkspaceEnvironment.noStorePathSelects(selection))
			return;
		if (lookups.beadsDirSet() && lookups.findBeadsDir() != "")
			return;
		if (!WorkspaceEnvironment.databaseSettingSelects(selection))
			lookups.findBeadsDir();
	}

	/**
		The `.beads` directory that upstream's pre-run sets up first for
		`where`, `version` and help pages, and that its legacy-workspace guard
		reads for `where`, or "" for none: noStoreBeadsDir, which with -C
		upstream's FindBeadsDir finds again through BEADS_DIR (see
		findThroughBeadsDir).
	**/
	function noStoreSetupDirectory(invocation:Invocation):String {
		final beadsDir = noStoreBeadsDir(invocation);
		final pathSelects = WorkspaceEnvironment.noStorePathSelects({directory: invocation.directory, databasePath: invocation.databasePath});
		return beadsDir != "" && !pathSelects && invocation.directory != "" ? findThroughBeadsDir(invocation, beadsDir) : beadsDir;
	}

	/** `where` sets up its directory in the pre-run and again in its command body; `version` and help pages only in the pre-run. */
	static function noStoreInitializations(invocation:Invocation):Int {
		return invocation.command == Where && !invocation.helpCommand ? 2 : 1;
	}

	/**
		How often upstream sets up the workspace that a command which opens a
		store takes: when it finds the `.beads` directory and again when it
		binds the database. It sets up only once when a --db or BEADS_DB path
		selects the database, and when it finds no database and stops. A --db
		value that names a database finds the `.beads` directory as without
		--db.
	**/
	static function storeInitializations(invocation:Invocation, location:WorkspaceLocation):Int {
		return findsDatabase(invocation, location) && !databasePathSelected(invocation, location) ? 2 : 1;
	}

	/**
		Upstream selectedNoDBBeadsDir (see WorkspaceEnvironment.noStoreBeadsDir):
		the `.beads` directory that `where`, `version` and help pages set up, or
		"" for none. Commands that open a store set up the same directory for a
		`db` setting.
	**/
	function noStoreBeadsDir(invocation:Invocation):String {
		return WorkspaceEnvironment.noStoreBeadsDir(workspace, {directory: invocation.directory, databasePath: invocation.databasePath});
	}

	/**
		Upstream's pre-run for a command that opens the store when no workspace
		is found and BEADS_DB names a path that this build does not follow.

		Why: before it opens or creates a database for the path (main.go
		FindDatabasePath at :1250), upstream sets up the directory that
		resolveCommandBeadsDir derives from it (:1316-1317), which prints its
		config warning and shared-server notice, and its legacy-workspace guard
		(:1319) stops a metadata.json there that does not load, or a legacy
		workspace layout, before anything is written. Its lookups and its
		guardUndiscoveredLegacyWorkspace come first (:1210-1243), as for any
		command that finds no workspace. What: those lookups and that guard
		(see storeLookupsWithoutWorkspace), that setup (see loadSelectedConfig)
		for WorkspaceEnvironment.variableBeadsDir, then the guard there: for
		such a metadata.json upstream's load warning and error, or the guard's
		refusal; else this build's refusal. How: it only reads.
	**/
	function refuseDatabaseVariablePath(invocation:Invocation, name:String):Int {
		final stop = storeLookupsWithoutWorkspace(invocation);
		if (stop != null)
			return stop;
		final beadsDir = WorkspaceEnvironment.variableBeadsDir(environmentValue(name));
		loadSelectedConfig(beadsDir, [beadsDir]);
		switch LegacyUpgradeGuard.check(beadsDir, () -> LayeredConfig.forWorkspace(beadsDir).sharedServerMode()) {
			case GuardLoadFailed(error):
				output.writeStderr(metadataLoadWarning(beadsDir, error));
				output.writeStderr(metadataLoadFailure(error));
				return 1;
			case GuardRefused(error):
				output.writeStderr('Error: ${error}\n');
				return 1;
			case GuardPasses | GuardUnknown:
		}
		return runModeAwareFailure(invocation.output, databaseVariableRefusal(invocation.command, name));
	}

	/** This build's refusal of a `command` for which the variable `name` names a path that it does not follow. */
	static function databaseVariableRefusal(command:Command, name:String):String {
		return '${commandPath(command)} is not available yet when ${name} names this path in this build';
	}

	static function metadataLoadRole(invocation:Invocation):MetadataLoadRole {
		if (invocation.helpCommand)
			return MetadataWarnsOnly;
		if (invocation.showHelp)
			return MetadataUnread;
		return switch invocation.command {
			case RootHelp | Version: MetadataWarnsOnly;
			case Where: MetadataStopsCommand(false);
			// The label, events and config groups print their help, which cobra shows without the pre-run.
			case command: usesStore(command) ? MetadataStopsCommand(true) : MetadataUnread;
		};
	}

	/**
		Whether upstream takes the workspace from a database path. Store commands
		take it from --db (a --db value that names a database instead finds the
		workspace) or from a BEADS_DB path that the parser took as `databasePath`;
		`where`, `version` and help also from BEADS_DB, BD_DB and the `db` setting.
	**/
	static function databasePathSelects(invocation:Invocation, location:WorkspaceLocation, opensStore:Bool):Bool {
		if (invocation.databasePath != "" && location.databaseName == "")
			return true;
		return !opensStore
			&& (environmentValue("BEADS_DB") != "" || environmentValue("BD_DB") != "" || databaseSettingSelects(invocation));
	}

	function writeJsonStdout(value:String):Void {
		final document = escapeJsonHtml(value);
		output.writeStdout(output.usesJsonEnvelope() ? wrapJsonDocument(document) : document);
		if (!jsonDeprecationEmitted && output.shouldEmitJsonDeprecation()) {
			jsonDeprecationEmitted = true;
			output.writeStderr(jsonDeprecation + "\n");
		}
	}

	/**
		Matches the default of Go's `encoding/json`, which upstream `bd` uses for
		every JSON output: `<`, `>` and `&` print as `<`, `>` and
		`&`. These characters can occur only inside JSON strings, so this
		replacement over the complete document escapes each string exactly once.
		Text that is already escaped, such as stored metadata, has none of them
		left. Human output does not come through here and stays unchanged.
	**/
	static function escapeJsonHtml(json:String):String {
		final ampersands = StringTools.replace(json, "&", "\\u0026");
		final lessThan = StringTools.replace(ampersands, "<", "\\u003c");
		return StringTools.replace(lessThan, ">", "\\u003e");
	}

	/** Complete every nested issue encoding before stdout or the deprecation note. */
	function writeRenderedJsonStdout(document:StoreResult<String>):Int {
		return switch document {
			case Failure(message): runStoreFailure('encoding JSON: $message');
			case Success(value):
				writeJsonStdout(value);
				0;
		};
	}

	/**
		Wraps one already-serialized top-level object at the JSON output boundary.
		Every caller supplies pretty JSON with a top-level schema_version field;
		the envelope owns that field instead, so data retains the legacy payload.
	**/
	static function wrapJsonDocument(value:String):String {
		final trailingNewline = StringTools.endsWith(value, "\n");
		var data = trailingNewline ? value.substr(0, value.length - 1) : value;
		data = StringTools.replace(data, '  "schema_version": 1,\n', "");
		final schemaSuffix = ',\n  "schema_version": 1\n}';
		if (StringTools.endsWith(data, schemaSuffix))
			data = data.substr(0, data.length - schemaSuffix.length) + "\n}";
		data = StringTools.replace(data, "\n", "\n  ");
		return '{\n  "data": ${data},\n  "schema_version": 1\n}\n';
	}

	function runRootHelp(invocation:Invocation):Int {
		if (StringTools.trim(invocation.directory) != "") {
			switch workspace.discover(invocation.directory, "") {
				case InvalidSelection(message):
					return runStoreFailure(message);
				case Found(_) | NotFound:
			}
		}
		output.writeStdout(rootHelp());
		return 0;
	}

	function runVersion(invocation:Invocation):Int {
		if (StringTools.trim(invocation.directory) != "") {
			switch workspace.discover(invocation.directory, "") {
				case InvalidSelection(message):
					return runStoreFailure(message);
				case Found(_) | NotFound:
			}
		}
		// Upstream's resolveBranch asks GetRepoContext for the branch (cmd/bd/version.go:41, :123).
		lookups.getRepoContext();
		switch invocation.output {
			case Human:
				output.writeStdout(identity + "\n");
			case Json:
				final document:VersionDocument = {
					schema_version: 1,
					version: "0.0.0-development",
					build: "development",
					compatibility: {
						project: "Beads",
						version: "v1.2.1",
						commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"
					},
					identity: identity
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
		}
		return 0;
	}

	function runWhere(invocation:Invocation):Int {
		// Upstream's where looks its directory up again (resolveWhereBeadsDir, where.go:54).
		noStoreLookups(invocation);
		return switch whereWorkspace(invocation) {
			case Found(location):
				// Then it looks for the database (FindDatabasePath, :79).
				lookups.findDatabasePath();
				// There configfile.Load rewrites a legacy config.json as metadata.json.
				if (legacyOnly(location.path))
					return runModeAwareFailure(invocation.output, legacyOnlyRefusal(commandPath(invocation.command)));
				final prefix = wherePrefix(location);
				final bound = whereBeadsDir;
				final redirectedFrom = RedirectSource.whereOrigin(bound != null ? bound : location.path, location.path);
				switch invocation.output {
					case Human: output.writeStdout(renderWhereHuman(location, prefix, redirectedFrom));
					case Json: writeJsonStdout(renderWhereJson(location, prefix, redirectedFrom));
				}
				0;
			case NotFound:
				// resolveWhereBeadsDir falls back to FindBeadsDir (where.go:123).
				lookups.findBeadsDir();
				final hint = workspaceDiagHint(false, LayeredConfig.atStartup().sharedServerMode());
				switch invocation.output {
					case Human:
						output.writeStderr('Error: ${noWorkspaceMessage}\nHint: ${hint}\n');
					case Json:
						final document:DiagnosticDocument = {
							schema_version: 1,
							error: "no_beads_directory",
							message: noWorkspaceMessage,
							hint: hint
						};
						writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				}
				1;
			case InvalidSelection(message):
				runStoreFailure(message);
		};
	}

	/**
		The workspace that upstream's `where` reports: the one that its last
		lookup finds through BEADS_DIR (see whereBeadsDir), or else, for a
		database path, the one that this build's discovery finds for it.

		That lookup canonicalizes BEADS_DIR's directory and follows its
		redirect. When that directory is the canonical path of the workspace
		that discovery found for the selection, it is the same workspace,
		which `where` names by that path, as for a `.beads` symbolic link,
		without another native discovery. Otherwise, as for a redirect chain
		or a `db` setting, discovery runs again with BEADS_DIR naming the
		directory. Its FindDatabasePath (where.go:79) follows that directory's
		redirect once, so when the workspace that the lookup finds there has
		a redirect of its own, as in a chain of four, the database is the one
		in that workspace, which the native discovery would follow again.
	**/
	function whereWorkspace(invocation:Invocation):WorkspaceDiscovery {
		final selected = workspace.discover(invocation.directory, invocation.databasePath);
		final bound = whereBeadsDir;
		if (bound == null)
			return derivedWhereWorkspace(invocation, selected);
		switch selected {
			case Found(location) if (location.path == bound):
				return selected;
			case Found(location) if (!databaseSettingSelects(invocation) && RedirectSource.canonicalizePath(location.path) == bound):
				return Found(relocated(location, bound, location.databaseName, location.foundPath));
			case Found(_) | NotFound | InvalidSelection(_):
		}
		final found = WorkspaceEnvironment.discoverWithBeadsDir(workspace, bound);
		return switch found {
			case Found(location) if (WorkspaceEnvironment.redirectedThrough(location.path) != null):
				Found(relocated(location, location.path, location.databaseName, location.foundPath, WorkspaceEnvironment.directoryDatabase(location.path)));
			case Found(_) | NotFound | InvalidSelection(_):
				found;
		};
	}

	/**
		The workspace that upstream's `where` reports for a database path:
		the directory that resolveCommandBeadsDir derives from the path (see
		noStoreBeadsDir), which names the workspace that discovery found
		(`selected`) in its own words. For a path given in another letter case
		that is the canonical path, with each name's stored case on macOS, when
		the path's canonical parent claims it.
	**/
	function derivedWhereWorkspace(invocation:Invocation, selected:WorkspaceDiscovery):WorkspaceDiscovery {
		final location = switch selected {
			case Found(location): location;
			case NotFound | InvalidSelection(_): return selected;
		};
		final derived = noStoreBeadsDir(invocation);
		if (derived == "" || derived == location.path || !RedirectSource.samePath(derived, location.path))
			return selected;
		return Found(relocated(location, derived, location.databaseName, location.foundPath));
	}

	/**
		`location` with another path, database name and found directory (see
		WorkspaceLocation.foundPath), and with another database path when
		`databasePath` is given.
	**/
	static function relocated(location:WorkspaceLocation, path:String, databaseName:String, foundPath:Null<String>, ?databasePath:String):WorkspaceLocation {
		return {
			path: path,
			yamlPrefix: location.yamlPrefix,
			databasePath: databasePath != null ? databasePath : location.databasePath,
			databaseName: databaseName,
			databaseMissing: location.databaseMissing,
			proxiedServer: location.proxiedServer,
			listLimitConfigured: location.listLimitConfigured,
			listLimit: location.listLimit,
			foundPath: foundPath
		};
	}

	function runInfo(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) {
							runWorkspaceDatabaseNotFound(location);
						} else if (invocation.infoThanks || invocation.infoWhatsNew) {
							// Upstream's pre-run opens the store first; the checks above and the schema check stand for an embedded open.
							final opensStore = invocation.global || opensServerStore(location);
							if (!opensStore && !location.proxiedServer)
								store.checkSchema(location.path, selectedDatabaseName(invocation, location));
							final opened = opensStore ? store.validate(location.path, invocation.global) : Success(true);
							finishStoreOpen(opened.match(Success(_)));
							switch opened {
								case Failure(message): runStoreFailure(message);
								case Success(_) if (invocation.infoThanks):
									// Upstream checks --thanks first and prints the page in every output mode.
									output.writeStdout(ThanksPage.render(output.textStyle, startupColors, colors, darkBackground));
									0;
								case Success(_):
									renderWhatsNew(invocation.output);
									0;
							}
						} else {
							final read = store.info(location.path, invocation.infoSchema, invocation.global);
							finishStoreOpen(read.match(Success(_)));
							switch read {
								case Failure(message): runStoreFailure(message);
								case Success(snapshot):
									// Upstream prints the database path it took: for BEADS_DB, the one FindDatabasePath takes.
									final databasePath = switch invocation.databaseVariable {
										case VariablePath(_, _, variablePath) if (variablePath != null): variablePath;
										case NoVariable | VariablePath(_, _, _) | UnsupportedPath(_): snapshot.databasePath;
									};
									switch invocation.output {
										case Human: output.writeStdout(renderInfoHuman(snapshot, databasePath, invocation.infoSchema));
										case Json: writeJsonStdout(renderInfoJson(snapshot, databasePath, invocation.infoSchema));
									}
									0;
							}
						}
				}
		};
	}

	function renderWhatsNew(mode:OutputMode):Void {
		switch mode {
			case Json:
				final document:WhatsNewDocument = {
					schema_version: 1,
					current_version: InfoChanges.currentVersion,
					recent_changes: InfoChanges.recent
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
			case Human:
				var rendered = '\n🆕 What\'s New in bd (Current: v${InfoChanges.currentVersion})\n';
				rendered += "=============================================================\n\n";
				for (entry in InfoChanges.recent) {
					final marker = entry.version == InfoChanges.currentVersion ? " ← current" : "";
					rendered += '## v${entry.version} (${entry.date})${marker}\n\n';
					for (change in entry.changes)
						rendered += '  • ${change}\n';
					rendered += "\n";
				}
				rendered += "💡 Tip: Use `bd info --whats-new --json` for machine-readable output\n\n";
				output.writeStdout(rendered);
		}
	}

	function runPing(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch pingStore(location, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(snapshot):
								renderPing(invocation.output, snapshot);
								0;
						}
				}
		};
	}

	/** Upstream ping's body finds the workspace (cmd/bd/ping.go:48) before it pings the store; under a proxied server it pings the server instead. */
	function pingStore(location:WorkspaceLocation, global:Bool):StoreResult<PingSnapshot> {
		if (!location.proxiedServer)
			lookups.findBeadsDir();
		final pinged = store.ping(location.path, global);
		finishStoreOpen(pinged.match(Success(_)));
		return pinged;
	}

	function runStatus(invocation:Invocation):Int {
		final assignee = invocation.statusAssigned ? actor.resolve(invocation.actor) : "";
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation,
							location)) runWorkspaceDatabaseNotFound(location); else switch readStatus(location, invocation.statusSkipBlocked, assignee,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(snapshot):
								renderStatus(invocation.output, snapshot);
								0;
						}
				}
		};
	}

	function readStatus(location:WorkspaceLocation, skipBlocked:Bool, assignee:String, global:Bool):StoreResult<StatusSnapshot> {
		final read = store.status(location.path, skipBlocked, assignee, global);
		finishStoreOpen(read.match(Success(_)));
		return read;
	}

	function runShow(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query): closeIssueQuery(query, runShowQuery(invocation, location, query));
						}
				}
		};
	}

	function runShowQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.watchMode)
			return runShowWatch(invocation, location, query);
		if (invocation.showThread)
			return runShowThread(invocation, location, query);
		if (invocation.showRefs)
			return runShowRefs(invocation, location, query);
		if (invocation.showChildren)
			return runShowChildren(invocation, location, query);
		if (invocation.showShort)
			return runShowShort(invocation, location, query);
		return switch invocation.output {
			case Human: runShowHuman(invocation, location, query);
			case Json: runShowJson(invocation, location, query);
		};
	}

	function runList(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) {
							runWorkspaceDatabaseNotFound(location);
						} else {
							final effectiveLimit = resolveListLimit(invocation, location);
							switch openIssueQuery(invocation, location) {
								case Failure(message): runStoreFailure(message);
								case Success(query):
									// Upstream checks --offset in the command body, after its pre-run opened the store.
									final positiveOffset = switch invocation.listRequest.offset {
										case IntPresent(value): value > 0;
										case IntAbsent: false;
									};
									final deferredExit = runDeferredChecks(invocation);
									final result = if (deferredExit != null) {
										deferredExit;
									} else if (positiveOffset && !location.proxiedServer) {
										runStoreFailure("--offset is only supported under --proxied-server");
									} else {
										// Upstream's openRoutedReadStore asks for the user's role before it reads; a proxied server does not route.
										final routedExit = location.proxiedServer ? null : routeListRead(invocation, location, query);
										if (routedExit != null)
											routedExit;
										else if (invocation.watchMode)
											runListWatch(invocation, location, effectiveLimit, query);
										else
											renderListResult(invocation, loadListResult(invocation, location, effectiveLimit, query), effectiveLimit);
									}
									closeIssueQuery(query, result);
							}
						}
				}
		};
	}

	function runDepList(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runDepListQuery(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runDepListQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final batch = invocation.showIds.length > 1;
		final resolved = new Array<String>();
		for (id in invocation.showIds)
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					if (!batch)
						return runModeAwareFailure(invocation.output, 'resolving ${id}: ${message}');
					output.writeStderr('warning: resolving ${id}: ${message} (skipped)\n');
				case ReadHere(Success(IssueMissing)):
					final message = 'no issue found matching "${id}"';
					if (!batch)
						return runModeAwareFailure(invocation.output, 'resolving ${id}: ${message}');
					output.writeStderr('warning: resolving ${id}: ${message} (skipped)\n');
				case ReadHere(Success(IssueFound(summary))):
					resolved.push(summary.id);
			}
		if (resolved.length == 0) {
			if (invocation.output == Json)
				writeJsonStdout("[]\n");
			else
				output.writeStderr("no resolvable issues in batch\n");
			return 0;
		}
		if (invocation.depType != "" && haxe.io.Bytes.ofString(invocation.depType).length > 32) {
			final role = invocation.depListSelection == BatchEdges ? "read edges" : "related";
			return runModeAwareFailure(invocation.output, 'validation failed: ${role} type 0 is not a usable dependency type (non-empty, max 32 chars)');
		}
		final dependencyTypes = invocation.depType == "" ? [] : [invocation.depType];
		return switch invocation.depListSelection {
			case RelatedIssues(direction):
				final neighbors = new Array<RelatedIssue>();
				for (id in resolved) {
					final plan = switch prepareRelationRead(id, direction == Incoming ? "in" : "out", dependencyTypes) {
						case RelationPlanInvalid(message): return runModeAwareFailure(invocation.output, message);
						case RelationPlanReady(value): value;
					};
					switch query.relatedIssues(location.path, location.databaseName, plan, invocation.global) {
						case Failure(message): return runModeAwareFailure(invocation.output, message);
						case Success(rows):
							for (row in rows)
								neighbors.push(row);
					}
				}
				renderRelatedDepList(invocation, resolved, neighbors, direction);
			case BatchEdges:
				switch query.dependencyEdges(location.path, location.databaseName, resolved, dependencyTypes, invocation.global) {
					case DependencyEdgeFailure(message): runModeAwareFailure(invocation.output, message);
					case DependencyEdges(anchors): renderDepList(invocation, anchors);
				}
		};
	}

	function runDepCycles(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.dependencyCycles(location.path, location.databaseName, invocation.global) {
									case Failure(message): runModeAwareFailure(invocation.output, message);
									case Success(cycles): renderDepCycles(invocation, cycles);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/** Matches upstream `bd dep cycles` output with colors off. */
	function renderDepCycles(invocation:Invocation, cycles:Array<DependencyCycle<RelatedIssue>>):Int {
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderDepCyclesJson(cycles));
		// Upstream's dep cycles view (cmd/bd/dep_cycles.go:56-85).
		final styles = terminalStyles();
		if (cycles.length == 0) {
			output.writeStdout('\n${styles.renderPass("✓")} No dependency cycles detected\n\n');
			return 0;
		}
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderFail("⚠")} Found ${cycles.length} dependency cycles:\n\n');
		for (index in 0...cycles.length) {
			final cycle = cycles[index];
			var missing = 0;
			for (member in cycle.members)
				if (member.issue == null)
					missing++;
			if (missing > 0)
				rendered.add('${index + 1}. Cycle involving (${missing} of ${cycle.members.length} members have no record in this database):\n');
			else
				rendered.add('${index + 1}. Cycle involving:\n');
			for (member in cycle.members) {
				final issue = member.issue;
				rendered.add('   - ${member.id}: ${issue == null ? styles.renderMuted("(no record in this database)") : issue.title}\n');
			}
			rendered.add("\n");
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	/** Upstream prints the bare cycle list; a member without a record has no "issue" key. */
	static function renderDepCyclesJson(cycles:Array<DependencyCycle<RelatedIssue>>):StoreResult<String> {
		if (cycles.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (cycleIndex in 0...cycles.length) {
			final cycle = cycles[cycleIndex];
			lines.push("  {");
			lines.push('    "members": [');
			for (memberIndex in 0...cycle.members.length) {
				final member = cycle.members[memberIndex];
				final issue = member.issue;
				lines.push("      {");
				if (issue == null) {
					lines.push('        "id": ${Json.stringify(member.id)}');
				} else {
					lines.push('        "id": ${Json.stringify(member.id)},');
					final fields = switch renderIssueFields(issue, false, "          ", issue.labels) {
						case Failure(message): return Failure(message);
						case Success(value): value;
					};
					lines.push('        "issue": {');
					for (fieldIndex in 0...fields.length)
						lines.push('          ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
					lines.push("        }");
				}
				lines.push(memberIndex == cycle.members.length - 1 ? "      }" : "      },");
			}
			lines.push("    ],");
			lines.push('    "partial": ${cycle.partial}');
			lines.push(cycleIndex == cycles.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	function runDepTree(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runDepTreeQuery(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/** Checks the flags, resolves the root and walks, in the order upstream runDepTree does. */
	function runDepTreeQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final request = invocation.depTree;
		final direction = parseTreeDirection(request.direction);
		if (direction == null)
			return runModeAwareFailure(invocation.output, "--direction must be 'down', 'up', or 'both'");
		if (request.maxDepth < 1)
			return runModeAwareFailure(invocation.output, "--max-depth must be >= 1");
		final maxRows = switch request.maxRows {
			case IntPresent(value): value;
			case IntAbsent: 0;
		};
		if (maxRows < 0)
			return runModeAwareFailure(invocation.output, '--max-rows must be non-negative; got ${maxRows}');
		if (request.maxRowsWarning != "")
			output.writeStderr(request.maxRowsWarning);
		final rootId = switch lookupIssueWithRouting(location, request.root, invocation.global, query) {
			case ReadElsewhere:
				return runRoutedLookupRefusal(invocation);
			case ReadHere(Failure(message)):
				return runModeAwareFailure(invocation.output, 'resolving issue ID ${request.root}: ${message}');
			case ReadHere(Success(IssueMissing)):
				return runModeAwareFailure(invocation.output, 'resolving issue ID ${request.root}: no issue found matching "${request.root}"');
			case ReadHere(Success(IssueFound(summary))): summary.id;
		};
		final nodes = switch query.dependencyTree(location.path, location.databaseName, {
			rootId: rootId,
			direction: direction,
			maxDepth: request.maxDepth,
			status: request.status
		}, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, message);
			case Success(value): value;
		};
		// Upstream checks the cap after the walk, on the nodes it would print.
		if (maxRows > 0 && nodes.length > maxRows)
			return runListRowLimitExceeded(nodes.length, request.maxRowsSource, maxRows);
		if (request.format == "mermaid") {
			// The argument as typed, not the resolved ID: it is used only for an empty tree.
			output.writeStdout(renderDepTreeMermaid(nodes, request.root));
			return 0;
		}
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderDepTreeJson(nodes));
		output.writeStdout(renderDepTreeHuman(nodes, rootId, direction, request.maxDepth, terminalStyles()));
		return 0;
	}

	/** Matches upstream runDepTree and renderTree with colors off; the root badge stays bold. */
	/**
		Upstream's dep tree view (cmd/bd/dep_tree.go:160-180) and treeRenderer
		(cmd/bd/dep.go:1205-1300): an accented heading, a muted ID for a node
		shown above, and a warning mark at the depth limit.
	**/
	static function renderDepTreeHuman(nodes:Array<TreeNode<RelatedIssue>>, rootId:String, direction:TreeDirection, maxDepth:Int,
			styles:TerminalStyles):String {
		if (nodes.length == 0)
			return switch direction {
				case TreeUp: '\n${rootId} has no dependents\n';
				case TreeBoth: '\n${rootId} has no dependencies or dependents\n';
				case TreeDown: '\n${rootId} has no dependencies\n';
			};
		final rendered = new StringBuf();
		final tree = styles.renderAccent("🌲");
		rendered.add(switch direction {
			case TreeUp: '\n${tree} Dependent tree for ${rootId}:\n\n';
			case TreeBoth: '\n${tree} Full dependency graph for ${rootId}:\n\n';
			case TreeDown: '\n${tree} Dependency tree for ${rootId}:\n\n';
		});
		final children = new Map<String, Array<TreeNode<RelatedIssue>>>();
		var root:Null<TreeNode<RelatedIssue>> = null;
		for (node in nodes) {
			if (node.depth == 0) {
				root = node;
				continue;
			}
			var siblings = children.get(node.parentId);
			if (siblings == null) {
				siblings = [];
				children.set(node.parentId, siblings);
			}
			siblings.push(node);
		}
		final top = root == null ? nodes[0] : root;
		// Only genuine blockers that are still open mark an open root as blocked (GH#3565).
		var rootBlocked = false;
		final rootChildren = children.get(top.id);
		if (rootChildren != null)
			for (child in rootChildren)
				if ((child.status == "open" || child.status == "in_progress") && isBlockingTreeEdge(child.edgeFromParent)) {
					rootBlocked = true;
					break;
				}
		final seen = new Map<String, Bool>();
		final activeConnectors = new Map<Int, Bool>();
		function renderNode(node:TreeNode<RelatedIssue>, depth:Int, isLast:Bool):Void {
			final prefix = new StringBuf();
			for (level in 0...depth)
				prefix.add(activeConnectors.get(level) == true ? "│   " : "    ");
			if (depth > 0)
				prefix.add(isLast ? "└── " : "├── ");
			// A node reached again, such as one on both sides of a `both` walk.
			if (seen.exists(node.id)) {
				rendered.add('${prefix.toString()}${styles.renderMuted(node.id)} (shown above)\n');
				return;
			}
			seen.set(node.id, true);
			final nodeChildren = children.get(node.id);
			var line = formatDepTreeNode(node, depth == 0 && rootBlocked, styles);
			if (depth == maxDepth && nodeChildren != null && nodeChildren.length > 0)
				line += styles.renderWarn(" …");
			rendered.add('${prefix.toString()}${line}\n');
			if (nodeChildren == null)
				return;
			for (index in 0...nodeChildren.length) {
				// The root has no siblings, so depth 0 never draws a vertical connector.
				if (depth > 0)
					activeConnectors.set(depth, index < nodeChildren.length - 1);
				renderNode(nodeChildren[index], depth + 1, index == nodeChildren.length - 1);
			}
		}
		renderNode(top, 0, true);
		rendered.add("\n");
		return rendered.toString();
	}

	/**
		Upstream formatTreeNode (cmd/bd/dep.go:1305-1355). `isBlocked` replaces
		the root's [READY] badge. Both badges are bold also with colors off,
		since upstream adds Bold to its empty pass and fail styles.
	**/
	static function formatDepTreeNode(node:TreeNode<RelatedIssue>, isBlocked:Bool, styles:TerminalStyles):String {
		if (StringTools.startsWith(node.id, "external:")) {
			final title = switch node.status {
				case "closed": styles.statusClosed.render(node.issue.title);
				case "blocked": styles.statusBlocked.render(node.issue.title);
				case _: node.issue.title;
			};
			return '${title} (external)';
		}
		var line = '${styles.renderStatusId(node.status, node.id)}: ${node.issue.title} [P${node.issue.priority}] (${node.status})';
		if (node.depth > 0 && node.edgeFromParent != "")
			line += " " + styles.renderMuted('[${node.edgeFromParent}]');
		if (node.status == "open" && node.depth == 0)
			line += " " + (isBlocked ? styles.failBold.render("[BLOCKED]") : styles.passBold.render("[READY]"));
		return line;
	}

	/** Upstream DependencyType.IsBlockingEdge: parent-child and other links do not block. */
	static function isBlockingTreeEdge(edge:String):Bool {
		return edge == "blocks" || edge == "conditional-blocks" || edge == "waits-for";
	}

	/** Upstream outputMermaidTree: each node once, then one edge per node with a parent. */
	static function renderDepTreeMermaid(nodes:Array<TreeNode<RelatedIssue>>, rootArgument:String):String {
		if (nodes.length == 0)
			return 'flowchart TD\n  ${rootArgument}["No dependencies"]\n';
		final rendered = new StringBuf();
		rendered.add("flowchart TD\n");
		final seen = new Map<String, Bool>();
		for (node in nodes) {
			if (seen.exists(node.id))
				continue;
			seen.set(node.id, true);
			var label = '${mermaidStatusSymbol(node.status)} ${node.id}: ${node.issue.title}';
			label = StringTools.replace(label, "\\", "\\\\");
			label = StringTools.replace(label, "\"", "\\\"");
			rendered.add('  ${node.id}["${label}"]\n');
		}
		rendered.add("\n");
		for (node in nodes)
			if (node.parentId != "" && node.parentId != node.id)
				rendered.add('  ${node.parentId} --> ${node.id}\n');
		return rendered.toString();
	}

	/** Upstream getStatusEmoji. */
	static function mermaidStatusSymbol(status:String):String {
		return switch status {
			case "open": "☐";
			case "in_progress": "◧";
			case "blocked": "⚠";
			case "deferred": "❄";
			case "closed": "☑";
			case _: "?";
		};
	}

	/** Upstream prints the bare node list: each issue, then depth, parent_id, edge_from_parent and truncated. */
	static function renderDepTreeJson(nodes:Array<TreeNode<RelatedIssue>>):StoreResult<String> {
		if (nodes.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (index in 0...nodes.length) {
			final node = nodes[index];
			final fields = switch renderIssueFields(node.issue, false, "    ", node.issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"depth": ${node.depth}');
			fields.push('"parent_id": ${Json.stringify(node.parentId)}');
			if (node.edgeFromParent != "")
				fields.push('"edge_from_parent": ${Json.stringify(node.edgeFromParent)}');
			// Upstream never sets Truncated; it is kept for the JSON shape.
			fields.push('"truncated": false');
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == nodes.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	function runGraphCheck(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.graphCycles(location.path, location.databaseName, invocation.global) {
									case Failure(message): runModeAwareFailure(invocation.output, 'cycle detection failed: ${message}');
									case Success(cycles): renderGraphCheck(invocation, cycles);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Upstream renderGraphCheck (cmd/bd/graph.go:325-350), with its pass and fail marks. A
		graph with cycles exits 1 with nothing on stderr, as upstream SilentExit does, in both
		output modes.
	**/
	function renderGraphCheck(invocation:Invocation, cycles:Array<Array<String>>):Int {
		final exitCode = cycles.length == 0 ? 0 : 1;
		if (invocation.output == Json) {
			writeJsonStdout(renderGraphCheckJson(cycles));
			return exitCode;
		}
		final styles = terminalStyles();
		final rendered = new StringBuf();
		if (cycles.length == 0) {
			rendered.add('\n${styles.renderPass("✓")} Graph integrity check passed\n\n');
			rendered.add('  ${styles.renderPass("✓")} No dependency cycles\n');
		} else {
			rendered.add('\n${styles.renderFail("✗")} Graph integrity issues found\n\n');
			rendered.add('${styles.renderFail("⚠")} Cycles (${cycles.length}):\n\n');
			for (cycle in cycles)
				rendered.add('  ${cycle.join(" → ")} → ${cycle[0]}\n');
			rendered.add("\n");
		}
		rendered.add("\n");
		output.writeStdout(rendered.toString());
		return exitCode;
	}

	/** Upstream's GraphCheckResult after the schema_version map round trip: keys sorted, `cycles` null when clean. */
	static function renderGraphCheckJson(cycles:Array<Array<String>>):String {
		final lines = ["{", '  "clean": ${cycles.length == 0},'];
		if (cycles.length == 0) {
			lines.push('  "cycles": null,');
		} else {
			lines.push('  "cycles": [');
			for (index in 0...cycles.length) {
				final cycle = cycles[index];
				lines.push("    [");
				for (memberIndex in 0...cycle.length)
					lines.push('      ${Json.stringify(cycle[memberIndex])}${memberIndex == cycle.length - 1 ? "" : ","}');
				lines.push(index == cycles.length - 1 ? "    ]" : "    ],");
			}
			lines.push("  ],");
		}
		lines.push('  "schema_version": 1,');
		lines.push('  "summary": {');
		lines.push('    "cycle_count": ${cycles.length}');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	function runGraph(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runGraphQuery(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Checks the arguments, resolves the root, loads its subgraph and checks the row cap,
		in the order upstream graphCmd does. Then `--open` filters the subgraph. `--all`
		goes to runGraphAll.
	**/
	function runGraphQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final request = invocation.graph;
		if (request.all && request.ids.length > 0)
			return runModeAwareFailure(invocation.output, "cannot specify issue ID with --all flag");
		if (request.all)
			return runGraphAll(invocation, location, query);
		if (request.ids.length == 0) {
			if (invocation.output == Json) {
				writeJsonStdout('{\n  "error": "issue ID required",\n  "hint": "Use --all for all open issues",\n  "schema_version": 1\n}\n');
			} else {
				output.writeStderr("Error: issue ID required\nHint: Use --all for all open issues\n");
			}
			return 1;
		}
		// Upstream reports every resolution failure, an ambiguous ID included, as not found.
		final rootId = switch lookupIssueSummary(location, request.ids[0], invocation.global, query) {
			case Success(IssueFound(summary)): summary.id;
			case Success(IssueMissing) | Failure(_):
				return runModeAwareFailure(invocation.output, 'issue \'${request.ids[0]}\' not found');
		};
		final load = switch query.graphSubgraph(location.path, location.databaseName, rootId, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, 'loading graph: ${message}');
			case Success(value): value;
		};
		final subgraph:GraphSubgraph = switch keepGraphRows(invocation, location, query, load.issues, load.rows) {
			case Failure(message): return runModeAwareFailure(invocation.output, 'loading graph: ${message}');
			case Success(kept): {
					root: load.root,
					issues: kept.issues,
					edges: [
						for (row in kept.rows)
							{issueId: row.issueId, dependsOnId: row.dependsOnId, type: row.type}
					]
				};
		};
		// Upstream reads the cap only now, after the whole subgraph is loaded.
		final maxRows = switch request.maxRows {
			case IntPresent(value): value;
			case IntAbsent: 0;
		};
		if (maxRows < 0)
			return runModeAwareFailure(invocation.output, '--max-rows must be non-negative; got ${maxRows}');
		if (request.maxRowsWarning != "")
			output.writeStderr(request.maxRowsWarning);
		if (maxRows > 0 && subgraph.issues.length > maxRows)
			return runListRowLimitExceeded(subgraph.issues.length, request.maxRowsSource, maxRows);
		final graph = request.view == "--open" ? openSubgraph(subgraph) : subgraph;
		// Upstream prints this line even with --json.
		if (graph == null) {
			output.writeStdout("No open issues in subgraph\n");
			return 0;
		}
		final layout = computeGraphLayout([for (issue in graph.issues) issue.id], graph.edges);
		// With --json, upstream ignores the other view flags.
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderGraphJson(graph, layout, output.usesJsonEnvelope()));
		switch request.view {
			case "--open" | "--compact":
				output.writeStdout(renderGraphCompact(graph, layout, terminalStyles()));
				return 0;
			case "--dot":
				output.writeStdout(renderGraphDot(graph, layout));
				return 0;
			case "--html":
				output.writeStdout(renderGraphHtml(graph, layout));
				return 0;
			case "--box":
				output.writeStdout(renderGraphBox(graph, layout, terminalStyles()));
				return 0;
			case _:
				output.writeStdout(renderGraphVisual(graph, layout, terminalStyles()));
				return 0;
		}
	}

	/**
		Upstream graph --all: reads the row cap first, then loads the open issues (see
		readAllGraphs), groups them (see groupAllGraphs) and prints every group. With no
		group it prints "No open issues found", even with --json.
	**/
	function runGraphAll(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final request = invocation.graph;
		final maxRows = switch request.maxRows {
			case IntPresent(value): value;
			case IntAbsent: 0;
		};
		if (maxRows < 0)
			return runModeAwareFailure(invocation.output, '--max-rows must be non-negative; got ${maxRows}');
		if (request.maxRowsWarning != "")
			output.writeStderr(request.maxRowsWarning);
		final graphs = switch query.graphAll(location.path, location.databaseName, maxRows, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, 'loading all issues: ${message}');
			case Success(AllGraphRowLimitExceeded(found, cap)): return runListRowLimitExceeded(found, request.maxRowsSource, cap);
			case Success(AllGraphRows(issues, rows)):
				switch keepGraphRows(invocation, location, query, issues, rows) {
					case Failure(message): return runModeAwareFailure(invocation.output, 'loading all issues: ${message}');
					case Success(kept): assembleAllGraphs(kept.issues, kept.rows, request.view == "--open");
				}
		};
		if (graphs.length == 0) {
			output.writeStdout("No open issues found\n");
			return 0;
		}
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderAllGraphsJson(graphs));
		final views:Array<GraphSubgraph> = [
			for (graph in graphs)
				{
					root: graph.root,
					issues: graph.issues,
					edges: [
						for (row in graph.dependencies)
							{issueId: row.issueId, dependsOnId: row.dependsOnId, type: row.type}
					]
				}
		];
		output.writeStdout(renderAllGraphViews(views, request.view, terminalStyles()));
		return 0;
	}

	/**
		The rows of a loaded graph that upstream's graph loaders keep (see
		selectGraphRows), with the issues that external rows add after the loaded
		ones.

		Why: upstream looks each external row's `<id>` up with
		resolveAndGetIssueWithRouting (cmd/bd/routed.go:70-96) when the graph does
		not hold that ID yet.
		What: the lookup first resolves the ID in this database as a partial ID
		(see lookupIssueSummary). An error other than "not found", such as an
		ambiguous ID, leaves the row out. A miss tries the routes.jsonl prefix
		routes (see prefixRouteLeaves) and then contributor auto-routing, which
		first asks for the user's role (see warnUnconfiguredRole and autoRoute).
		When either would open another repository, this fails with
		GRAPH_EXTERNAL_UNAVAILABLE; else the row is left out.
		How: each ID resolves once in this database; the routes run for each miss,
		as upstream's warnings repeat. The added issues are read like GetIssue.
	**/
	function keepGraphRows(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort, issues:Array<RelatedIssue>,
			rows:Array<GraphDependency>):StoreResult<KeptGraph> {
		final resolved = new Map<String, StoreResult<IssueLookup>>();
		var autoRouted:Null<Bool> = null;
		function lookup(target:String):ExternalTargetLookup {
			var found = resolved.get(target);
			if (found == null) {
				found = lookupIssueSummary(location, target, invocation.global, query);
				resolved.set(target, found);
			}
			switch found {
				case Success(IssueFound(summary)):
					return ExternalTargetFound(summary.id);
				case Failure(_):
					return ExternalTargetMissing;
				case Success(IssueMissing):
			}
			if (prefixRouteLeaves(location.path, target, lookups.follow))
				return ExternalTargetElsewhere;
			warnUnconfiguredRole();
			if (autoRouted == null)
				autoRouted = autoRoute(location, invocation.global, query).match(AutoRouteElsewhere);
			return autoRouted ? ExternalTargetElsewhere : ExternalTargetMissing;
		}
		final edges:Array<GraphEdge> = [for (row in rows) row];
		return switch selectGraphRows([for (issue in issues) issue.id], edges, lookup) {
			case GraphRowsElsewhere:
				Failure(GRAPH_EXTERNAL_UNAVAILABLE);
			case GraphRowsSelected(addedIds, kept):
				final keptRows = [
					for (row in kept)
						withTarget(rows[row.index], row.dependsOnId)
				];
				if (addedIds.length == 0) {
					Success({issues: issues, rows: keptRows});
				} else {
					final distinct = new Array<String>();
					for (id in addedIds)
						if (!distinct.contains(id))
							distinct.push(id);
					switch query.graphIssues(location.path, location.databaseName, distinct, invocation.global) {
						case Failure(message): Failure(message);
						case Success(read):
							final byId = [for (issue in read) issue.id => issue];
							Success({issues: issues.concat([for (id in addedIds) byId.get(id)]), rows: keptRows});
					}
				}
		};
	}

	/** `row` pointing to `dependsOnId`, which an external row's rewrite can change. */
	static function withTarget(row:GraphDependency, dependsOnId:String):GraphDependency {
		if (row.dependsOnId == dependsOnId)
			return row;
		return {
			issueId: row.issueId,
			dependsOnId: dependsOnId,
			type: row.type,
			createdAt: row.createdAt,
			createdBy: row.createdBy,
			metadata: row.metadata,
			threadId: row.threadId
		};
	}

	/**
		Where upstream's contributor auto-routing (openRoutedReadStore,
		cmd/bd/routing_read.go:158-175) sends a read: the planning repository of
		autoRouteTarget, made absolute like upstream routing.ExpandPath. Upstream
		opens that repository's `.beads` read-only; when that is this store's
		`.beads` (see sameDirectory), it reads this store a second time.

		Each routing setting comes from config.yaml or the environment when it is
		set there to more than spaces, or else from the database's config table.
		A workspace whose config table this build cannot read yet (server mode)
		takes config.yaml and the environment only.
	**/
	function autoRoute(location:WorkspaceLocation, global:Bool, query:IssueQueryPort):AutoRoute {
		final config = LayeredConfig.forWorkspace(location.path);
		final stored = new Map<String, String>();
		switch query.configSettings(location.path, location.databaseName, global) {
			case Success(settings):
				for (setting in settings)
					stored.set(setting.key, setting.value);
			case Failure(_):
		}
		function setting(key:String):String {
			final configured = config.source(key) == DefaultSource ? "" : goTrimSpace(config.getString(key));
			if (configured != "")
				return configured;
			final value = stored.get(key);
			return value == null ? "" : goTrimSpace(value);
		}
		final target = autoRouteTarget(setting, UserRole.detect);
		if (target == null)
			return NoAutoRoute;
		return sameDirectory(FilepathPkg.join(expandRoutePath(target.repository), ".beads"),
			location.path) ? AutoRouteToCurrent(target.rule) : AutoRouteElsewhere;
	}

	/**
		Upstream openRoutedReadStore before list, ready and children read
		(cmd/bd/list.go:231-240, cmd/bd/ready.go:124-138), after the role
		warning that it asks for. Null to read this store, or the exit code of a
		refusal where upstream would read another repository.

		When auto-routing names this workspace again, upstream reads the same
		issues and prints its note on stderr, unless --quiet, with the number of
		rows of the issues table. The count reads this build's embedded store
		only, so a server-mode workspace refuses there.
	**/
	function routeListRead(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Null<Int> {
		warnUnconfiguredRole();
		final command = commandPath(invocation.command);
		return switch autoRoute(location, invocation.global, query) {
			case NoAutoRoute:
				null;
			case AutoRouteElsewhere:
				runModeAwareFailure(invocation.output, routedListUnavailable(command));
			case AutoRouteToCurrent(_) if (opensServerStore(location)):
				runModeAwareFailure(invocation.output, routedListServerUnavailable(command));
			case AutoRouteToCurrent(rule):
				if (!invocation.quiet) {
					final total:Null<Int> = switch query.issueTotal(location.path, location.databaseName, invocation.global) {
						case Success(value): value;
						case Failure(_): null;
					};
					output.writeStderr(autoRouteNote(rule, total));
				}
				null;
		};
	}

	/**
		The groups of `bd graph --all` with their issues and complete rows (see
		groupAllGraphs). Under `--open`, upstream filterSubgraphOpen filters each
		group (see filterOpenGraph). Only an external row can add an issue that is
		not open; a new `blocks` row over such an issue has only its IDs and type,
		like upstream's synthetic types.Dependency.
	**/
	static function assembleAllGraphs(issues:Array<RelatedIssue>, dependencies:Array<GraphDependency>, open:Bool):Array<AllGraph> {
		final summaries:Array<AllGraphIssue> = [for (issue in issues) issue];
		final edges:Array<GraphEdge> = [for (row in dependencies) row];
		final byId = [for (issue in issues) issue.id => issue];
		final graphs = new Array<AllGraph>();
		for (group in groupAllGraphs(summaries, edges)) {
			final members = [for (id in group.issueIds) byId.get(id)];
			final rows = [for (index in group.edgeIndexes) dependencies[index]];
			if (!open) {
				graphs.push({root: byId.get(group.rootId), issues: members, dependencies: rows});
				continue;
			}
			final openIssues:Array<OpenGraphIssue> = [for (issue in members) issue];
			final rowEdges:Array<GraphEdge> = [for (row in rows) row];
			final filtered = filterOpenGraph(group.rootId, openIssues, rowEdges);
			if (filtered == null)
				continue;
			final kept = new Array<GraphDependency>();
			for (index in 0...filtered.edges.length) {
				final source = filtered.sources[index];
				final edge = filtered.edges[index];
				kept.push(source >= 0 ? rows[source] : {
					issueId: edge.issueId,
					dependsOnId: edge.dependsOnId,
					type: edge.type,
					createdAt: "0001-01-01T00:00:00Z",
					createdBy: "",
					metadata: "",
					threadId: ""
				});
			}
			graphs.push({
				root: byId.get(filtered.rootId),
				issues: [for (issue in members) if (isOpenGraphStatus(issue.status)) issue],
				dependencies: kept
			});
		}
		return graphs;
	}

	/**
		Prints the groups as upstream outputJSON prints its []*TemplateSubgraph. A list
		skips the schema_version round trip, so every object keeps its Go struct field
		order; only IssueMap, a Go map, prints its keys in byte order. The template fields
		that a graph never sets print their zero values, and no rows print as null.
	**/
	static function renderAllGraphsJson(graphs:Array<AllGraph>):StoreResult<String> {
		function renderIssue(issue:RelatedIssue, indent:String):StoreResult<String> {
			return switch renderIssueFields(issue, false, indent + "  ", issue.labels) {
				case Failure(message): Failure(message);
				case Success(fields): Success(renderJsonObject(fields, indent));
			};
		}
		final rendered = new Array<String>();
		for (graph in graphs) {
			final root = switch renderIssue(graph.root, "    ") {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final issues = new Map<String, String>();
			for (issue in graph.issues)
				switch renderIssue(issue, "      ") {
					case Failure(message):
						return Failure(message);
					case Success(value):
						issues.set(issue.id, value);
				}
			final ids = [for (issue in graph.issues) issue.id];
			final list = [for (id in ids) '      ${issues.get(id)}'];
			ids.sort(compareUtf8);
			final entries = [for (id in ids) '      ${Json.stringify(id)}: ${issues.get(id)}'];
			final rows = [
				for (row in graph.dependencies)
					'      ${renderJsonObject(renderDependencyFields(row), "      ")}'
			];
			final dependencies = rows.length == 0 ? "null" : "[\n" + rows.join(",\n") + "\n    ]";
			rendered.push("  " + renderJsonObject([
				'"Root": ${root}',
				'"Issues": [\n${list.join(",\n")}\n    ]',
				'"Dependencies": ${dependencies}',
				'"IssueMap": {\n${entries.join(",\n")}\n    }',
				'"VarDefs": null',
				'"Phase": ""',
				'"Pour": false'
			], "  "));
		}
		return Success("[\n" + rendered.join(",\n") + "\n]\n");
	}

	/** A types.Dependency in struct order; a dependency read leaves its `id` empty, so it is left out. */
	static function renderDependencyFields(row:GraphDependency):Array<String> {
		final fields = [
			'"issue_id": ${Json.stringify(row.issueId)}',
			'"depends_on_id": ${Json.stringify(row.dependsOnId)}',
			'"type": ${Json.stringify(row.type)}',
			'"created_at": ${Json.stringify(row.createdAt)}'
		];
		if (row.createdBy != "")
			fields.push('"created_by": ${Json.stringify(row.createdBy)}');
		if (row.metadata != "")
			fields.push('"metadata": ${Json.stringify(row.metadata)}');
		if (row.threadId != "")
			fields.push('"thread_id": ${Json.stringify(row.threadId)}');
		return fields;
	}

	/** Upstream filterSubgraphOpen (see filterOpenGraph): the open issues in load order; null when there is none. */
	static function openSubgraph(subgraph:GraphSubgraph):Null<GraphSubgraph> {
		final summaries:Array<OpenGraphIssue> = [for (issue in subgraph.issues) issue];
		final open = filterOpenGraph(subgraph.root.id, summaries, subgraph.edges);
		if (open == null)
			return null;
		final issues = [for (issue in subgraph.issues) if (isOpenGraphStatus(issue.status)) issue];
		var root = subgraph.root;
		for (issue in issues)
			if (issue.id == open.rootId)
				root = issue;
		return {root: root, issues: issues, edges: open.edges};
	}

	/**
		Prints upstream's map of `root`, `issues` and `layout` (a GraphLayout) as outputJSON does.

		Without the envelope, the schema_version round trip turns every object into a
		map, so every key prints in byte order. With BD_JSON_ENVELOPE=1 only the outer
		map is sorted: issues and the layout keep their Go struct field order. A nil
		slice prints as null. Every view of one issue prints the same record.
	**/
	static function renderGraphJson(subgraph:GraphSubgraph, layout:GraphLayout, structOrder:Bool):StoreResult<String> {
		function renderIssue(issue:RelatedIssue, indent:String):StoreResult<String> {
			final fields = switch renderIssueFields(issue, !structOrder, indent + "  ", issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			if (!structOrder)
				fields.sort(compareJsonFields);
			return Success(renderJsonObject(fields, indent));
		}
		final issues = new Array<String>();
		final issueById = new Map<String, RelatedIssue>();
		for (issue in subgraph.issues) {
			issueById.set(issue.id, issue);
			switch renderIssue(issue, "    ") {
				case Failure(message):
					return Failure(message);
				case Success(value):
					issues.push("    " + value);
			}
		}
		final nodeIds = [for (id in layout.nodes.keys()) id];
		nodeIds.sort(compareUtf8);
		final nodes = new Array<String>();
		for (id in nodeIds) {
			final placement = layout.nodes.get(id);
			final rendered = switch renderIssue(issueById.get(id), "        ") {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final fields = [
				'"Issue": ${rendered}',
				'"Layer": ${placement.layer}',
				'"Position": ${placement.position}',
				'"DependsOn": ${renderJsonStrings(placement.dependsOn, "        ")}'
			];
			if (!structOrder)
				fields.sort(compareJsonFields);
			nodes.push('      ${Json.stringify(id)}: ${renderJsonObject(fields, "      ")}');
		}
		final layers = [for (layer in layout.layers) '      ${renderJsonStrings(layer, "      ")}'];
		final layoutFields = [
			'"Nodes": {\n${nodes.join(",\n")}\n    }',
			'"Layers": [\n${layers.join(",\n")}\n    ]',
			'"MaxLayer": ${layout.maxLayer}',
			'"RootID": ${Json.stringify(subgraph.root.id)}'
		];
		if (!structOrder)
			layoutFields.sort(compareJsonFields);
		final root = switch renderIssue(subgraph.root, "  ") {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		return Success(renderJsonObject([
			'"issues": [\n${issues.join(",\n")}\n  ]',
			'"layout": ${renderJsonObject(layoutFields, "  ")}',
			'"root": ${root}',
			'"schema_version": 1'
		], "") + "\n");
	}

	/** An indented object whose own line starts at `indent`; each field is already rendered at `indent` plus two spaces. */
	static function renderJsonObject(fields:Array<String>, indent:String):String {
		return "{\n" + [for (field in fields) '${indent}  ${field}'].join(",\n") + '\n${indent}}';
	}

	/**
		An object of already-rendered members whose own line starts at `indent`, or `{}`
		for none. `sorted` puts the members in byte order, as a map round trip does;
		otherwise they keep the struct order that they come in.
	**/
	static function renderJsonMembers(fields:Array<String>, sorted:Bool, indent:String):String {
		if (fields.length == 0)
			return "{}";
		final members = fields.copy();
		if (sorted)
			members.sort(compareJsonFields);
		return renderJsonObject(members, indent);
	}

	/** Each value as a JSON string. */
	static function jsonStrings(values:Array<String>):Array<String> {
		return [for (value in values) Json.stringify(value)];
	}

	/** An indented array of already-rendered values whose own line starts at `indent`, or `[]` for an empty slice. */
	static function renderJsonArray(values:Array<String>, indent:String):String {
		if (values.length == 0)
			return "[]";
		return "[\n" + [for (value in values) '${indent}  ${value}'].join(",\n") + '\n${indent}]';
	}

	/** An indented string list, or null for an empty one, as Go prints a nil slice. */
	static function renderJsonStrings(values:Array<String>, indent:String):String {
		if (values.length == 0)
			return "null";
		return "[\n" + [for (value in values) '${indent}  ${Json.stringify(value)}'].join(",\n") + '\n${indent}]';
	}

	/** Opens the selected workspace's query like `bd blocked`, runs `action` with it, then closes it. */
	function runWithIssueQuery(invocation:Invocation, action:(IssueQueryPort, WorkspaceLocation) -> Int):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query): closeIssueQuery(query, action(query, location));
						}
				}
		};
	}

	/**
		Upstream typesCmd: the database custom types, then the types.custom names
		from the layered config.yaml files and BD_TYPES_CUSTOM.
	**/
	function runTypes(invocation:Invocation):Int {
		return runWithLayeredConfig(invocation, false, true, (config, location, query) -> {
			if (invocation.typesSections)
				return runTypeSections(invocation, location);
			return switch query.customTypes(location.path, location.databaseName, invocation.global) {
				case Failure(message): runModeAwareFailure(invocation.output, message);
				case Success(stored):
					final customTypes = effectiveCustomTypes(stored, config.list("types.custom"));
					if (invocation.output == Json)
						writeJsonStdout(renderTypesJson(customTypes, output.usesJsonEnvelope()));
					else
						output.writeStdout(renderTypesText(customTypes));
					0;
			};
		}, sharedServerPreflight(Types));
	}

	/**
		Upstream statusesCmd: the database custom statuses, or without them the
		status.custom entries from the layered config.yaml files and BD_STATUS_CUSTOM.
	**/
	function runStatuses(invocation:Invocation):Int {
		return runWithLayeredConfig(invocation, false, true,
			(config, location, query) -> switch query.customStatuses(location.path, location.databaseName, invocation.global) {
				case Failure(message): runModeAwareFailure(invocation.output, message);
				case Success(stored):
					final customStatuses = effectiveCustomStatuses(stored, config.list("status.custom"));
					if (invocation.output == Json)
						writeJsonStdout(renderStatusesJson(customStatuses, output.usesJsonEnvelope()));
					else
						output.writeStdout(renderStatusesText(customStatuses, terminalStyles()));
					0;
			}, sharedServerPreflight(Statuses));
	}

	/**
		The section list is static, but upstream opens the store before any command runs,
		so a store that cannot open fails here too. A proxied session is already open.
	**/
	function runTypeSections(invocation:Invocation, location:WorkspaceLocation):Int {
		if (!location.proxiedServer)
			switch store.validate(location.path, invocation.global) {
				case Failure(message):
					return runStoreFailure(message);
				case Success(_):
			}
		if (invocation.output == Json)
			writeJsonStdout(renderTypeSectionsJson());
		else
			output.writeStdout(renderTypeSectionsText());
		return 0;
	}

	function runBlocked(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.blockedIssues(location.path, location.databaseName, invocation.listRequest.parentId,
									invocation.global) {
									case Failure(message): runModeAwareFailure(invocation.output, message);
									case Success(blocked): renderBlocked(invocation, blocked);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Upstream `bd blocked` (cmd/bd/ready.go:320-335): pass and fail marks,
		the styled priority and ID; `%v` prints the blocker list as `[a b]`.
	**/
	function renderBlocked(invocation:Invocation, blocked:Array<BlockedIssue>):Int {
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderBlockedJson(blocked));
		final styles = terminalStyles();
		if (blocked.length == 0) {
			output.writeStdout('\n${styles.renderPass("✨")} No blocked issues\n\n');
			return 0;
		}
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderFail("🚫")} Blocked issues (${blocked.length}):\n\n');
		for (entry in blocked) {
			rendered.add('[${styles.renderPriority(entry.issue.priority)}] ${styles.renderId(entry.issue.id)}: ${entry.issue.title}\n');
			rendered.add('  Blocked by ${entry.blockedBy.length} open dependencies: [${entry.blockedBy.join(" ")}]\n\n');
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	/** Each entry is the full issue followed by blocked_by_count and blocked_by, like upstream BlockedIssue. */
	static function renderBlockedJson(blocked:Array<BlockedIssue>):StoreResult<String> {
		if (blocked.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (index in 0...blocked.length) {
			final entry = blocked[index];
			final fields = switch renderIssueFields(entry.issue, false, "    ", entry.issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"blocked_by_count": ${entry.blockedBy.length}');
			fields.push(renderRawStringArray("blocked_by", entry.blockedBy, "    "));
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == blocked.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	function runComments(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runCommentsQuery(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/** Resolves the issue, then reads and prints its comments, in the order upstream commentsCmd does. */
	function runCommentsQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final request = invocation.comments;
		if (request.misplacedList)
			return runModeAwareFailure(invocation.output, MISPLACED_COMMENTS_LIST);
		final issueId = switch lookupIssueWithRouting(location, request.issueId, invocation.global, query) {
			case ReadElsewhere: return runRoutedLookupRefusal(invocation);
			case ReadHere(Failure(message)): return runModeAwareFailure(invocation.output, 'resolving ${request.issueId}: ${message}');
			case ReadHere(Success(IssueMissing)):
				return runModeAwareFailure(invocation.output, 'resolving ${request.issueId}: no issue found matching "${request.issueId}"');
			case ReadHere(Success(IssueFound(summary))): summary.id;
		};
		final comments = switch query.issueComments(location.path, location.databaseName, issueId, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, 'getting comments: ${message}');
			case Success(value): value;
		};
		if (invocation.output == Json) {
			writeJsonStdout(renderCommentsJson(comments));
			return 0;
		}
		if (comments.length == 0) {
			output.writeStdout('No comments on ${issueId}\n');
			return 0;
		}
		final rendered = new StringBuf();
		rendered.add('\nComments on ${issueId}:\n\n');
		for (comment in comments) {
			rendered.add('[${comment.author}] at ${commentTimestamp(comment.createdAt, request.localTime)}\n');
			for (line in trimTrailingNewlines(output.renderMarkdown(comment.text)).split("\n"))
				rendered.add('  ${line}\n');
			rendered.add("\n");
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	/**
		Resolves the issue, then reads its commit snapshots or its events, as upstream historyCmd does.
		A proxied workspace skips the resolution upstream, and --global always selects a server database.
	**/
	function runHistoryQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final request = invocation.history;
		if (location.proxiedServer || invocation.global)
			return runModeAwareFailure(invocation.output, HISTORY_ROUTE_UNAVAILABLE);
		// Only an ambiguous ID is fatal; every other miss keeps the typed ID, which then has no history (GH#3502).
		var issueId = request.issueId;
		switch lookupIssueSummary(location, request.issueId, invocation.global, query) {
			case Success(IssueFound(summary)):
				issueId = summary.id;
			case Success(IssueMissing):
			case Failure(message):
				if (StringTools.startsWith(message, AMBIGUOUS_ISSUE_ID))
					return runModeAwareFailure(invocation.output, message);
		}
		if (request.events) {
			final events = switch query.issueEvents(location.path, location.databaseName, issueId, request.limit, invocation.global) {
				case Failure(message): return runModeAwareFailure(invocation.output, 'failed to get history events: ${message}');
				case Success(value): value;
			};
			if (invocation.output == Json)
				writeJsonStdout(renderHistoryEventsJson(events));
			else
				output.writeStdout(renderHistoryEventsText(issueId, events, terminalStyles()));
			return 0;
		}
		final history = switch query.issueHistory(location.path, location.databaseName, issueId, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, 'failed to get history: ${message}');
			case Success(value): value;
		};
		// Upstream applies --limit after the read.
		final shown = request.limit > 0 && request.limit < history.length ? history.slice(0, request.limit) : history;
		if (invocation.output == Json)
			writeJsonStdout(renderHistoryJson(shown));
		else
			output.writeStdout(renderHistoryText(issueId, shown, terminalStyles()));
		return 0;
	}

	/**
		Upstream runEventsTail without --follow: reads the journal after the checkpoint and prints one JSON
		line per row. A checkpoint that the retained rows do not continue fails with the retained window.
	**/
	function runEventsRead(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final unavailable = '${invocation.command == EventsTail ? "events tail" : "events export"} is not available yet for server-mode or proxied workspaces in this build';
		if (location.proxiedServer || invocation.global)
			return runModeAwareFailure(invocation.output, unavailable);
		final since = invocation.events.since;
		// A negative checkpoint would serve the whole journal as if it were a resume.
		if (since < 0)
			return runModeAwareFailure(invocation.output,
				'--since must be zero or a positive sequence number (got ${haxe.Int64.toStr(since)}); use 0 to read from the beginning');
		return switch query.eventsJournal(location.path, location.databaseName, since, invocation.events.limit, invocation.global) {
			case Failure(message):
				runModeAwareFailure(invocation.output, 'reading events journal: ${message}');
			case Success(JournalRouteUnavailable):
				runModeAwareFailure(invocation.output, unavailable);
			case Success(JournalTruncated(window)):
				if (invocation.output == Json)
					writeJsonStdout(renderEventsTruncatedJson(window, output.usesJsonEnvelope()));
				else
					output.writeStderr('Error: ${eventsTruncatedMessage(window)}\nHint: ${eventsTruncatedHint(window)}\n');
				1;
			case Success(JournalRecords(rows)):
				// Records are JSON lines in every mode, outside the JSON envelope.
				final lines = renderEventsRecords(rows);
				output.writeStdout(lines.text);
				lines.error == null ? 0 : runModeAwareFailure(invocation.output, 'reading events journal: ${lines.error}');
		};
	}

	/**
		The hidden BeadsHX snapshot extension (BHX-M08-09, spec v1): every issue
		of an embedded workspace and the revision it comes from, as
		`TaskSnapshot` describes. Upstream has no such command.

		It reads embedded workspaces only, and refuses `--global`, shared-server,
		server-mode and proxied workspaces before it opens anything. The parser
		keeps this command in human output, so every error goes to stderr. It
		prints the artifact in one write after the whole read, so stdout holds
		the whole artifact or nothing.
	**/
	function runSnapshot(invocation:Invocation):Int {
		if (invocation.global)
			return runModeAwareFailure(OutputMode.Human, TaskSnapshot.ROUTE_UNAVAILABLE);
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(OutputMode.Human, message);
					case Accepted:
						if (location.proxiedServer || opensServerStore(location)) runModeAwareFailure(OutputMode.Human,
							TaskSnapshot.ROUTE_UNAVAILABLE); else if (!findsDatabase(invocation,
							location)) runWorkspaceDatabaseNotFound(location); else switch store.taskSnapshot(location.path,
							selectedDatabaseName(invocation, location)) {
							case Failure(message): runStoreFailure(message);
							case Success(artifact):
								output.writeStdout(artifact);
								0;
						}
				}
		};
	}

	/**
		Upstream configGetCmd. The key's source decides the route: the database
		config table, the layered config.yaml and environment values, git config,
		or backup.enabled's effective value. YAML and git keys run without a
		database, as upstream's configCommandCanRunWithoutStore lets them.
	**/
	function runConfigGet(invocation:Invocation):Int {
		final key = invocation.configKey;
		final storeFree = isYamlOnlyKey(key) || key == "beads.role";
		final readsTable = !storeFree && goTrimSpace(key) != "" && !isKvPlaneKey(key);
		return runWithLayeredConfig(invocation, storeFree, readsTable, (config, location, query) -> {
			if (key == "backup.enabled")
				return showBackupEnabled(invocation, config, location != null);
			if (isYamlOnlyKey(key)) {
				if (isUserGlobalKey(key)) {
					// Upstream reads these from the user config.yaml alone, with its own YAML rules.
					if (userConfigYamlPresent())
						return runModeAwareFailure(invocation.output, 'config get ${key} is not available yet when a user config.yaml exists in this build');
					return showConfigValue(invocation, key, "", userConfigYamlDisplayPath());
				}
				return showConfigValue(invocation, key, config.getString(key), "config.yaml");
			}
			if (key == "beads.role")
				return showConfigValue(invocation, key, gitBeadsRole(), "git config");
			if (goTrimSpace(key) == "")
				return runStoreFailure("getting config: validation failed: config key must not be empty");
			// The kv. plane shares the table; upstream answers it as absent without a read.
			if (isKvPlaneKey(key))
				return showConfigValue(invocation, key, "", null);
			return switch query.configValue(location.path, selectedDatabaseName(invocation, location), key, invocation.global) {
				case Failure(message): runConfigReadFailure(invocation, "getting config", message);
				case Success(value): showConfigValue(invocation, key, value, null);
			};
		}, sharedServerPreflight(ConfigGet));
	}

	function showConfigValue(invocation:Invocation, key:String, value:String, location:Null<String>):Int {
		if (invocation.output == Json)
			writeJsonStdout(renderConfigGetJson(key, value, location));
		else
			output.writeStdout(renderConfigGetText(key, value, location));
		return 0;
	}

	/**
		Upstream runConfigGetBackupEnabled. An unset key is on in an embedded
		workspace whose Git checkout has a remote and off in shared-server mode.
	**/
	function showBackupEnabled(invocation:Invocation, config:LayeredConfig, workspaceSelected:Bool):Int {
		final source = config.source("backup.enabled");
		final sharedServer = config.sharedServerMode();
		final effective = source != DefaultSource ? config.getBool("backup.enabled") : (!sharedServer && workspaceSelected && gitHasRemote());
		if (invocation.output == Json) {
			writeJsonStdout(renderBackupEnabledJson(effective, source));
			return 0;
		}
		final description = switch source {
			case EnvironmentSource: "env var";
			case ConfigFileSource: "config.yaml";
			case DefaultSource if (sharedServer): "default (auto: off in sql-server mode)";
			case DefaultSource if (effective): "default (auto: on — git remote detected)";
			case DefaultSource: "default (auto: off — no git remote)";
		};
		output.writeStdout(renderBackupEnabledText(effective, description));
		return 0;
	}

	/** Upstream configListCmd: the stored settings, then the config.yaml and environment notes. */
	function runConfigList(invocation:Invocation):Int {
		return runWithLayeredConfig(invocation, false, true, (config, location, query) -> {
			final stored = switch query.configSettings(location.path, selectedDatabaseName(invocation, location), invocation.global) {
				case Failure(message): return runConfigReadFailure(invocation, "listing config", message);
				case Success(rows): [for (row in rows) if (!isKvPlaneKey(row.key)) row];
			};
			if (invocation.output == Json)
				writeJsonStdout(renderConfigListJson(stored));
			else
				output.writeStdout(renderConfigListText(stored, config.allKeys(), config.facts, goQuote));
			return 0;
		}, sharedServerPreflight(ConfigList));
	}

	/**
		Upstream configShowCmd: the layered keys, the metadata.json fields, the
		database config table without the kv. plane, git's beads.role and
		BEADS_MAX_ROWS, sorted by key and kept when their source starts with
		--source. Upstream creates an embedded database when the workspace has
		none, and reads user-global keys from the user config.yaml; this build
		refuses both cases.
	**/
	function runConfigShow(invocation:Invocation):Int {
		return runWithLayeredConfig(invocation, true, true, (config, location, query) -> {
			final databaseEntries = new Array<ConfigShowEntry>();
			if (query != null) {
				switch query.configSettings(location.path, selectedDatabaseName(invocation, location), invocation.global) {
					case Failure(message) if (message == CONFIG_ROUTE_UNAVAILABLE):
						return runModeAwareFailure(invocation.output, message);
					// Upstream lists no database rows when the table read fails.
					case Failure(_):
					case Success(rows):
						for (row in rows)
							if (!isKvPlaneKey(row.key))
								databaseEntries.push({key: row.key, value: row.value, source: "database"});
				}
			} else if (location != null)
				return runModeAwareFailure(invocation.output, "config show is not available yet for a workspace without a database in this build");
			if (userConfigYamlPresent())
				return runModeAwareFailure(invocation.output, "config show is not available yet when a user config.yaml exists in this build");
			// Upstream's collectMetadataEntries finds the workspace for its metadata.json rows (cmd/bd/config_show.go:237).
			lookups.findBeadsDir();
			final metadataEntries = location == null ? [] : readWorkspaceMetadata(location.path);
			// Upstream gathers the rows in this order before its sort, which leaves rows with one key in either order.
			final entries = layeredEntries(config.allKeys(), config.facts, environmentValue("BEADS_ACTOR")).concat(metadataEntries).concat(databaseEntries);
			final role = gitBeadsRole();
			if (role != "")
				entries.push({key: "beads.role", value: role, source: "git"});
			final maxRows = environmentValue("BEADS_MAX_ROWS");
			if (maxRows != "")
				entries.push({key: "BEADS_MAX_ROWS", value: maxRows, source: "env: BEADS_MAX_ROWS"});
			final shown = filterConfigShowEntries(sortConfigShowEntries(entries), invocation.configSource);
			if (invocation.output == Json)
				writeJsonStdout(renderConfigShowJson(shown));
			else
				output.writeStdout(renderConfigShowText(shown));
			return 0;
		}, sharedServerPreflight(ConfigShow));
	}

	/**
		Upstream configValidateCmd: doctor's config.yaml, metadata.json and
		database checks, then the sync checks of the workspace config.yaml. The
		JSON form exits 0 even when it lists issues, as upstream's does. The
		database check dials a Dolt server only when a Dolt data directory exists.
	**/
	function runConfigValidate(invocation:Invocation):Int {
		if (invocation.global)
			return runModeAwareFailure(invocation.output, CONFIG_ROUTE_UNAVAILABLE);
		return runWithLayeredConfig(invocation, true, false, (config, location, _) -> {
			// Upstream finds the workspace (resolvedConfigRepoRoot, cmd/bd/config.go:787), then doctor's findConfigPath resolves its repository's .beads (doctor/config_values.go:96).
			final found = lookups.findBeadsDir();
			if (found != "")
				lookups.resolveBeadsDirForRepo(Path.directory(found));
			if (location == null) {
				final message = "no active beads workspace found";
				final hint = workspaceDiagHint(true, config.sharedServerMode());
				if (invocation.output == Json)
					writeJsonStdout('{\n  "error": ${Json.stringify(message)},\n  "hint": ${Json.stringify(hint)},\n  "schema_version": 1\n}\n');
				else
					output.writeStderr('Error: ${message}\nHint: ${hint}\n');
				return 1;
			}
			final beadsDir = location.path;
			final metadata = workspaceMetadataFields(beadsDir);
			final host = ConfigProbes.validationHost();
			final doctorIssues = new Array<String>();
			final configPath = ConfigProbes.validationConfigPath(beadsDir);
			if (configPath != "")
				switch ConfigProbes.readValidationYaml(configPath) {
					case YamlFailed(message): doctorIssues.push('config.yaml: failed to parse: ${message}');
					case YamlLoaded(yaml): for (issue in yamlConfigIssues(yaml, host))
							doctorIssues.push(issue);
				}
			for (issue in metadataConfigIssues(metadata == null ? null : metadataFacts(metadata), host.quote))
				doctorIssues.push(issue);
			final doltDirectory = ConfigProbes.doltDirectory(beadsDir, metadata);
			if (!ConfigProbes.statMissing(doltDirectory))
				switch ConfigProbes.probeServerStore(beadsDir, doltDirectory, metadata == null ? new Map<String, String>() : metadata, config) {
					case ProbeEndpointConfigured:
						return runModeAwareFailure(invocation.output,
							"config validate is not available yet when a Dolt server endpoint is configured in this build");
					case ProbeAnswered:
						return runModeAwareFailure(invocation.output, "config validate is not available yet when a Dolt server answers in this build");
					case ProbeFailed(message):
						doctorIssues.push('database: failed to open Dolt store: ${message}');
				}
			final syncIssues = switch ConfigProbes.readValidationYaml(ConfigProbes.workspaceConfigPath(beadsDir)) {
				case YamlLoaded(yaml): syncConfigIssues(yaml, host);
				// Upstream skips the sync checks when the workspace config.yaml does not read.
				case YamlFailed(_): [];
			};
			final issues = validationIssues(doctorIssues, syncIssues);
			if (invocation.output == Json) {
				writeJsonStdout(renderValidationJson(issues));
				return 0;
			}
			output.writeStdout(renderValidationText(issues));
			return issues.length == 0 ? 0 : 1;
		}, configPreflight("validate", true), unboundWorkspace(invocation));
	}

	/**
		Upstream configDriftCmd: the git hooks, the Dolt remote and the server
		checks, exiting 1 when one reports drift. In an embedded workspace the
		remote check's server store never opens, so it reports that error.
	**/
	function runConfigDrift(invocation:Invocation):Int {
		if (invocation.global)
			return runModeAwareFailure(invocation.output, CONFIG_ROUTE_UNAVAILABLE);
		return runWithLayeredConfig(invocation, true, false, (config, location, _) -> {
			final items = gitHooksDrift();
			// Upstream's remote and server checks each find the workspace (cmd/bd/config_drift.go:159, :255).
			lookups.findBeadsDir();
			lookups.findBeadsDir();
			if (location == null) {
				items.push(plainItem("remote", DriftSkipped, "No active beads workspace found"));
				items.push(plainItem("server", DriftSkipped, "No active beads workspace found"));
			} else {
				final metadata = workspaceMetadataFields(location.path);
				switch ConfigProbes.probeServerStore(location.path, ConfigProbes.doltDirectory(location.path, metadata),
					metadata == null ? new Map<String, String>() : metadata, config) {
					case ProbeEndpointConfigured:
						return runModeAwareFailure(invocation.output,
							"config drift is not available yet when a Dolt server endpoint is configured in this build");
					case ProbeAnswered:
						return runModeAwareFailure(invocation.output, "config drift is not available yet when a Dolt server answers in this build");
					case ProbeFailed(message):
						items.push(remoteOpenFailureItem(message));
				}
				// The preflight refuses shared-server mode, so the server state lives in the workspace.
				items.push(serverDriftItem(ConfigProbes.serverProbablyRunning(location.path)));
			}
			if (invocation.output == Json)
				writeJsonStdout(renderDriftJson(items));
			else
				output.writeStdout(renderDriftText(items));
			return hasDrift(items) ? 1 : 0;
		}, configPreflight("drift", false), unboundWorkspace(invocation));
	}

	/** Upstream checkHooksDrift: skipped outside a git repository, else the bd hooks in the hooks directory. */
	function gitHooksDrift():Array<DriftItem> {
		final directory = ConfigProbes.gitHooksDirectory();
		if (directory == null)
			return [plainItem("hooks", DriftSkipped, "Not a git repository")];
		return hooksDriftItems(gitHookStatuses(directory), InfoChanges.currentVersion);
	}

	/**
		Upstream CheckGitHooks (cmd/bd/hooks.go:510-548): each bd hook in the
		hooks directory. Without a directory, outside a git repository, every
		hook counts as not installed.
	**/
	static function gitHookStatuses(directory:Null<String>):Array<HookStatus> {
		final version = InfoChanges.currentVersion;
		return [
			for (name in GIT_HOOK_NAMES)
				hookStatus(name, directory == null ? null : ConfigProbes.readHook(directory, name), version)
		];
	}

	/**
		Refusals before `bd config validate` or `bd config drift` opens the
		store. In shared-server mode upstream connects to the shared server,
		which writes (a `db` setting is refused before discovery, as for every
		store command). checkWorkspaceMetadata already stopped a metadata.json
		that does not load and a backend other than Dolt, as upstream's
		legacy-workspace guard does. Validate also reads the workspace
		back from its parent directory, which only a `.beads` directory without
		its own redirect survives unchanged.
	**/
	static function configPreflight(name:String, resolvesFromRepository:Bool):ConfigPreflightInput->Null<String> {
		return input -> {
			final config = input.config;
			final location = input.location;
			if (config.sharedServerMode())
				return sharedServerRefusal('config ${name}');
			// A configured host can make upstream treat the workspace as a server workspace.
			if (environmentValue("BEADS_DOLT_SERVER_HOST") != "" || config.getString("dolt.host") != "")
				return 'config ${name} is not available yet when a Dolt server endpoint is configured in this build';
			if (resolvesFromRepository && !ConfigProbes.resolvesFromRepository(location.path))
				return 'config ${name} is not available yet for this redirected workspace in this build';
			return null;
		};
	}

	/**
		The shared-server refusal before `bd types`, `bd statuses` and `bd config
		get`, `list` or `show` open the store (see validateStoreSelection). When
		upstream finds no database it writes nothing, so the command goes on as
		without shared-server mode, except that the hint for the missing
		database names `bd doctor`.
	**/
	static function sharedServerPreflight(command:Command):ConfigPreflightInput->Null<String> {
		return input -> input.config.sharedServerMode() && input.reachesSharedServer ? sharedServerRefusal(commandPath(command)) : null;
	}

	static function sharedServerRefusal(path:String):String {
		return '${path} is not available yet in shared-server mode in this build';
	}

	static function databaseSettingRefusal(path:String):String {
		return '${path} is not available yet when the db setting names a database in this build';
	}

	/**
		Upstream's pre-run takes the `db` setting from the process-start config
		as the database path only when no --db flag, -C directory, BEADS_DB, BD_DB
		or BEADS_DIR selects the workspace. It then opens, or creates, an
		embedded database at that path for every command that opens a store,
		even when no workspace is found, so runInvocation refuses those commands
		before discovery (see WorkspaceEnvironment.databaseSettingSelects).
	**/
	static function databaseSettingSelects(invocation:Invocation):Bool {
		return WorkspaceEnvironment.databaseSettingSelects({directory: invocation.directory, databasePath: invocation.databasePath});
	}

	/**
		Upstream's pre-run for config commands that can run without a store: a
		workspace with no metadata.json, no database upstream can find and no
		--db selection opens no store. (A configured host, which would make it a
		server workspace, is refused by the preflight.)
	**/
	static function unboundWorkspace(invocation:Invocation):WorkspaceLocation->Bool {
		return location -> invocation.databasePath == ""
			&& location.databasePath == ""
			&& location.databaseName == ""
			&& !location.proxiedServer
			&& switch readMetadataFields(location.path) {
				case MetadataAbsent: true;
				case MetadataFields(_) | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: false;
			};
	}

	/** The decoded metadata.json fields, or null when there are none; checkWorkspaceMetadata stopped a file that does not load. */
	static function workspaceMetadataFields(beadsDir:String):Null<Map<String, String>> {
		return switch readMetadataFields(beadsDir) {
			case MetadataFields(fields): fields;
			case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: null;
		};
	}

	static function metadataFacts(fields:Map<String, String>):MetadataFacts {
		function text(tag:String, zero:String):String {
			final value = fields.get(tag);
			return value == null ? zero : value;
		}
		return {database: text("database", ""), doltDatabase: text("dolt_database", ""), deletionsRetentionDays: text("deletions_retention_days", "0")};
	}

	/** A config table read failure; a route this build does not read is refused like other unported routes. */
	function runConfigReadFailure(invocation:Invocation, operation:String, message:String):Int {
		return message == CONFIG_ROUTE_UNAVAILABLE ? runModeAwareFailure(invocation.output, message) : runStoreFailure('${operation}: ${message}');
	}

	/**
		Loads config like upstream's startup and selected-workspace initializations,
		printing each selected-workspace failure as upstream's warning, then opens the store when the
		command needs it and runs `action`. Upstream initializes for the selected
		workspace once without a database and twice with one (see
		storeInitializations). Upstream also opens the store before any config command runs;
		when `action` reads no table, an empty-key read stands for that open, so a
		database route this build does not read is refused either way. For a found
		workspace, a non-null `preflight` message refuses the command before the
		store opens; every caller passes at least the shared-server refusal.
		`runsWithoutDatabase` can route a workspace upstream finds no database for
		to `action` without a store.
	**/
	function runWithLayeredConfig(invocation:Invocation, storeFree:Bool, readsTable:Bool,
			action:(LayeredConfig, Null<WorkspaceLocation>, Null<IssueQueryPort>) -> Int, preflight:ConfigPreflightInput->Null<String>,
			?runsWithoutDatabase:WorkspaceLocation->Bool):Int {
		// run printed this load's failure before the command started.
		final startup = LayeredConfig.atStartup();
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound:
				final stop = storeLookupsWithoutWorkspace(invocation);
				if (stop != null)
					return stop;
				storeFree ? action(startup, null, null) : runDatabaseNotFound(startup.sharedServerMode());
			case Found(location):
				boundWorkspace = location;
				// Upstream warns about a missing metadata.json after its config warnings and before its database selection checks.
				final defaultDirectory = missingMetadataDirectory(invocation, location);
				// Without a database upstream stops before those checks.
				final selection = findsDatabase(invocation, location) ? validateDatabaseSelection(invocation, location) : Accepted;
				switch selection {
					case PlainFailure(message):
						final initializations = storeInitializations(invocation, location);
						final config = loadStoreConfig(invocation, location, initializations, true);
						final targetRefusal = guardBoundTarget(location, initializations, config);
						if (targetRefusal != null)
							return runStoreFailure(targetRefusal);
						final gateRefusal = holdWorkspaceGates(invocation, location, config);
						if (gateRefusal != null)
							return runModeAwareFailure(invocation.output, gateRefusal);
						trackVersionLookup(invocation, location, config);
						warnStoreConfiguration(location, defaultDirectory, invocation.global);
						runStoreFailure(message);
					case ModeAwareFailure(message):
						final initializations = storeInitializations(invocation, location);
						final config = loadStoreConfig(invocation, location, initializations, true);
						final targetRefusal = guardBoundTarget(location, initializations, config);
						if (targetRefusal != null)
							return runStoreFailure(targetRefusal);
						final gateRefusal = holdWorkspaceGates(invocation, location, config);
						if (gateRefusal != null)
							return runModeAwareFailure(invocation.output, gateRefusal);
						trackVersionLookup(invocation, location, config);
						warnStoreConfiguration(location, defaultDirectory, invocation.global);
						runModeAwareFailure(invocation.output, message);
					case Accepted:
						final reachesServer = reachesSharedServer(invocation, location);
						if (!findsDatabase(invocation, location) || (runsWithoutDatabase != null && runsWithoutDatabase(location))) {
							final config = loadStoreConfig(invocation, location, 1, true);
							final gateRefusal = holdWorkspaceGates(invocation, location, config);
							if (gateRefusal != null)
								return runModeAwareFailure(invocation.output, gateRefusal);
							final refusal = preflight({config: config, location: location, reachesSharedServer: reachesServer});
							if (refusal != null)
								return runModeAwareFailure(invocation.output, refusal);
							storeFree ? action(config, location, null) : runDatabaseNotFound(config.sharedServerMode());
						} else {
							final initializations = storeInitializations(invocation, location);
							final config = loadStoreConfig(invocation, location, initializations, true);
							final targetRefusal = guardBoundTarget(location, initializations, config);
							if (targetRefusal != null)
								return runStoreFailure(targetRefusal);
							final gateRefusal = holdWorkspaceGates(invocation, location, config);
							if (gateRefusal != null)
								return runModeAwareFailure(invocation.output, gateRefusal);
							final strictRefusal = proxiedStrictReadonlyRefusal(invocation, location, config);
							if (strictRefusal != null)
								return runStoreFailure(strictRefusal);
							trackVersionLookup(invocation, location, config);
							// Upstream warns about a missing metadata.json before the store open that a refusal stands for.
							warnMissingMetadata(defaultDirectory);
							final refusal = preflight({config: config, location: location, reachesSharedServer: reachesServer});
							if (refusal != null)
								return runModeAwareFailure(invocation.output, refusal);
							if (defaultDirectory == null)
								warnStoreConfiguration(location, null, invocation.global);
							switch validateOpenedDatabase(invocation, location, defaultDirectory) {
								case PlainFailure(message): return runStoreFailure(message);
								case ModeAwareFailure(message): return runModeAwareFailure(invocation.output, message);
								case Accepted:
							}
							switch openIssueQuery(invocation, location) {
								case Failure(message): runStoreFailure(message);
								case Success(query):
									// Upstream's warnMultipleDatabases follows the store open (cmd/bd/main.go:1688).
									if (looksUpDatabasesAfterOpen(invocation, location))
										lookups.findAllDatabases();
									final probe = readsTable ? Success("") : query.configValue(location.path, selectedDatabaseName(invocation, location), "",
										invocation.global);
									closeIssueQuery(query, switch probe {
										case Failure(message) if (message == CONFIG_ROUTE_UNAVAILABLE): runModeAwareFailure(invocation.output, message);
										case Failure(_) | Success(_): action(config, location, query);
									});
							}
						}
				}
		};
	}

	function runLabel(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = invocation.command == LabelListAll ? runLabelListAll(invocation, location,
									query) : runLabelList(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/** Upstream runLabelList: resolve the argument on this route, then print the labels of the issue's detail read. */
	function runLabelList(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final input = invocation.showIds[0];
		// The proxied route resolves an exact issue or wisp ID only, and calls anything else "not found".
		final resolved = location.proxiedServer ? query.issueSummary(location.path, location.databaseName, input,
			invocation.global) : lookupIssueSummary(location, input, invocation.global, query);
		final issueId = switch resolved {
			case Failure(message): return runModeAwareFailure(invocation.output, 'resolving ${input}: ${message}');
			case Success(IssueMissing):
				final reason = location.proxiedServer ? "not found" : 'no issue found matching "${input}"';
				return runModeAwareFailure(invocation.output, 'resolving ${input}: ${reason}');
			case Success(IssueFound(summary)): summary.id;
		};
		final request:IssueDetailsRequest = {includeDependents: false, includeComments: false, briefDependencies: false};
		final labels = switch query.issueDetails(location.path, issueId, request, invocation.global) {
			case Failure(message): return runModeAwareFailure(invocation.output, message);
			// Upstream's detail read reports a vanished row as workapi's not-found error.
			case Success(DetailsMissing): return runModeAwareFailure(invocation.output, 'not found: issue ${issueId}');
			case Success(DetailsFound(details)): details.labels;
		};
		if (invocation.output == Json)
			writeJsonStdout(renderIssueLabelsJson(labels));
		else
			output.writeStdout(renderIssueLabelsHuman(issueId, labels, terminalStyles()));
		return 0;
	}

	/** Upstream labelListAllCmd: one unfiltered, unlimited search, whose bulk-loaded labels it counts. */
	function runLabelListAll(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (location.proxiedServer)
			return runModeAwareFailure(invocation.output, LABEL_LIST_ALL_ROUTE_UNAVAILABLE);
		final issues = switch query.issueSearch(location.path, location.databaseName, "", IssueListRequests.everyIssue(), invocation.global) {
			case ListFailure(message): return runModeAwareFailure(invocation.output, message);
			// The request sets no row cap, so this branch only completes the switch.
			case ListRowLimitExceeded(found, source, cap): return runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page): page.items;
		};
		final counts = countLabels(issues);
		if (invocation.output == Json)
			writeJsonStdout(renderLabelCountsJson(counts));
		else
			output.writeStdout(renderLabelCountsHuman(counts, terminalStyles()));
		return 0;
	}

	function renderRelatedDepList(invocation:Invocation, ids:Array<String>, dependencies:Array<RelatedIssue>, direction:RelationDirection):Int {
		switch invocation.output {
			case Json:
				return writeRenderedJsonStdout(renderDependencyIssuesJson(dependencies));
			case Human:
				if (dependencies.length == 0) {
					if (ids.length != 1)
						output.writeStdout("\nNo dependencies found\n");
					else if (direction == Incoming)
						output.writeStdout('\nNo issues depend on ${ids[0]}\n');
					else
						output.writeStdout('\n${ids[0]} has no dependencies\n');
				} else {
					// Upstream's dep list (cmd/bd/dep.go:939-955) prints each ID in its status style.
					final styles = terminalStyles();
					for (dependency in dependencies)
						output.writeStdout('  ${styles.renderStatusId(dependency.status, dependency.id)}: ${dependency.title} [P${dependency.priority}] (${dependency.status}) via ${dependency.dependencyType}\n');
					output.writeStdout("\n");
				}
		}
		return 0;
	}

	static function renderDependencyIssuesJson(dependencies:Array<RelatedIssue>):StoreResult<String> {
		if (dependencies.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (index in 0...dependencies.length) {
			final dependency = dependencies[index];
			final fields = switch renderIssueFields(dependency, false, "    ", dependency.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"dependency_type": ${Json.stringify(dependency.dependencyType)}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == dependencies.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	function renderDepList(invocation:Invocation, anchors:Array<beadshx.relation.DependencyAnchor>):Int {
		for (anchor in anchors)
			if (anchor.missing)
				output.writeStderr('warning: no issue found: ${anchor.id} (skipped)\n');
		switch invocation.output {
			case Json:
				final edges = new Array<beadshx.relation.DependencyEdge>();
				for (anchor in anchors)
					for (edge in anchor.edges)
						edges.push(edge);
				writeJsonStdout(renderDependencyEdgesJson(edges));
			case Human:
				final rendered = new StringBuf();
				for (anchor in anchors) {
					if (anchor.missing)
						continue;
					if (anchor.edges.length == 0) {
						rendered.add('\n${anchor.id} has no dependencies\n');
						continue;
					}
					// Upstream printDepListEdges (cmd/bd/dep.go:756-783).
					rendered.add('\n${terminalStyles().renderAccent("📋")} Dependencies of ${anchor.id}:\n\n');
					for (edge in anchor.edges)
						rendered.add('  ${edge.dependsOnId} via ${edge.dependencyType.toString()}\n');
				}
				rendered.add("\n");
				output.writeStdout(rendered.toString());
		}
		return 0;
	}

	static function renderDependencyEdgesJson(edges:Array<beadshx.relation.DependencyEdge>):String {
		if (edges.length == 0)
			return "[]\n";
		final lines = ["["];
		for (index in 0...edges.length) {
			final edge = edges[index];
			final fields = new Array<String>();
			fields.push('"issue_id": ${Json.stringify(edge.issueId)}');
			fields.push('"depends_on_id": ${Json.stringify(edge.dependsOnId)}');
			fields.push('"type": ${Json.stringify(edge.dependencyType.toString())}');
			fields.push('"created_at": ${Json.stringify(edge.createdAt)}');
			if (edge.createdBy != "")
				fields.push('"created_by": ${Json.stringify(edge.createdBy)}');
			if (edge.metadata != "")
				fields.push('"metadata": ${Json.stringify(edge.metadata)}');
			if (edge.threadId != "")
				fields.push('"thread_id": ${Json.stringify(edge.threadId)}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == edges.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	function runCount(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								// Upstream parseCountRequest checks its flags first in the command body.
								final deferredExit = runDeferredChecks(invocation);
								final result = if (deferredExit != null) {
									deferredExit;
								} else switch query.issueCount(location.path, location.databaseName, invocation.countRequest, invocation.countGroup,
									invocation.global) {
									case Failure(message): runStoreFailure(message);
									case Success(count): renderCount(invocation, count);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runReady(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runReadyBody(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Upstream ready's command body, after its pre-run opened the store. It
		checks the --brief rules first. Under a proxied server it then reads
		--max-rows and BEADS_MAX_ROWS, refuses a negative --offset and gathers
		its input before it picks a view. Otherwise it refuses a positive
		--offset, and --gated, --mol and --explain answer without gathering the
		input, so their output ignores what the gathering would report.
	**/
	function runReadyBody(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final modeExit = reportDeferredCheck(invocation, invocation.readyModeCheck);
		if (modeExit != null)
			return modeExit;
		final offset = switch invocation.readyRequest.offset {
			case IntPresent(value): value;
			case IntAbsent: 0;
		};
		if (location.proxiedServer) {
			// Upstream rejectMaxRowsUnderProxiedServer; only --claim takes a cap here, and ignores it.
			final maxRowsExit = runMaxRowsCheck(invocation);
			if (maxRowsExit != null)
				return maxRowsExit;
			switch invocation.readyRequest.maxRows {
				case IntPresent(value) if (value > 0 && !invocation.readyClaim):
					return runModeAwareFailure(invocation.output, "--max-rows / BEADS_MAX_ROWS is not supported in proxied-server mode");
				case IntPresent(_) | IntAbsent:
			}
			if (offset < 0)
				return runStoreFailure("--offset must be >= 0");
			final gatherExit = reportDeferredCheck(invocation, invocation.deferredCheck);
			if (gatherExit != null)
				return gatherExit;
			final filterExit = reportDeferredCheck(invocation, invocation.readyFilterCheck);
			if (filterExit != null)
				return filterExit;
			if (invocation.readyClaim)
				return runReadyClaimRefusal();
			return runReadyView(invocation, location, query);
		}
		if (offset > 0)
			return runModeAwareFailure(invocation.output, "--offset is only supported under --proxied-server");
		if (invocation.readyGated) {
			if (invocation.readyClaim)
				return runModeAwareFailure(invocation.output, "--claim cannot be combined with --gated");
			return runReadyGated(invocation, location, query);
		}
		if (invocation.readyMolecule != "") {
			if (invocation.readyClaim)
				return runModeAwareFailure(invocation.output, "--claim cannot be combined with --mol");
			return runReadyMolecule(invocation, location, query);
		}
		if (invocation.readyExplain) {
			if (invocation.readyClaim)
				return runModeAwareFailure(invocation.output, "--claim cannot be combined with --explain");
			return runReadyExplain(invocation, location, query);
		}
		final deferredExit = runDeferredChecks(invocation);
		if (deferredExit != null)
			return deferredExit;
		if (invocation.readyClaim)
			return runReadyClaimRefusal();
		// Upstream's openRoutedReadStore asks for the user's role before it reads.
		final routedExit = routeListRead(invocation, location, query);
		if (routedExit != null)
			return routedExit;
		return runReadyList(invocation, location, query);
	}

	/**
		`ready --claim` writes, so this build refuses it where upstream claims.
		That is also where upstream's CheckReadonly refuses it under --readonly,
		with this message.
	**/
	function runReadyClaimRefusal():Int {
		return runStoreFailure("operation 'ready --claim' is not allowed in read-only mode");
	}

	/** The proxied route's view, after it gathered its input. */
	function runReadyView(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.readyGated)
			return runReadyGated(invocation, location, query);
		if (invocation.readyMolecule != "")
			return runReadyMolecule(invocation, location, query);
		if (invocation.readyExplain)
			return runReadyExplain(invocation, location, query);
		return runReadyList(invocation, location, query);
	}

	function runReadyList(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch query.issueReady(location.path, location.databaseName, invocation.readyRequest, invocation.global) {
			case ReadyFailure(message): runStoreFailure(message);
			case ReadyRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ReadySuccess(ready): renderReady(invocation, location.proxiedServer, ready, query, location);
		};
	}

	function runReadyGated(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch query.issueReady(location.path, location.databaseName, readyExplainRequest(), invocation.global) {
			case ReadyFailure(message): runStoreFailure(message);
			case ReadyRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ReadySuccess(ready):
				switch query.issueList(location.path, location.databaseName, IssueListRequests.moleculeCandidates(), 0, invocation.global) {
					case ListFailure(message): runStoreFailure(message);
					case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						final molecules = GatedReady.discover(ready.page.items, candidates.items);
						if (invocation.output == Json)
							return writeRenderedJsonStdout(renderGatedReadyJson(molecules, output.usesJsonEnvelope()));
						else
							output.writeStdout(renderGatedReadyHuman(molecules, terminalStyles()));
						0;
				}
		};
	}

	/**
		Upstream runReadyExplain (cmd/bd/ready.go:450-514): the ready set, then
		GetBlockedIssues, whose failure stops the command, DetectCycles, and the
		blockers' records (GetIssuesByIDs); upstream only logs a failure of the last
		two. Its blocked list comes from the stored `is_blocked` flag and its cycles
		from the blocking edges of both dependency tables, which only an embedded
		workspace reads with Haxe-owned SQL. There the blockers' records come from a
		follow-up read of every issue. In a server-mode or proxied workspace, also
		one that keeps an embeddeddolt directory from before, the candidates'
		blocking edges stand in for the blocked list and the cycles.
	**/
	function runReadyExplain(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final ready = switch query.issueReady(location.path, location.databaseName, readyExplainRequest(), invocation.global) {
			case ReadyFailure(message): return runStoreFailure(message);
			case ReadyRowLimitExceeded(found, source, cap): return runListRowLimitExceeded(found, source, cap);
			case ReadySuccess(value): value;
		};
		final explanation = switch query.blockedIssues(location.path, location.databaseName, "", invocation.global) {
			case Failure(message) if (message == BLOCKED_ROUTE_UNAVAILABLE):
				switch query.issueList(location.path, location.databaseName, IssueListRequests.readyExplainCandidates(), 0, invocation.global) {
					case ListFailure(message): return runStoreFailure(message);
					case ListRowLimitExceeded(found, source, cap): return runListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						ReadyExplain.build(ready.page.items, candidates.items, ReadyExplain.blockedFromEdges(candidates.items),
							ReadyExplain.cyclesFromEdges(candidates.items));
				}
			case Failure(message):
				return runModeAwareFailure(invocation.output, message);
			case Success(entries):
				final blocked:Array<BlockedEntry> = [for (entry in entries) {issue: entry.issue, blockedBy: entry.blockedBy}];
				final cycles = switch query.graphCycles(location.path, location.databaseName, invocation.global) {
					case Success(value): value;
					case Failure(_): [];
				};
				final records = switch query.issueList(location.path, location.databaseName, IssueListRequests.everyIssue(), 0, invocation.global) {
					case ListSuccess(page): page.items;
					case ListFailure(_) | ListRowLimitExceeded(_, _, _): [];
				};
				ReadyExplain.build(ready.page.items, records, blocked, cycles);
		};
		if (invocation.output == Json)
			return writeRenderedJsonStdout(renderReadyExplanationJson(explanation, output.usesJsonEnvelope()));
		output.writeStdout(renderReadyExplanationHuman(explanation, terminalStyles()));
		return 0;
	}

	static function readyExplainRequest():beadshx.store.ReadyRequest {
		return {
			issueType: "",
			assignee: "",
			unassigned: false,
			labels: [],
			labelsAny: [],
			excludeLabels: [],
			labelPattern: "",
			labelRegex: "",
			priority: IntAbsent,
			parentId: "",
			moleculeType: "",
			includeDeferred: false,
			includeEphemeral: false,
			excludeTypes: [],
			metadataFields: [],
			hasMetadataKey: "",
			sort: beadshx.store.ReadySort.Priority,
			limit: IntPresent(0),
			offset: IntAbsent,
			brief: false,
			maxRows: IntAbsent,
			maxRowsSource: ""
		};
	}

	function runReadyMolecule(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch lookupIssueSummary(location, invocation.readyMolecule, invocation.global, query) {
			case Failure(_): runModeAwareFailure(invocation.output, 'molecule \'${invocation.readyMolecule}\' not found');
			case Success(IssueMissing): runModeAwareFailure(invocation.output, 'molecule \'${invocation.readyMolecule}\' not found');
			case Success(IssueFound(root)):
				switch loadMoleculeItems(location, root.id, query, invocation.global) {
					case ListFailure(message): runStoreFailure('loading molecule: ${message}');
					case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
					case ListSuccess(page):
						final steps = new Array<MoleculeStep>();
						final dependencies = new Array<MoleculeDependency>();
						for (item in page.items) {
							steps.push({
								id: item.id,
								title: item.title,
								status: item.status,
								priority: item.priority,
								issueType: item.issueType
							});
							for (dependency in item.dependencies)
								dependencies.push({
									issueId: dependency.issueId,
									dependsOnId: dependency.dependsOnId,
									dependencyType: dependency.dependencyType,
									metadata: dependency.metadata
								});
						}
						final analysis = MoleculeReady.analyze(root.id, steps, dependencies);
						if (invocation.output == Json) {
							writeRenderedJsonStdout(renderMoleculeReadyJson(root.title, page.items, analysis, output.usesJsonEnvelope()));
						} else {
							output.writeStdout(renderMoleculeReadyHuman(root.title, page.items, analysis, terminalStyles()));
							0;
						}
				}
		};
	}

	/** The root and the issues of ready --mol, both follow-up reads after the root's lookup. */
	function loadMoleculeItems(location:WorkspaceLocation, rootId:String, query:IssueQueryPort, global:Bool):IssueListResult {
		return switch query.issueList(location.path, location.databaseName, IssueListRequests.exact(rootId), 0, global) {
			case ListFailure(message): ListFailure(message);
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(rootPage):
				if (rootPage.items.length == 0) {
					ListFailure('template ${rootId} not found');
				} else switch query.issueList(location.path, location.databaseName, IssueListRequests.moleculeCandidates(), 0, global) {
					case ListFailure(message): ListFailure(message);
					case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						final byId = new Map<String, IssueListItem>();
						byId.set(rootId, rootPage.items[0]);
						final nodes = [];
						for (item in candidates.items) {
							byId.set(item.id, item);
							final parents = [
								for (dependency in item.dependencies)
									if (dependency.dependencyType == "parent-child") dependency.dependsOnId
							];
							nodes.push({id: item.id, parents: parents});
						}
						final items = [
							for (id in MoleculeSubgraph.collectIds(rootId, nodes))
								if (byId.exists(id)) byId.get(id)
						];
						ListSuccess({items: items, hasMore: false, formatted: ""});
				}
		};
	}

	function runSearch(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runSearchBody(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Upstream search's command body, after its pre-run opened the store. It
		asks for the query first. The direct route then checks --status, which
		reads the custom statuses, before the date, priority and metadata
		checks. The proxied route makes those checks first, and prints them as
		a JSON error under --json.
	**/
	function runSearchBody(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.searchQuery == "") {
			output.writeStdout(searchHelp());
			return location.proxiedServer ? runModeAwareFailure(invocation.output, "search query is required") : runStoreFailure("search query is required");
		}
		switch invocation.deferredCheck {
			case ChecksPassed:
			case PlainCheckFailure(message) if (location.proxiedServer):
				return runModeAwareFailure(invocation.output, message);
			case PlainCheckFailure(_) | OutputCheckFailure(_) | ExactCheckFailure(_, _):
				// The native search checks --status, so this build searches to find a bad status first.
				if (invocation.listRequest.status != "")
					switch query.issueSearch(location.path, location.databaseName, invocation.searchQuery, invocation.listRequest, invocation.global) {
						case ListFailure(message): return runStoreFailure(message);
						case ListRowLimitExceeded(_, _, _) | ListSuccess(_):
					}
				final checkExit = reportDeferredCheck(invocation, invocation.deferredCheck);
				if (checkExit != null)
					return checkExit;
		}
		return switch query.issueSearch(location.path, location.databaseName, invocation.searchQuery, invocation.listRequest, invocation.global) {
			case ListFailure(message): runStoreFailure(message);
			case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page): renderSearch(invocation, page);
		};
	}

	function runQuery(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query): closeIssueQuery(query, runQueryBody(invocation, location, query));
						}
				}
		};
	}

	/** Checks the arguments as upstream's command body does, after its pre-run opened the store, then queries. */
	function runQueryBody(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (!invocation.queryRequest.provided) {
			output.writeStderr("Error: query expression is required\n\n");
			// Cobra's Help writes to stdout.
			output.writeStdout(queryHelp());
			return 1;
		}
		final deferredExit = runDeferredChecks(invocation);
		if (deferredExit != null)
			return deferredExit;
		if (invocation.queryRequest.parseOnly)
			return switch QuerySyntax.parse(invocation.queryRequest.expression) {
				case Parsed(expression):
					output.writeStdout('Parsed query: ${QuerySyntax.render(expression)}\n');
					0;
				case Invalid(message): runModeAwareFailure(invocation.output, 'invalid query expression: ${message}');
			};
		if (!location.proxiedServer && invocation.queryRequest.offset > 0)
			return runModeAwareFailure(invocation.output, "--offset is only supported under --proxied-server");
		return executeQuery(invocation, location, query);
	}

	function executeQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch QuerySyntax.parse(invocation.queryRequest.expression) {
			case Invalid(message): runModeAwareFailure(invocation.output, 'invalid query expression: ${message}');
			case Parsed(expression):
				switch QueryPlanner.plan(expression, invocation.queryRequest, query) {
					case PlanInvalid(message): runModeAwareFailure(invocation.output, message);
					case Planned(plan): executeQueryPlan(invocation, location, query, plan);
				}
		};
	}

	function executeQueryPlan(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort, plan:QueryExecutionPlan):Int {
		final storageRequest:QueryStorageRequest = switch plan {
			case ExactQuery(filter, page):
				{filter: filter, fetch: OrderedPage(page.limit, page.offset, page.sortBy, page.reverse)};
			case PredicateQuery(filter, _, _): {filter: filter, fetch: CompleteCandidates};
		};
		return switch query.issueQuery(location.path, location.databaseName, storageRequest, invocation.global) {
			case QueryRowsFailure(message): runStoreFailure(message);
			case QueryRows(source):
				switch finishQueryPage(plan, source) {
					case Failure(message): runStoreFailure(message);
					case Success(page): renderQuery(invocation, page.rows, page.hasMore);
				}
		};
	}

	static function finishQueryPage(plan:QueryExecutionPlan, source:beadshx.store.QueryStorageRequest.QueryRowPage):StoreResult<QueryPageResult> {
		return switch plan {
			case ExactQuery(_, _): Success(QueryPage.exactPage(source.rows, source.sourceHasMore));
			case PredicateQuery(_, compiledPredicate, policy):
				if (!source.complete) Failure("native query source returned an incomplete candidate set"); else Success(QueryPage.predicatePage(source.rows,
					compiledPredicate, policy));
		};
	}

	function renderQuery(invocation:Invocation, rows:Array<beadshx.store.IssueQueryRow>, hasMore:Bool):Int {
		final items = [for (row in rows) row.item];
		if (invocation.output == Json) {
			final status = writeRenderedJsonStdout(renderListJsonArray({items: items, hasMore: hasMore, formatted: ""}, false, false));
			if (status != 0)
				return status;
		} else if (items.length == 0) {
			output.writeStdout('No issues found matching query: ${invocation.queryRequest.expression}\n');
		} else if (invocation.queryRequest.longFormat) {
			final rendered = new StringBuf();
			rendered.add('\nFound ${items.length} issues:\n\n');
			for (issue in items) {
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n');
				rendered.add('  ${issue.title}\n');
				if (issue.assignee != "")
					rendered.add('  Assignee: ${issue.assignee}\n');
				if (issue.labels.length > 0)
					rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
				rendered.add("\n");
			}
			output.writeStdout(rendered.toString());
		} else {
			final rendered = new StringBuf();
			final styles = terminalStyles();
			rendered.add('Found ${items.length} issues:\n');
			for (issue in items)
				rendered.add(renderCompactIssue(issue, styles.renderStatusIcon(issue.status), "", "", styles));
			output.writeStdout(rendered.toString());
		}
		writeTruncationHint(hasMore, invocation.queryRequest.limit);
		return 0;
	}

	/**
		Upstream printTruncationHint of `list` and `query` (cmd/bd/list_output.go:17-23):
		on a terminal stderr, says in the warning style that `limit` hid more issues.
	**/
	function writeTruncationHint(hasMore:Bool, limit:Int):Void {
		if (hasMore && limit > 0 && output.isStderrTerminal())
			output.writeStderr(terminalStyles()
				.renderWarn('\nShowing ${limit} issues; more results matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.\n'));
	}

	/**
		Upstream internal/ui's styles for this process: colored, from the palette
		for the terminal's background, when `colors` is on, and empty otherwise.

		Why: upstream asks the terminal for its background once, at start, and
		only when colors are on. What: the styles, built once. How: they use the
		answer that `run` got at start (`darkBackground`), so building them never
		asks the terminal again.
	**/
	function terminalStyles():TerminalStyles {
		final existing = builtStyles;
		if (existing != null)
			return existing;
		final built = colors ? TerminalStyles.colored(darkBackground, output.textStyle) : TerminalStyles.plain(output.textStyle);
		builtStyles = built;
		return built;
	}

	function renderSearch(invocation:Invocation, page:IssueListPage):Int {
		if (invocation.output == Json) {
			return writeRenderedJsonStdout(renderListJsonArray(page, false, false, false));
		}
		if (page.items.length == 0) {
			output.writeStdout('No issues found matching \'${invocation.searchQuery}\'\n');
			return 0;
		}
		final rendered = new StringBuf();
		if (invocation.listLong) {
			rendered.add('\nFound ${page.items.length} issues matching \'${invocation.searchQuery}\':\n\n');
			for (issue in page.items) {
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n');
				rendered.add('  ${issue.title}\n');
				if (issue.assignee != "")
					rendered.add('  Assignee: ${issue.assignee}\n');
				if (issue.labels.length > 0)
					rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
				rendered.add("\n");
			}
		} else {
			rendered.add('Found ${page.items.length} issues matching \'${invocation.searchQuery}\':\n');
			for (issue in page.items) {
				final assignee = issue.assignee == "" ? "" : ' @${issue.assignee}';
				final labels = issue.labels.length == 0 ? "" : ' [${issue.labels.join(" ")}]';
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}${assignee}${labels} - ${issue.title}\n');
			}
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	function runStale(invocation:Invocation):Int {
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) runWorkspaceDatabaseNotFound(location); else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								// Upstream checks --days and --status in the command body, after its pre-run opened the store.
								final result = if (invocation.staleRequest.days < 1) {
									runModeAwareFailure(invocation.output, "--days must be at least 1");
								} else if (!validStaleStatus(invocation.staleRequest.status)) {
									runModeAwareFailure(invocation.output,
										'invalid status \'${invocation.staleRequest.status}\'. Valid values: open, in_progress, blocked, deferred');
								} else switch query.issueStale(location.path, location.databaseName, invocation.staleRequest, invocation.global) {
									case Failure(message): runStoreFailure(message);
									case Success(issues): renderStale(invocation, issues);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	static function validStaleStatus(status:String):Bool {
		return status == "" || status == "open" || status == "in_progress" || status == "blocked" || status == "deferred";
	}

	function renderStale(invocation:Invocation, issues:Array<StaleIssue>):Int {
		if (invocation.output == Json) {
			return writeRenderedJsonStdout(renderRawIssuesJson(issues));
		}
		// Upstream displayStaleIssues (cmd/bd/stale.go:70-85).
		final styles = terminalStyles();
		if (issues.length == 0) {
			output.writeStdout('\n${styles.renderPass("✨")} No stale issues found (all active)\n\n');
			return 0;
		}
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderWarn("⏰")} Stale issues (${issues.length} not updated in ${invocation.staleRequest.days}+ days):\n\n');
		final now = Date.now().getTime();
		for (index in 0...issues.length) {
			final issue = issues[index];
			// Upstream's int(now.Sub(issue.UpdatedAt).Hours() / 24), in milliseconds.
			final updated = rfc3339Millis(issue.updatedAt);
			final daysStale = updated == null ? 0 : Std.int((now - updated) / 86400000.0);
			rendered.add('${index + 1}. [${styles.renderPriority(issue.priority)}] ${styles.renderId(issue.id)}: ${issue.title}\n');
			rendered.add('   Status: ${styles.renderStatus(issue.status)}, Last updated: ${daysStale} days ago\n');
			if (issue.assignee != "")
				rendered.add('   Assignee: ${issue.assignee}\n');
			rendered.add("\n");
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	function runOrphans(invocation:Invocation):Int {
		if (invocation.orphansFix)
			return runModeAwareFailure(invocation.output, "operation 'orphans --fix' is not allowed in read-only mode");
		return switch discoverStoreWorkspace(invocation) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFoundWithoutWorkspace(invocation);
			case Found(location):
				switch validateStoreSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!findsDatabase(invocation, location)) {
							runWorkspaceDatabaseNotFound(location);
						} else switch openIssueQuery(invocation, location) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.issueOrphanCandidates(location.path, invocation.listRequest, invocation.global) {
									case Failure(message): runModeAwareFailure(invocation.output, 'unable to find orphaned issues: ${message}');
									case Success(scan): loadAndRenderOrphans(invocation, location, scan);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	/**
		Finds the candidates that a commit message names. The prefix is upstream
		doltStoreProvider.GetIssuePrefix: the layered `issue-prefix` setting
		(BD_ISSUE_PREFIX sets it, the `issue_prefix` spelling does not), then the
		stored issue_prefix that the scan read in the same session, then `bd`.
	**/
	function loadAndRenderOrphans(invocation:Invocation, location:WorkspaceLocation, scan:OrphanCandidateScan):Int {
		if (scan.candidates.length == 0)
			return renderOrphans(invocation, []);
		final gitDirectory = invocation.directory == "" ? "." : invocation.directory;
		return switch gitHistory.log(gitDirectory) {
			case Failure(message): runModeAwareFailure(invocation.output, 'unable to find orphaned issues: ${message}');
			case Success(log):
				final configuredPrefix = LayeredConfig.forWorkspace(location.path).getString("issue-prefix");
				final storedPrefix = scan.prefix == "" ? "bd" : scan.prefix;
				final prefix = configuredPrefix == "" ? storedPrefix : configuredPrefix;
				renderOrphans(invocation, findOrphanedIssues(scan.candidates, prefix, log));
		};
	}

	static function findOrphanedIssues(candidates:Array<OrphanCandidate>, prefix:String, log:String):Array<OrphanIssue> {
		final candidatesById = new StringMap<OrphanCandidate>();
		for (candidate in candidates)
			candidatesById.set(candidate.id, candidate);
		final recorded = new StringMap<Bool>();
		final issues = new Array<OrphanIssue>();
		final reference = new EReg('\\(${EReg.escape(prefix)}-[a-z0-9.]+\\)', "");
		for (line in log.split("\n")) {
			if (line == "")
				continue;
			final separator = line.indexOf(" ");
			if (separator < 0)
				continue;
			final commit = line.substr(0, separator);
			final message = line.substr(separator + 1);
			var offset = 0;
			while (offset < line.length && reference.matchSub(line, offset)) {
				final position = reference.matchedPos();
				final matched = reference.matched(0);
				final issueId = matched.substr(1, matched.length - 2);
				final candidate = candidatesById.get(issueId);
				if (candidate != null && !recorded.exists(issueId)) {
					recorded.set(issueId, true);
					issues.push({
						id: candidate.id,
						title: candidate.title,
						status: candidate.status,
						latestCommit: commit,
						latestCommitMessage: message
					});
				}
				offset = position.pos + position.len;
			}
		}
		return issues;
	}

	function renderOrphans(invocation:Invocation, issues:Array<OrphanIssue>):Int {
		if (invocation.output == Json) {
			writeJsonStdout(renderOrphansJson(issues));
			return 0;
		}
		// Upstream's orphans view (cmd/bd/orphans.go:80-95).
		final styles = terminalStyles();
		if (issues.length == 0) {
			output.writeStdout('${styles.renderPass("✓")} No orphaned issues found\n');
			return 0;
		}
		issues.sort((left, right) -> left.id < right.id ? -1 : left.id == right.id ? 0 : 1);
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderWarn("⚠")} Found ${issues.length} orphaned issue(s):\n\n');
		for (index in 0...issues.length) {
			final issue = issues[index];
			rendered.add('${index + 1}. ${styles.renderId(issue.id)}: ${issue.title}\n');
			rendered.add('   Status: ${issue.status}\n');
			if (invocation.orphansDetails)
				rendered.add('   Latest commit: ${issue.latestCommit} - ${issue.latestCommitMessage}\n');
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	static function renderOrphansJson(issues:Array<OrphanIssue>):String {
		if (issues.length == 0)
			return "null\n";
		final lines = ["["];
		for (index in 0...issues.length) {
			final issue = issues[index];
			lines.push("  {");
			lines.push('    "issue_id": ${Json.stringify(issue.id)},');
			lines.push('    "title": ${Json.stringify(issue.title)},');
			lines.push('    "status": ${Json.stringify(issue.status)},');
			lines.push('    "latest_commit": ${Json.stringify(issue.latestCommit)},');
			lines.push('    "latest_commit_message": ${Json.stringify(issue.latestCommitMessage)}');
			lines.push(index == issues.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	/** Upstream runMoleculeReady's text view (cmd/bd/ready.go:621-675). */
	static function renderMoleculeReadyHuman(title:String, items:Array<IssueListItem>, analysis:MoleculeReadyAnalysis, styles:TerminalStyles):String {
		final byId = new Map<String, IssueListItem>();
		for (item in items)
			byId.set(item.id, item);
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderAccent("🧪")} Ready steps in molecule: ${title}\n');
		rendered.add('   ID: ${analysis.moleculeId}\n');
		rendered.add('   Total: ${analysis.totalSteps} steps, ${analysis.readySteps} ready\n');
		if (analysis.readySteps == 0) {
			rendered.add('\n${styles.renderWarn("✨")} No ready steps (all blocked or completed)\n\n');
			return rendered.toString();
		}
		if (analysis.groups.length > 0) {
			rendered.add('\n${styles.renderPass("⚡")} Parallel Groups:\n');
			for (group in analysis.groups) {
				var ready = 0;
				for (id in group.members) {
					final info = findMoleculeInfo(analysis.steps, id);
					if (info != null && info.isReady)
						ready++;
				}
				if (ready > 0)
					rendered.add('   ${group.name}: ${ready} ready\n');
			}
		}
		rendered.add('\n${styles.renderPass("📋")} Ready steps:\n\n');
		var index = 0;
		for (info in analysis.steps) {
			if (!info.isReady)
				continue;
			final issue = byId.get(info.stepId);
			if (issue == null)
				continue;
			index++;
			final group = info.parallelGroup == "" ? "" : ' [${styles.renderAccent(info.parallelGroup)}]';
			rendered.add('${index}. [${styles.renderPriority(issue.priority)}] [${styles.renderType(issue.issueType)}] ${styles.renderId(issue.id)}: ${issue.title}${group}\n');
			final readyParallel = new Array<String>();
			for (id in info.canParallel) {
				final parallel = findMoleculeInfo(analysis.steps, id);
				if (parallel != null && parallel.isReady)
					readyParallel.push(id);
			}
			if (readyParallel.length > 0)
				rendered.add('   Can run with: [${readyParallel.join(" ")}]\n');
		}
		rendered.add("\n");
		return rendered.toString();
	}

	/**
		Upstream ready --mol JSON: `MoleculeReadyOutput` (cmd/bd/ready.go:679-693), whose
		steps hold each ready step's whole `types.Issue` and its `ParallelInfo`
		(cmd/bd/mol_show.go:154-162). Upstream leaves `can_parallel` nil for a step
		in no parallel group. Without the envelope, upstream round-trips the
		output through a map, which sorts every key (cmd/bd/output.go:68-99).
	**/
	static function renderMoleculeReadyJson(title:String, items:Array<IssueListItem>, analysis:MoleculeReadyAnalysis, envelope:Bool):StoreResult<String> {
		final sorted = !envelope;
		final byId = new Map<String, IssueListItem>();
		for (item in items)
			byId.set(item.id, item);
		final steps = new Array<String>();
		for (info in analysis.steps) {
			if (!info.isReady)
				continue;
			final issue = byId.get(info.stepId);
			if (issue == null)
				continue;
			final issueFields = switch renderIssueFields(issue, sorted, "        ", issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final blockedBy = renderJsonArray(jsonStrings(info.blockedBy), "        ");
			final blocks = renderJsonArray(jsonStrings(info.blocks), "        ");
			final canParallel = renderJsonStrings(info.canParallel, "        ");
			final parallelInfo = [
				'"step_id": ${Json.stringify(info.stepId)}',
				'"status": ${Json.stringify(info.status)}',
				'"is_ready": ${info.isReady}',
				'"parallel_group": ${Json.stringify(info.parallelGroup)}',
				'"blocked_by": ${blockedBy}',
				'"blocks": ${blocks}',
				'"can_parallel": ${canParallel}'
			];
			final renderedIssue = renderJsonMembers(issueFields, sorted, "      ");
			final renderedInfo = renderJsonMembers(parallelInfo, sorted, "      ");
			final step = ['"issue": ${renderedIssue}', '"parallel_info": ${renderedInfo}'];
			if (info.parallelGroup != "")
				step.push('"parallel_group": ${Json.stringify(info.parallelGroup)}');
			steps.push(renderJsonMembers(step, sorted, "    "));
		}
		// Go prints the keys of a map in byte order in both modes.
		final groups = new Array<String>();
		for (group in analysis.groups) {
			final members = renderJsonArray(jsonStrings(group.members), "    ");
			groups.push('${Json.stringify(group.name)}: ${members}');
		}
		// readySteps stays a nil slice when no step is ready.
		final renderedSteps = steps.length == 0 ? "null" : renderJsonArray(steps, "  ");
		final renderedGroups = renderJsonMembers(groups, true, "  ");
		final document = [
			'"molecule_id": ${Json.stringify(analysis.moleculeId)}',
			'"molecule_title": ${Json.stringify(title)}',
			'"total_steps": ${analysis.totalSteps}',
			'"ready_steps": ${analysis.readySteps}',
			'"steps": ${renderedSteps}',
			'"parallel_groups": ${renderedGroups}',
			'"schema_version": 1'
		];
		return Success(renderJsonMembers(document, sorted, "") + "\n");
	}

	/** Upstream's ready --explain view (cmd/bd/ready.go:517-573; proxied, ready_proxied_server.go:357-399). */
	static function renderReadyExplanationHuman(explanation:ReadyExplanation, styles:TerminalStyles):String {
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderAccent("📊")} Ready Work Explanation\n\n');
		if (explanation.ready.length == 0) {
			rendered.add('${styles.renderWarn("○")} No ready work\n\n');
		} else {
			rendered.add('${styles.renderPass("●")} Ready (${explanation.ready.length} issues):\n\n');
			for (item in explanation.ready) {
				rendered.add('  ${styles.renderId(item.issue.id)} [${styles.renderPriority(item.issue.priority)}] ${item.issue.title}\n');
				rendered.add('    Reason: ${item.reason}\n');
				if (item.resolvedBlockers != null && item.resolvedBlockers.length > 0)
					rendered.add('    Resolved blockers: ${item.resolvedBlockers.join(", ")}\n');
				if (item.dependentCount > 0)
					rendered.add('    Unblocks: ${item.dependentCount} issue(s)\n');
				rendered.add("\n");
			}
		}
		if (explanation.blocked.length > 0) {
			rendered.add('${styles.renderFail("●")} Blocked (${explanation.blocked.length} issues):\n\n');
			for (item in explanation.blocked) {
				rendered.add('  ${styles.renderId(item.issue.id)} [${styles.renderPriority(item.issue.priority)}] ${item.issue.title}\n');
				for (blocker in item.blockedBy)
					rendered.add('    ← blocked by ${styles.renderId(blocker.id)}: ${blocker.title} [${blocker.status}]\n');
				rendered.add("\n");
			}
		}
		if (explanation.cycles.length > 0) {
			rendered.add('${styles.renderFail("⚠")} Cycles detected (${explanation.cycles.length}):\n\n');
			for (cycle in explanation.cycles)
				rendered.add('  ${cycle.join(" → ")} → ${cycle[0]}\n');
			rendered.add("\n");
		}
		rendered.add('${styles.renderMuted("─")} Summary: ${explanation.ready.length} ready, ${explanation.blocked.length} blocked');
		if (explanation.cycles.length > 0)
			rendered.add(', ${explanation.cycles.length} cycle(s)');
		rendered.add("\n\n");
		return rendered.toString();
	}

	/**
		Upstream's ready --gated view (cmd/bd/mol_ready_gated.go:98-118). Its
		marks render an empty text in the warning or accent style, which prints
		the style's escape sequences around nothing when colors are on.
	**/
	static function renderGatedReadyHuman(molecules:Array<GatedMolecule>, styles:TerminalStyles):String {
		if (molecules.length == 0)
			return '\n${styles.renderWarn("")} No molecules ready for gate-resume dispatch\n\n';
		final rendered = new StringBuf();
		rendered.add('\n${styles.renderAccent("")} Molecules ready for gate-resume dispatch (${molecules.length}):\n\n');
		for (index in 0...molecules.length) {
			final molecule = molecules[index];
			rendered.add('${index + 1}. ${styles.renderId(molecule.moleculeId)}: ${molecule.moleculeTitle}\n');
			rendered.add('   Gate closed: ${molecule.closedGate.id} (${molecule.closedGate.longFields.awaitType})\n');
			rendered.add('   Ready step: ${molecule.readyStep.id} - ${molecule.readyStep.title}\n\n');
		}
		rendered.add("To dispatch a molecule:\n");
		rendered.add("  bd sling <agent> --mol <molecule-id>\n");
		return rendered.toString();
	}

	/**
		Upstream ready --gated JSON: `GatedReadyOutput` (cmd/bd/mol_ready_gated.go:15-26),
		with each molecule's closed gate and ready step as a whole `types.Issue`.
		Without the envelope, upstream round-trips it through a map, which sorts
		every key (cmd/bd/output.go:68-99).
	**/
	static function renderGatedReadyJson(molecules:Array<GatedMolecule>, envelope:Bool):StoreResult<String> {
		final sorted = !envelope;
		final rendered = new Array<String>();
		for (molecule in molecules) {
			final closedGate = switch renderIssueFields(molecule.closedGate, sorted, "        ", molecule.closedGate.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final readyStep = switch renderIssueFields(molecule.readyStep, sorted, "        ", molecule.readyStep.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final renderedGate = renderJsonMembers(closedGate, sorted, "      ");
			final renderedStep = renderJsonMembers(readyStep, sorted, "      ");
			rendered.push(renderJsonMembers([
				'"molecule_id": ${Json.stringify(molecule.moleculeId)}',
				'"molecule_title": ${Json.stringify(molecule.moleculeTitle)}',
				'"closed_gate": ${renderedGate}',
				'"ready_step": ${renderedStep}'
			], sorted, "    "));
		}
		final renderedMolecules = renderJsonArray(rendered, "  ");
		final document = [
			'"molecules": ${renderedMolecules}',
			'"count": ${molecules.length}',
			'"schema_version": 1'
		];
		return Success(renderJsonMembers(document, sorted, "") + "\n");
	}

	/**
		Upstream ready --explain JSON: `types.ReadyExplanation` (internal/types/types.go:1677-1714).
		Each ready and blocked item is its whole `types.Issue` and the item's own
		fields. Without the envelope, upstream round-trips the explanation
		through a map, which sorts every key (cmd/bd/output.go:68-99).
	**/
	static function renderReadyExplanationJson(explanation:ReadyExplanation, envelope:Bool):StoreResult<String> {
		final sorted = !envelope;
		final ready = new Array<String>();
		for (item in explanation.ready) {
			final fields = switch renderIssueFields(item.issue, sorted, "      ", item.issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"reason": ${Json.stringify(item.reason)}');
			final resolvedBlockers = item.resolvedBlockers;
			final resolved = resolvedBlockers == null ? "null" : renderJsonArray(jsonStrings(resolvedBlockers), "      ");
			fields.push('"resolved_blockers": ${resolved}');
			fields.push('"dependency_count": ${item.dependencyCount}');
			fields.push('"dependent_count": ${item.dependentCount}');
			if (item.parent != null)
				fields.push('"parent": ${Json.stringify(item.parent)}');
			ready.push(renderJsonMembers(fields, sorted, "    "));
		}
		final blocked = new Array<String>();
		for (item in explanation.blocked) {
			final fields = switch renderIssueFields(item.issue, sorted, "      ", item.issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			final blockers = [
				for (blocker in item.blockedBy)
					renderJsonMembers([
						'"id": ${Json.stringify(blocker.id)}',
						'"title": ${Json.stringify(blocker.title)}',
						'"status": ${Json.stringify(blocker.status)}',
						'"priority": ${blocker.priority}'
					], sorted, "        ")
			];
			final renderedBlockers = renderJsonArray(blockers, "      ");
			fields.push('"blocked_by": ${renderedBlockers}');
			fields.push('"blocked_by_count": ${item.blockedByCount}');
			blocked.push(renderJsonMembers(fields, sorted, "    "));
		}
		final renderedReady = renderJsonArray(ready, "  ");
		final renderedBlocked = renderJsonArray(blocked, "  ");
		final document = ['"ready": ${renderedReady}', '"blocked": ${renderedBlocked}'];
		if (explanation.cycles.length > 0) {
			final cycles = renderJsonArray([for (cycle in explanation.cycles) renderJsonArray(jsonStrings(cycle), "    ")], "  ");
			document.push('"cycles": ${cycles}');
		}
		final summary = renderJsonMembers([
			'"total_ready": ${explanation.ready.length}',
			'"total_blocked": ${explanation.blocked.length}',
			'"cycle_count": ${explanation.cycles.length}'
		], sorted, "  ");
		document.push('"summary": ${summary}');
		document.push('"schema_version": 1');
		return Success(renderJsonMembers(document, sorted, "") + "\n");
	}

	static function findMoleculeInfo(infos:Array<MoleculeParallelInfo>, id:String):Null<MoleculeParallelInfo> {
		for (info in infos)
			if (info.stepId == id)
				return info;
		return null;
	}

	function renderReady(invocation:Invocation, proxied:Bool, result:ReadyResult, query:IssueQueryPort, location:WorkspaceLocation):Int {
		if (invocation.output == Json) {
			final legacy = switch renderListJsonArray(result.page, false, false) {
				case Failure(message): return runStoreFailure('encoding JSON: $message');
				case Success(value): value;
			};
			if (result.truncated && output.usesJsonEnvelope()) {
				output.writeStdout(renderReadyEnvelope(legacy, result));
			} else {
				writeJsonStdout(legacy);
			}
			if (result.truncated) {
				if (proxied) {
					output.writeStderr('Showing ${result.page.items.length} ready issues; more matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.\n');
				} else
					switch result.total {
						case TotalKnown(total):
							output.writeStderr('Showing ${result.page.items.length} of ${total.wireValue()} ready issues. Use --limit 0 for all, or --limit N to raise the cap.\n');
						case TotalUnknown:
					}
			}
			return 0;
		}

		// Upstream's ready body (cmd/bd/ready.go:239-279) and its proxied twin style these as below.
		final styles = terminalStyles();
		if (result.page.items.length == 0) {
			output.writeStdout(result.hasOpenIssues ? '\n${styles.renderWarn("✨")} No ready work found (all issues have blocking dependencies)\n\n' : '\n${styles.renderPass("✨")} No open issues\n\n');
			return 0;
		}
		if (invocation.readyPlain || !invocation.readyPretty) {
			output.writeStdout(renderReadyPlain(result.page, styles));
		} else {
			output.writeStdout(renderReadyPretty(result.page, query, location, invocation.global, styles));
		}
		if (result.truncated) {
			if (proxied) {
				output.writeStdout(styles.renderMuted('Showing ${result.page.items.length} ready issues; more matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.')
					+ "\n\n");
			} else
				switch result.total {
					case TotalKnown(total):
						output.writeStdout(styles.renderMuted('Showing ${result.page.items.length} of ${total.wireValue()} ready issues. Use -n to show more.')
							+ "\n\n");
					case TotalUnknown:
				}
		}
		return 0;
	}

	static function renderReadyEnvelope(legacy:String, result:ReadyResult):String {
		var data = StringTools.endsWith(legacy, "\n") ? legacy.substr(0, legacy.length - 1) : legacy;
		data = StringTools.replace(data, "\n", "\n  ");
		final lines = [
			"{",
			'  "data": ${data},',
			'  "pagination": {',
			'    "returned": ${result.page.items.length},'
		];
		switch result.total {
			case TotalKnown(total):
				lines.push('    "total": ${total.wireValue()},');
			case TotalUnknown:
		}
		lines.push('    "truncated": true');
		lines.push("  },");
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderReadyPlain(page:IssueListPage, styles:TerminalStyles):String {
		var rendered = '\n${styles.renderAccent("📋")} Ready work (${page.items.length} issues with no active blockers):\n\n';
		for (index in 0...page.items.length) {
			final issue = page.items[index];
			rendered += '${index + 1}. [${styles.renderPriority(issue.priority)}] [${styles.renderType(issue.issueType)}] ${styles.renderId(issue.id)}: ${issue.title}\n';
			switch issue.estimatedMinutes {
				case IntegerPresent(value):
					rendered += '   Estimate: ${value} min\n';
				case IntegerAbsent:
			}
			if (issue.assignee != "")
				rendered += '   Assignee: ${issue.assignee}\n';
		}
		return rendered + "\n";
	}

	/**
		Upstream displayReadyList (cmd/bd/ready.go:416-433): each issue as
		formatPrettyIssueWithContext prints it, with its parent epic's title in
		the muted style, then the footer.

		Upstream buildParentEpicMap (cmd/bd/ready.go:362-413) reads each parent
		with GetIssue and skips one that it cannot read. The issue summary is that
		read: Haxe-owned SQL in an embedded workspace, so it opens no second store.
	**/
	function renderReadyPretty(page:IssueListPage, query:IssueQueryPort, location:WorkspaceLocation, global:Bool, styles:TerminalStyles):String {
		final parentTitles = new Map<String, String>();
		for (issue in page.items) {
			if (issue.parent == "" || parentTitles.exists(issue.parent))
				continue;
			var title = "";
			switch query.issueSummary(location.path, location.databaseName, issue.parent, global) {
				case Success(IssueFound({issueType: Epic, title: epicTitle})):
					title = epicTitle;
				case Failure(_) | Success(IssueMissing) | Success(IssueFound(_)):
			}
			parentTitles.set(issue.parent, title);
		}
		var rendered = "";
		for (issue in page.items) {
			var line = renderPrettyIssue(issue, styles);
			final parentTitle = issue.parent == "" ? null : parentTitles.get(issue.parent);
			if (parentTitle != null && parentTitle != "")
				line += " " + styles.renderMuted('← ${parentTitle}');
			rendered += line + "\n";
		}
		rendered += "\n" + StringTools.rpad("", "-", 80) + "\n";
		rendered += 'Ready: ${page.items.length} issues with no active blockers\n\n';
		rendered += "Status: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n";
		rendered += "Priority: P0–P4 (label only; not a status icon)\n";
		return rendered;
	}

	/**
		Upstream executeCount (cmd/bd/count.go:175-225). Without a --by-* flag it
		prints the count; with one, the total and the sorted buckets, also when
		no bucket is left: `Total: 0` and an empty line, or an empty `groups`
		list in JSON.
	**/
	function renderCount(invocation:Invocation, result:CountResult):Int {
		final grouped = switch invocation.countGroup {
			case Ungrouped: false;
			case ByStatus | ByPriority | ByType | ByAssignee | ByLabel: true;
		};
		switch invocation.output {
			case Human:
				if (!grouped) {
					output.writeStdout(result.total.wireValue() + "\n");
				} else {
					var rendered = 'Total: ${result.total.wireValue()}\n\n';
					for (group in result.groups)
						rendered += '${group.group}: ${group.count.wireValue()}\n';
					output.writeStdout(rendered);
				}
			case Json:
				if (!grouped) {
					writeJsonStdout('{\n  "count": ${result.total.wireValue()},\n  "schema_version": 1\n}\n');
				} else if (result.groups.length == 0) {
					writeJsonStdout('{\n  "groups": [],\n  "schema_version": 1,\n  "total": ${result.total.wireValue()}\n}\n');
				} else {
					final lines = ["{", '  "groups": ['];
					for (index in 0...result.groups.length) {
						final group = result.groups[index];
						final suffix = index + 1 == result.groups.length ? "" : ",";
						lines.push("    {");
						lines.push('      "count": ${group.count.wireValue()},');
						lines.push('      "group": ${Json.stringify(group.group)}');
						lines.push('    }${suffix}');
					}
					lines.push("  ],");
					lines.push('  "schema_version": 1,');
					lines.push('  "total": ${result.total.wireValue()}');
					lines.push("}");
					writeJsonStdout(lines.join("\n") + "\n");
				}
		}
		return 0;
	}

	/**
		Chooses between upstream's recursive tree walk and its one-page parent filter.

		Only the tree view (`--tree`, `--pretty`, `--deps` or `--watch`) walks every level
		below `--parent`. `--flat`, `--json` and `--format` read one page of direct children.
		Each `--watch` refresh reads again; an embedded workspace reads with Haxe-owned SQL,
		whose session checks the schema only at the command's first read.
	**/
	function loadListResult(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):IssueListResult {
		return isListHierarchy(invocation) ? loadIssueHierarchy(invocation, location, effectiveLimit,
			query) : query.issueList(location.path, location.databaseName, invocation.listRequest, effectiveLimit, invocation.global);
	}

	/** True for the `--parent` tree view; its empty result prints "Issue 'X' has no children". */
	static function isListHierarchy(invocation:Invocation):Bool {
		return invocation.listRequest.parentId != ""
			&& !invocation.listRequest.ready
			&& !invocation.listFlat
			&& (invocation.watchMode || (invocation.output == Human && invocation.listRequest.format == ""));
	}

	/**
		Reconstructs the recursive parent view in Haxe from typed list reads.

		The storage port returns direct children only. Haxe owns parent validation,
		cycle defense, traversal order, and the upstream-compatible error context.
		The page read comes first, as upstream's; the parent and each level are
		follow-up reads, which upstream makes in the store that it opened once.
	**/
	function loadIssueHierarchy(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):IssueListResult {
		final request = invocation.listRequest;
		switch query.issueList(location.path, location.databaseName, request, effectiveLimit, invocation.global) {
			case ListFailure(message):
				return ListFailure(message);
			case ListRowLimitExceeded(found, source, cap):
				return ListRowLimitExceeded(found, source, cap);
			case ListSuccess(_):
		}

		final parent = switch query.issueList(location.path, location.databaseName, IssueListRequests.exact(request.parentId), 0, invocation.global) {
			case ListFailure(message): return ListFailure('error checking parent issue: ${message}');
			case ListRowLimitExceeded(found, source, cap): return ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				if (page.items.length == 0)
					return ListFailure('error checking parent issue: not found: issue ${request.parentId}');
				page.items[0];
		};

		final seen = new StringMap<Bool>();
		seen.set(request.parentId, true);
		return switch collectIssueDescendants(invocation, location, query, request, request.parentId, seen) {
			case ListFailure(message): ListFailure('error finding descendants: ${message}');
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				if (page.items.length > 0)
					page.items.push(parent);
				ListSuccess(page);
		};
	}

	function collectIssueDescendants(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort, request:IssueListRequest, parentId:String,
			seen:StringMap<Bool>):IssueListResult {
		final childRequest = IssueListRequests.descendants(request, parentId);
		return switch query.issueList(location.path, location.databaseName, childRequest, 0, invocation.global) {
			case ListFailure(message): ListFailure(message);
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				final descendants = new Array<IssueListItem>();
				for (child in page.items) {
					if (seen.exists(child.id))
						continue;
					seen.set(child.id, true);
					descendants.push(child);
					switch collectIssueDescendants(invocation, location, query, request, child.id, seen) {
						case ListFailure(message): return ListFailure(message);
						case ListRowLimitExceeded(found, source, cap): return ListRowLimitExceeded(found, source, cap);
						case ListSuccess(nested):
							for (item in nested.items)
								descendants.push(item);
					}
				}
				ListSuccess({items: descendants, hasMore: false, formatted: ""});
		};
	}

	/**
		Keeps list polling policy in Haxe while WatchPort owns only timer and signal lifecycle.

		The first read must succeed because there is no last good screen yet. Later read
		failures are reported without discarding that screen or stopping the watcher.
	**/
	function runListWatch(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):Int {
		var current:Null<IssueListPage> = null;
		switch loadListResult(invocation, location, effectiveLimit, query) {
			case ListFailure(message):
				return runStoreFailure('querying issues: ${message}');
			case ListRowLimitExceeded(found, source, cap):
				return runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				current = page;
		}
		if (current == null)
			return 1;

		output.writeStdout(renderWatchedList(current, terminalStyles()));
		var snapshot = issueListWatchSnapshot(current);
		output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
		watch.start();
		var stopped = false;
		while (!stopped) {
			stopped = watch.waitForStop();
			if (stopped)
				continue;
			switch loadListResult(invocation, location, effectiveLimit, query) {
				case ListFailure(message):
					output.writeStderr('Error refreshing issues: ${message}\n');
				case ListRowLimitExceeded(found, source, cap):
					output.writeStderr('Error refreshing issues: ${listRowLimitMessage(found, source, cap)}\n');
				case ListSuccess(page):
					final nextSnapshot = issueListWatchSnapshot(page);
					if (nextSnapshot != snapshot) {
						snapshot = nextSnapshot;
						output.writeStdout(renderWatchedList(page, terminalStyles()));
						output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
					}
			}
		}
		watch.close();
		output.writeStderr("\nStopped watching.\n");
		return 0;
	}

	static function listRowLimitMessage(found:Int, source:String, cap:Int):String {
		return source == "" ? 'search returned ${found} rows, exceeding cap of ${cap}' : 'search returned ${found} rows, exceeding ${source} cap of ${cap}';
	}

	static function renderWatchedList(page:IssueListPage, styles:TerminalStyles):String {
		final now = Date.now();
		final time = '${twoDigits(now.getHours())}:${twoDigits(now.getMinutes())}:${twoDigits(now.getSeconds())}';
		return "\x1b[2J\x1b[H" + StringTools.rpad("", "=", 80) + "\n" + 'Beads - Open & In Progress (${time})\n' + StringTools.rpad("", "=", 80) + "\n\n"
			+ renderListHuman(page, false, "", styles);
	}

	static function twoDigits(value:Int):String {
		return value < 10 ? '0${value}' : Std.string(value);
	}

	static function issueListWatchSnapshot(page:IssueListPage):String {
		final snapshot = new StringBuf();
		for (issue in page.items)
			snapshot.add('${issue.id}:${issue.status}:${issue.updatedAt};');
		return snapshot.toString();
	}

	/**
		Prints one list page as upstream's list command body does. Every view
		except the `--parent` tree then prints the truncation hint for
		`effectiveLimit`; that tree reads each level without a limit. The tree
		views print the --skip-labels footer after the hint. In agent mode the
		flat view prints renderListAgent. A Go template that the native store
		renders reports no has-more flag, so no hint follows its output yet; a
		template that fails prints the lines before the failing edge and no hint.
	**/
	function renderListResult(invocation:Invocation, result:IssueListResult, effectiveLimit:Int):Int {
		return switch result {
			case ListFailure(message): runStoreFailure(message);
			case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				final skipLabels = invocation.listRequest.skipLabels;
				final hierarchy = isListHierarchy(invocation);
				// Upstream checks --format before agent mode, and prints the --limit hint after it.
				if (invocation.listRequest.format != "") {
					switch selectIssueListFormat(invocation.listRequest.format) {
						case GraphvizDot:
							output.writeStdout(renderListDot(page.items, goQuote));
						case DependencyDigraph:
							output.writeStdout(renderListDigraph(page.items));
						case PageTemplate(source):
							final rendered = renderListTemplate(page.items, source);
							output.writeStdout(rendered.text);
							if (rendered.error != null) return runStoreFailure(rendered.error);
						case NativeTemplate(_) | NoListFormat:
							output.writeStdout(page.formatted);
					}
				} else
					switch invocation.output {
						case Human:
							if (page.items.length == 0 && hierarchy) {
								output.writeStdout('Issue \'${invocation.listRequest.parentId}\' has no children\n');
								return 0;
							}
							if (!invocation.listFlat) {
								output.writeStdout(renderListHuman(page, false, invocation.listDepsMode, terminalStyles()));
								if (!hierarchy)
									writeTruncationHint(page.hasMore, effectiveLimit);
								if (skipLabels)
									output.writeStdout(appendSkipLabelsFooter("", true));
								return 0;
							}
							output.writeStdout(invocation.agentMode ? renderListAgent(page) : renderListFlat(page, invocation.listLong, skipLabels,
								invocation.listRequest.brief, terminalStyles()));
						case Json:
							final exit = writeRenderedJsonStdout(renderListJson(page, skipLabels));
							if (exit != 0) return exit;
					}
				writeTruncationHint(page.hasMore, effectiveLimit);
				0;
		};
	}

	function resolveListLimit(invocation:Invocation, location:WorkspaceLocation):Int {
		return switch invocation.listRequest.limit {
			case IntPresent(value): value;
			case IntAbsent:
				if (invocation.listRequest.all) 0; else if (location.listLimitConfigured) location.listLimit; else if (!output.isStdoutTerminal()) 0; else
					if (invocation.agentMode) 20; else 50;
		};
	}

	function runListRowLimitExceeded(found:Int, source:String, cap:Int):Int {
		final attributedSource = source == "" ? "BEADS_MAX_ROWS" : source;
		output.writeStderr('Error: too many rows: ${found} found, ${attributedSource}=${cap} exceeded.\n');
		output.writeStderr("       Refine the query (add filters, set --limit), or raise the cap with\n");
		output.writeStderr("       --max-rows N or BEADS_MAX_ROWS=N.\n");
		return 2;
	}

	/**
		Upstream displayPrettyListWithDepsMode (cmd/bd/list_tree.go:161-220): the
		tree view, each line from `renderListLine`, with the dependency rows of
		--deps in the muted style.
	**/
	static function renderListHuman(page:IssueListPage, skipLabels:Bool, depsMode:String, styles:TerminalStyles):String {
		if (page.items.length == 0)
			return appendSkipLabelsFooter("No issues found.\n", skipLabels);
		final byId = new Map<String, IssueListItem>();
		for (item in page.items)
			byId.set(item.id, item);
		final childGroups = new Array<ListChildGroup>();
		var roots = new Array<IssueListItem>();
		for (item in page.items) {
			var parent = item.parent;
			if (parent == "") {
				final separator = item.id.lastIndexOf(".");
				if (separator > 0) {
					final dottedParent = item.id.substr(0, separator);
					if (byId.exists(dottedParent))
						parent = dottedParent;
				}
			}
			if (parent != "" && byId.exists(parent)) {
				var group:Null<ListChildGroup> = null;
				for (candidate in childGroups) {
					if (candidate.parent == parent) {
						group = candidate;
						break;
					}
				}
				if (group == null) {
					group = {parent: parent, children: []};
					childGroups.push(group);
				}
				group.children.push(item);
			} else {
				roots.push(item);
			}
		}
		roots = depsMode == "" ? sortedListItems(roots) : orderListItemsByDependencies(roots);
		for (index in 0...childGroups.length) {
			final group = childGroups[index];
			childGroups[index] = {
				parent: group.parent,
				children: depsMode == "" ? sortedListItems(group.children) : orderListItemsByDependencies(group.children)
			};
		}
		final rendered = new StringBuf();
		for (root in roots) {
			rendered.add(renderListLine(root, styles));
			if (depsMode != "")
				rendered.add(renderListDependencyAnnotations(root, "", depsMode, byId, styles));
			renderListChildren(rendered, root.id, "", childGroups, depsMode, byId, styles);
		}
		var open = 0;
		var inProgress = 0;
		for (item in page.items) {
			if (item.status == "open")
				open++;
			else if (item.status == "in_progress")
				inProgress++;
		}
		rendered.add("\n" + StringTools.rpad("", "-", 80) + "\n");
		if (page.hasMore)
			rendered.add('Showing ${page.items.length} issues (${open} open, ${inProgress} in progress); more match (truncated by --limit). Use --limit 0 for all.\n');
		else
			rendered.add('Total: ${page.items.length} issues (${open} open, ${inProgress} in progress)\n');
		rendered.add("\nStatus: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n");
		rendered.add("Priority: P0–P4 (label only; not a status icon)\n");
		if (depsMode != "")
			rendered.add("Deps:   ╌╌▷ = depends-on / relationship (points to target); siblings ordered so dependencies come first; ↗ = target outside current view\n");
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	static function renderListChildren(rendered:StringBuf, parent:String, prefix:String, childGroups:Array<ListChildGroup>, depsMode:String,
			byId:Map<String, IssueListItem>, styles:TerminalStyles):Void {
		var group:Null<ListChildGroup> = null;
		for (candidate in childGroups) {
			if (candidate.parent == parent) {
				group = candidate;
				break;
			}
		}
		if (group == null)
			return;
		for (index in 0...group.children.length) {
			final child = group.children[index];
			final last = index == group.children.length - 1;
			rendered.add(prefix + (last ? "└── " : "├── ") + renderListLine(child, styles));
			final extension = prefix + (last ? "    " : "│   ");
			if (depsMode != "")
				rendered.add(renderListDependencyAnnotations(child, extension, depsMode, byId, styles));
			renderListChildren(rendered, child.id, extension, childGroups, depsMode, byId, styles);
		}
	}

	static function renderListLine(issue:IssueListItem, styles:TerminalStyles):String {
		return renderPrettyIssue(issue, styles) + "\n";
	}

	/**
		Upstream formatPrettyIssue (cmd/bd/list_format.go:45-71): the styled status
		icon, ID, priority, an [epic] or [bug] badge and the title. A closed issue
		mutes its ID, its priority, and its plain type, for every type, in place of
		the badge, and then the title with the space before it.
	**/
	static function renderPrettyIssue(issue:IssueListItem, styles:TerminalStyles):String {
		return renderShortIssue(issue.id, issue.title, issue.status, issue.priority, issue.issueType, styles);
	}

	/**
		The one-line issue of upstream formatPrettyIssue and formatShortIssue
		(cmd/bd/show_format.go:19-43), which print the same text.
	**/
	static function renderShortIssue(id:String, title:String, status:String, priority:beadshx.store.JsonInteger, issueType:String,
			styles:TerminalStyles):String {
		final icon = styles.renderStatusIcon(status);
		if (status == "closed")
			return '${icon} ${styles.renderMuted(id)} ${styles.renderMuted('P${priority}')} ${styles.renderMuted(issueType)}'
				+ styles.renderMuted(" " + title);
		final typeBadge = switch issueType {
			case "epic": styles.typeEpic.render("[epic]") + " ";
			case "bug": styles.typeBug.render("[bug]") + " ";
			case _: "";
		};
		return '${icon} ${id} ${styles.renderPriority(priority)} ${typeBadge}${title}';
	}

	static function compareListItems(left:IssueListItem, right:IssueListItem):Int {
		final priority = left.priority.compare(right.priority);
		return priority != 0 ? priority : compareIssueIds(left.id, right.id);
	}

	static function sortedListItems(items:Array<IssueListItem>):Array<IssueListItem> {
		final ordered = items.copy();
		ordered.sort(compareListItems);
		return ordered;
	}

	static function orderListItemsByDependencies(items:Array<IssueListItem>):Array<IssueListItem> {
		if (items.length < 2)
			return items.copy();
		final byId = new Map<String, IssueListItem>();
		final indegree = new Map<String, Int>();
		final dependents = new Map<String, Array<String>>();
		for (item in items) {
			byId.set(item.id, item);
			indegree.set(item.id, 0);
		}
		for (item in items) {
			final seen = new Map<String, Bool>();
			for (dependency in item.dependencies) {
				final presentation = listDependencyPresentation(dependency.dependencyType);
				if (presentation == null
					|| !presentation.scheduling
					|| dependency.dependsOnId == item.id
					|| !byId.exists(dependency.dependsOnId)
					|| seen.exists(dependency.dependsOnId))
					continue;
				seen.set(dependency.dependsOnId, true);
				final degree = indegree.get(item.id);
				indegree.set(item.id, (degree == null ? 0 : degree) + 1);
				var targets = dependents.get(dependency.dependsOnId);
				if (targets == null) {
					targets = [];
					dependents.set(dependency.dependsOnId, targets);
				}
				targets.push(item.id);
			}
		}
		final ready = new Array<IssueListItem>();
		for (item in items)
			if (indegree.get(item.id) == 0)
				ready.push(item);
		ready.sort(compareListItems);
		final ordered = new Array<IssueListItem>();
		final emitted = new Map<String, Bool>();
		while (ready.length > 0) {
			final item = ready[0];
			ready.shift();
			ordered.push(item);
			emitted.set(item.id, true);
			final targets = dependents.get(item.id);
			if (targets == null)
				continue;
			var grew = false;
			for (targetId in targets) {
				final degree = indegree.get(targetId);
				final next = (degree == null ? 0 : degree) - 1;
				indegree.set(targetId, next);
				if (next == 0) {
					final target = byId.get(targetId);
					if (target != null)
						ready.push(target);
					grew = true;
				}
			}
			if (grew)
				ready.sort(compareListItems);
		}
		if (ordered.length < items.length) {
			final remainder = new Array<IssueListItem>();
			for (item in items)
				if (!emitted.exists(item.id))
					remainder.push(item);
			remainder.sort(compareListItems);
			for (item in remainder)
				ordered.push(item);
		}
		return ordered;
	}

	static function renderListDependencyAnnotations(item:IssueListItem, prefix:String, depsMode:String, byId:Map<String, IssueListItem>,
			styles:TerminalStyles):String {
		final inView = new Array<ListDependencyRow>();
		final outside = new Array<String>();
		final seen = new Map<String, Bool>();
		for (dependency in item.dependencies) {
			final presentation = listDependencyPresentation(dependency.dependencyType);
			if (presentation == null || (depsMode != "all" && !presentation.scheduling))
				continue;
			final key = dependency.dependencyType + "\x00" + dependency.dependsOnId;
			if (seen.exists(key))
				continue;
			seen.set(key, true);
			final target = byId.get(dependency.dependsOnId);
			if (target == null)
				outside.push(dependency.dependsOnId);
			else
				inView.push({label: presentation.label, target: dependency.dependsOnId, title: target.title});
		}
		inView.sort((left, right) -> left.label != right.label ? (left.label < right.label ? -1 : 1) : compareIssueIds(left.target, right.target));
		outside.sort(compareIssueIds);
		final rendered = new StringBuf();
		// Upstream mutes the glyph and padded label of each row (cmd/bd/list_tree_deps.go:184), and the whole summary.
		for (row in inView)
			rendered.add(prefix + styles.renderMuted("╌╌▷ " + StringTools.rpad('[${row.label}]', " ", 20)) + ' ${row.target} ${row.title}\n');
		if (outside.length > 0) {
			final named = outside.length > 4 ? outside.slice(0, 4) : outside;
			final suffix = outside.length > 4 ? ', +${outside.length - 4} more' : "";
			rendered.add(prefix + styles.renderMuted('╌╌▷ ↗ ${outside.length} outside this view: ${named.join(", ")}${suffix}') + "\n");
		}
		return rendered.toString();
	}

	static function listDependencyPresentation(dependencyType:String):Null<ListDependencyPresentation> {
		return switch dependencyType {
			case "parent-child": null;
			case "blocks": {label: "depends-on", scheduling: true};
			case "conditional-blocks": {label: "conditionally-depends-on", scheduling: true};
			case "waits-for": {label: "waits-for", scheduling: true};
			case "related" | "relates-to": {label: "related", scheduling: false};
			case "discovered-from": {label: "discovered-from", scheduling: false};
			case "duplicates": {label: "duplicates", scheduling: false};
			case "supersedes": {label: "superseded-by", scheduling: false};
			case "replies-to": {label: "replies-to", scheduling: false};
			case _: {label: dependencyType, scheduling: false};
		};
	}

	static function renderListJson(page:IssueListPage, skipLabels:Bool):StoreResult<String> {
		final array = switch renderListJsonArray(page, skipLabels, skipLabels) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		if (!skipLabels)
			return Success(array);
		final rows = array.split("\n");
		final lines = ['{', '  "issues": ${rows[0]}'];
		for (index in 1...(rows.length - 1))
			lines.push("  " + rows[index]);
		lines[lines.length - 1] += ",";
		lines.push('  "meta": {');
		lines.push('    "count": ${page.items.length},');
		lines.push('    "skip_labels": true');
		lines.push("  }");
		lines[lines.length - 1] += ",";
		lines.push('  "schema_version": 1');
		lines.push("}");
		return Success(lines.join("\n") + "\n");
	}

	static function appendSkipLabelsFooter(rendered:String, skipLabels:Bool):String {
		return skipLabels ? rendered + "\nnote: --skip-labels in effect — labels suppressed in output.\n" : rendered;
	}

	/**
		Upstream formatIssueCompact for each issue (cmd/bd/list_format.go:238-277),
		or the --long view. An open issue with an open blocker takes the blocked
		icon, and a pinned issue the pin prefix. A closed issue's whole line is in
		the closed style; any other line styles its ID, priority and type.
	**/
	static function renderListFlat(page:IssueListPage, long:Bool, skipLabels:Bool, brief:Bool, styles:TerminalStyles):String {
		if (long)
			return renderListLong(page, skipLabels, brief, styles);
		final rendered = new StringBuf();
		for (issue in page.items) {
			final dependencyInfo = renderListBlockingInfo(issue);
			final suffix = dependencyInfo == "" ? "" : ' ${dependencyInfo}';
			final renderedStatus = issue.status == "open" && issue.blockedBy.length > 0 ? "blocked" : issue.status;
			rendered.add(renderCompactIssue(issue, styles.renderStatusIcon(renderedStatus), pinIndicator(issue), suffix, styles));
		}
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	/**
		The compact line that upstream's list (formatIssueCompact) and query
		(formatQueryIssue, cmd/bd/query.go:257-285) print for one issue, with its
		`icon`, the `pin` prefix before the ID (which only list prints), the
		dependency note `suffix`, and a line feed.
	**/
	static function renderCompactIssue(issue:IssueListItem, icon:String, pin:String, suffix:String, styles:TerminalStyles):String {
		final assignee = issue.assignee == "" ? "" : ' @${issue.assignee}';
		final labels = issue.labels.length == 0 ? "" : ' [${issue.labels.join(" ")}]';
		if (issue.status == "closed")
			return styles.renderClosedLine('${icon} ${pin}${issue.id} [P${issue.priority}] [${issue.issueType}]${assignee}${labels} - ${issue.title}${suffix}')
				+ "\n";
		return
			'${icon} ${pin}${styles.renderId(issue.id)} [${styles.renderPriority(issue.priority)}] [${styles.renderType(issue.issueType)}]${assignee}${labels} - ${issue.title}${suffix}\n';
	}

	/**
		Upstream pinIndicator (cmd/bd/list_format.go:24-29): `📌 ` for an issue
		with the pinned flag, and nothing otherwise.

		Why: only list's flat and long views print it, before the ID and inside
		the closed style of a closed issue; the tree view, the agent view and
		query do not. What: the prefix text, never styled. How: the list row
		carries the stored flag in its long fields; the pinned status is a
		different thing and keeps its own status icon.
	**/
	static function pinIndicator(issue:IssueListItem):String {
		return issue.longFields.pinned ? "📌 " : "";
	}

	/**
		Upstream formatAgentIssue for each row of the flat list in agent mode:
		`ID: Title`, then the dependency note of the flat view when there is one.
		It prints no status, priority, type, assignee or labels, also for --long,
		and no --skip-labels footer.
	**/
	static function renderListAgent(page:IssueListPage):String {
		final rendered = new StringBuf();
		for (issue in page.items) {
			final dependencyInfo = renderListBlockingInfo(issue);
			rendered.add(dependencyInfo == "" ? '${issue.id}: ${issue.title}\n' : '${issue.id}: ${issue.title} ${dependencyInfo}\n');
		}
		return rendered.toString();
	}

	static function renderListBlockingInfo(issue:IssueListItem):String {
		final parts = new Array<String>();
		if (issue.blockingParent != "")
			parts.push('parent: ${issue.blockingParent}');
		if (issue.blockedBy.length > 0)
			parts.push('blocked by: ${issue.blockedBy.join(", ")}');
		if (issue.blocks.length > 0)
			parts.push('blocks: ${issue.blocks.join(", ")}');
		return parts.length == 0 ? "" : '(' + parts.join(", ") + ')';
	}

	/**
		Upstream formatIssueLong for each issue (cmd/bd/list_format.go:85-132). A
		pinned issue's first line starts with the pin prefix. A closed issue's
		first two lines are one text in the closed style, which lipgloss pads to
		the same width when colors are on; any other issue styles its ID,
		priority, type and status.
	**/
	static function renderListLong(page:IssueListPage, skipLabels:Bool, brief:Bool, styles:TerminalStyles):String {
		final rendered = new StringBuf();
		rendered.add('\nFound ${page.items.length} issues:\n\n');
		for (issue in page.items) {
			final pin = pinIndicator(issue);
			if (issue.status == "closed")
				rendered.add(styles.renderClosedLine('${pin}${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n  ${issue.title}') + "\n");
			else {
				rendered.add('${pin}${styles.renderId(issue.id)} [${styles.renderPriority(issue.priority)}] [${styles.renderType(issue.issueType)}] ${styles.renderStatus(issue.status)}\n');
				rendered.add('  ${issue.title}\n');
			}
			if (issue.assignee != "")
				rendered.add('  Assignee: ${issue.assignee}\n');
			if (brief) {
				rendered.add("  Description: (omitted by --brief)\n");
			} else {
				final description = StringTools.trim(issue.description);
				if (description != "") {
					rendered.add("  Description:\n");
					for (line in description.split("\n"))
						rendered.add('    ${line}\n');
				}
			}
			if (skipLabels)
				rendered.add("  Labels: (suppressed by --skip-labels)\n");
			else if (issue.labels.length > 0)
				rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
			if (issue.metadata.hasHumanValue()) {
				final count = issue.metadata.topLevelFieldCount();
				rendered.add(count > 0 ? '  Metadata: ${count} keys\n' : "  Metadata: set\n");
			}
			rendered.add("\n");
		}
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	/**
		Upstream's `types.IssueWithCounts` for each item (internal/types/types.go:1136-1142):
		the whole Issue, with its labels and, when `includeRelations` is on, its
		dependencies, then the counts and the parent. `forceLabels` is list
		--skip-labels' empty labels member (cmd/bd/list.go:47-53), whose view
		upstream round-trips through a map, so `sortFields` sorts every key.
	**/
	static function renderListJsonArray(page:IssueListPage, forceLabels:Bool, sortFields:Bool, includeRelations:Bool = true):StoreResult<String> {
		if (page.items.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (index in 0...page.items.length) {
			final item = page.items[index];
			final fields = switch renderIssueFields(item, sortFields, "    ", forceLabels ? null : item.labels, includeRelations ? item.dependencies : null) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			if (forceLabels)
				fields.push('"labels": []');
			fields.push('"dependency_count": ${item.dependencyCount}');
			fields.push('"dependent_count": ${item.dependentCount}');
			fields.push('"comment_count": ${item.commentCount}');
			if (includeRelations && item.parent != "")
				fields.push('"parent": ${Json.stringify(item.parent)}');
			if (sortFields)
				fields.sort(compareJsonFields);
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == page.items.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	/** The Issue's own `types.Dependency` rows (internal/types/types.go:1102-1120), at a field indent of `fieldIndent`. */
	static function renderListDependencies(dependencies:Array<IssueListDependency>, sortFields:Bool, fieldIndent:String):String {
		final objectIndent = fieldIndent + "  ";
		final memberIndent = objectIndent + "  ";
		final lines = ['"dependencies": ['];
		for (index in 0...dependencies.length) {
			final dependency = dependencies[index];
			final fields = new Array<String>();
			if (dependency.id != "")
				fields.push('"id": ${Json.stringify(dependency.id)}');
			fields.push('"issue_id": ${Json.stringify(dependency.issueId)}');
			fields.push('"depends_on_id": ${Json.stringify(dependency.dependsOnId)}');
			fields.push('"type": ${Json.stringify(dependency.dependencyType)}');
			fields.push('"created_at": ${Json.stringify(dependency.createdAt)}');
			if (dependency.createdBy != "")
				fields.push('"created_by": ${Json.stringify(dependency.createdBy)}');
			if (dependency.metadata != "")
				fields.push('"metadata": ${Json.stringify(dependency.metadata)}');
			if (dependency.threadId != "")
				fields.push('"thread_id": ${Json.stringify(dependency.threadId)}');
			if (sortFields)
				fields.sort(compareJsonFields);
			lines.push('${objectIndent}{');
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('${memberIndent}${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == dependencies.length - 1 ? "" : ",";
			lines.push('${objectIndent}}${suffix}');
		}
		lines.push('${fieldIndent}]');
		return lines.join("\n");
	}

	static function compareJsonFields(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}

	function runShowWatch(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length != 1)
			return runModeAwareFailure(invocation.output, "watch mode requires exactly one issue ID");

		final requestedId = ids[0];
		var canonicalId = requestedId;
		var current:Null<IssueDetails> = null;
		switch loadWatchedIssue(location, requestedId, invocation.global, true, query) {
			case ReadElsewhere:
				return runRoutedLookupRefusal(invocation);
			case ReadHere(Failure(message)):
				output.writeStderr('Error fetching issue: ${message}\n');
				return 0;
			case ReadHere(Success(DetailsMissing)):
				output.writeStdout('Issue not found: ${requestedId}\n');
				return 0;
			case ReadHere(Success(DetailsFound(issue))):
				canonicalId = issue.id;
				current = issue;
		}
		if (current == null)
			return 0;

		final localNode = () -> localNodeId(location);
		switch renderIssueHuman(current, invocation.agentMode, false, localNode, WatchedShow) {
			case Failure(message):
				return runStoreFailure(message);
			case Success(rendered):
				output.writeStdout(rendered);
		}
		var snapshot = issueWatchSnapshot(current);
		output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
		watch.start();
		var stopped = false;
		while (!stopped) {
			stopped = watch.waitForStop();
			if (stopped)
				continue;
			switch loadWatchedIssue(location, canonicalId, invocation.global, true, query) {
				case ReadElsewhere:
					watch.close();
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(_) | Success(DetailsMissing)):
				case ReadHere(Success(DetailsFound(issue))):
					final nextSnapshot = issueWatchSnapshot(issue);
					if (nextSnapshot != snapshot) {
						switch renderIssueHuman(issue, invocation.agentMode, false, localNode, WatchedShow) {
							case Failure(message):
								watch.close();
								return runStoreFailure(message);
							case Success(rendered):
								snapshot = nextSnapshot;
								output.writeStdout(rendered);
						}
						output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
					}
			}
		}
		watch.close();
		output.writeStderr("\nStopped watching.\n");
		return 0;
	}

	/** Upstream config.NodeID (internal/config/config.go:1062-1064): the trimmed `node_id` setting, also from BEADS_NODE_ID or BD_NODE_ID. */
	static function localNodeId(location:WorkspaceLocation):String {
		return goTrimSpace(LayeredConfig.forWorkspace(location.path).getString("node_id"));
	}

	function loadWatchedIssue(location:WorkspaceLocation, id:String, global:Bool, includeComments:Bool,
			query:IssueQueryPort):RoutedRead<StoreResult<IssueDetailsLookup>> {
		return switch lookupIssueWithRouting(location, id, global, query) {
			case ReadElsewhere: ReadElsewhere;
			case ReadHere(Failure(message)): ReadHere(Failure(message));
			case ReadHere(Success(IssueMissing)): ReadHere(Failure('no issue found matching "${id}"'));
			case ReadHere(Success(IssueFound(summary))):
				ReadHere(query.issueDetails(location.path, summary.id, {
					includeDependents: true,
					includeComments: includeComments,
					briefDependencies: false
				}, global));
		};
	}

	static function issueWatchSnapshot(issue:IssueDetails):String {
		return '${issue.id}:${issue.status}:${issue.updatedAt}';
	}

	function runShowThread(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");

		final requestedId = ids[0];
		var canonicalId = "";
		switch lookupIssueWithRouting(location, requestedId, invocation.global, query) {
			case ReadElsewhere:
				return runRoutedLookupRefusal(invocation);
			case ReadHere(Failure(_) | Success(IssueMissing)):
				if (invocation.output == Human)
					return runShowHuman(invocation, location, query);
				return runShowJson(invocation, location, query);
			case ReadHere(Success(IssueFound(summary))):
				canonicalId = summary.id;
		}
		final detailRequest:IssueDetailsRequest = {
			includeDependents: true,
			includeComments: false,
			briefDependencies: false
		};
		var root:Null<IssueDetails> = null;
		switch query.issueDetails(location.path, canonicalId, detailRequest, invocation.global) {
			case Failure(message):
				return runStoreFailure('fetching message ${canonicalId}: ${message}');
			case Success(DetailsMissing):
				return runStoreFailure('message ${canonicalId} not found');
			case Success(DetailsFound(issue)):
				root = issue;
		}
		if (root == null)
			return runStoreFailure('message ${canonicalId} not found');
		final ancestors = new Map<String, Bool>();
		ancestors.set(root.id, true);
		while (true) {
			final parentId = threadParentId(root);
			if (parentId == "" || ancestors.exists(parentId))
				break;
			ancestors.set(parentId, true);
			switch query.issueDetails(location.path, parentId, detailRequest, invocation.global) {
				case Failure(_) | Success(DetailsMissing):
					break;
				case Success(DetailsFound(parent)):
					root = parent;
			}
		}

		final entries = new Array<ThreadEntry>();
		entries.push({issue: root, parentId: ""});
		final threadIds = new Map<String, Bool>();
		threadIds.set(root.id, true);
		final queue = [root];
		var queueIndex = 0;
		while (queueIndex < queue.length) {
			final current = queue[queueIndex++];
			for (dependent in current.dependents) {
				if (dependent.dependencyType != "replies-to" || threadIds.exists(dependent.id))
					continue;
				switch query.issueDetails(location.path, dependent.id, detailRequest, invocation.global) {
					case Failure(_) | Success(DetailsMissing):
					case Success(DetailsFound(reply)):
						threadIds.set(reply.id, true);
						entries.push({issue: reply, parentId: current.id});
						queue.push(reply);
				}
			}
		}
		entries.sort((left, right) -> left.issue.createdAt < right.issue.createdAt ? -1 : left.issue.createdAt == right.issue.createdAt ? 0 : 1);
		switch invocation.output {
			case Human:
				output.writeStdout(renderThreadHuman(root.title, entries, terminalStyles()));
			case Json:
				return writeRenderedJsonStdout(renderThreadJson(entries));
		}
		return 0;
	}

	static function threadParentId(issue:IssueDetails):String {
		for (dependency in issue.dependencies)
			if (dependency.dependencyType == "replies-to")
				return dependency.id;
		return "";
	}

	/** Upstream's thread view (cmd/bd/show_thread.go:94-131): accented IDs, muted times and Subject labels. */
	static function renderThreadHuman(title:String, entries:Array<ThreadEntry>, styles:TerminalStyles):String {
		final parents = new Map<String, String>();
		for (entry in entries)
			parents.set(entry.issue.id, entry.parentId);
		var rendered = '\n${styles.renderAccent("📬")} Thread: ${title}\n' + StringTools.rpad("", "─", 66) + "\n";
		for (entry in entries) {
			var depth = 0;
			var parent = entry.parentId;
			while (parent != "" && depth < 5) {
				depth++;
				final next = parents.get(parent);
				parent = next == null ? "" : next;
			}
			final indent = StringTools.lpad("", " ", depth * 2);
			final issue = entry.issue;
			final icon = issue.status == "closed" ? "✓" : "📧";
			rendered += '${indent}${icon} ${styles.renderAccent(issue.id)} ${styles.renderMuted(formatHumanTime(issue.createdAt))}\n';
			rendered += '${indent}  From: ${issue.longFields.sender}  To: ${issue.assignee}\n';
			if (entry.parentId != "")
				rendered += '${indent}  Re: ${entry.parentId}\n';
			rendered += '${indent}  ${styles.renderMuted("Subject")}: ${issue.title}\n';
			if (issue.description != "")
				for (line in issue.description.split("\n"))
					rendered += '${indent}  ${line}\n';
			rendered += "\n";
		}
		return rendered + 'Total: ${entries.length} messages in thread\n\n';
	}

	function runShowRefs(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final groups = new Array<ShowDependencyGroup>();
		for (id in ids) {
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					output.writeStderr('Error resolving ${id}: ${message}\n');
				case ReadHere(Success(IssueMissing)):
					output.writeStderr('Error resolving ${id}: no issue found matching "${id}"\n');
				case ReadHere(Success(IssueFound(summary))):
					switch query.issueDependents(location.path, summary.id, invocation.global) {
						case Failure(message): output.writeStderr('Error getting refs for ${id}: ${message}\n');
						case Success(references):
							var replaced = false;
							for (index in 0...groups.length) {
								if (groups[index].issueId == summary.id) {
									groups[index] = {issueId: summary.id, items: references};
									replaced = true;
									break;
								}
							}
							if (!replaced) groups.push({issueId: summary.id, items: references});
					}
			}
		}
		switch invocation.output {
			case Json:
				return writeRenderedJsonStdout(renderShowDependencyMapJson(groups, output.usesJsonEnvelope(), true));
			case Human:
				for (group in groups)
					output.writeStdout(renderShowRefsGroup(group, terminalStyles()));
		}
		return 0;
	}

	/**
		Upstream's refs view of one issue and displayRefGroup
		(cmd/bd/show_refs.go:56-103): a closed reference is muted, and an open,
		in-progress or blocked one has its ID in that status's style.
	**/
	static function renderShowRefsGroup(group:ShowDependencyGroup, styles:TerminalStyles):String {
		if (group.items.length == 0)
			return '\n${styles.renderAccent(group.issueId)}: No references found\n';
		final sections = new Array<HumanDependencyGroup>();
		for (reference in group.items) {
			final relation = humanDependencyRelation(reference.dependencyType);
			var selected:Null<HumanDependencyGroup> = null;
			for (section in sections)
				if (section.relation.canonical == relation.canonical) {
					selected = section;
					break;
				}
			if (selected == null) {
				selected = {relation: relation, dependencies: []};
				sections.push(selected);
			}
			selected.dependencies.push(reference);
		}
		sections.sort(compareHumanDependencyGroups);
		var rendered = '\n${styles.renderAccent("📎")} References to ${group.issueId}:\n';
		for (section in sections) {
			rendered += '\n  ${referenceEmoji(section.relation.canonical)} ${section.relation.incomingHeading} (${section.dependencies.length}):\n';
			for (reference in section.dependencies) {
				if (reference.status == "closed") {
					rendered += '    ${styles.renderMuted(reference.id)}: ${styles.renderMuted(reference.title)} ${styles.renderMuted('[P${reference.priority} - ${reference.status}]')}\n';
					continue;
				}
				rendered += '    ${styles.renderStatusId(reference.status, reference.id)}: ${reference.title} [P${reference.priority} - ${reference.status}]\n';
			}
		}
		return rendered + "\n";
	}

	static function referenceEmoji(dependencyType:String):String {
		return switch dependencyType {
			case "until": "⏳";
			case "caused-by": "⚡";
			case "validates": "✅";
			case "blocks": "🚫";
			case "parent-child": "↳";
			case "related": "↔";
			case "tracks": "👁";
			case "discovered-from": "◊";
			case "supersedes": "⬆";
			case "duplicates": "🔄";
			case "replies-to": "💬";
			case "approved-by": "👍";
			case "authored-by": "✏";
			case "assigned-to": "👤";
			case _: "→";
		};
	}

	function runShowChildren(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final groups = new Array<ShowDependencyGroup>();
		for (id in ids) {
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					output.writeStderr('Error resolving ${id}: ${message}\n');
				case ReadHere(Success(IssueMissing)):
					output.writeStderr('Error resolving ${id}: no issue found matching "${id}"\n');
				case ReadHere(Success(IssueFound(summary))):
					switch query.issueDependents(location.path, summary.id, invocation.global) {
						case Failure(message): output.writeStderr('Error getting children for ${id}: ${message}\n');
						case Success(dependents):
							final children = new Array<IssueDependency>();
							for (dependent in dependents)
								if (dependent.dependencyType == "parent-child")
									children.push(dependent);
							var replaced = false;
							for (index in 0...groups.length) {
								if (groups[index].issueId == summary.id) {
									groups[index] = {issueId: summary.id, items: children};
									replaced = true;
									break;
								}
							}
							if (!replaced) groups.push({issueId: summary.id, items: children});
					}
			}
		}
		switch invocation.output {
			case Json:
				return writeRenderedJsonStdout(renderShowDependencyMapJson(groups, output.usesJsonEnvelope(), false));
			case Human:
				// Upstream showIssueChildren (cmd/bd/show_children.go:69-84).
				final styles = terminalStyles();
				for (group in groups) {
					if (group.items.length == 0) {
						output.writeStdout('${styles.renderAccent(group.issueId)}: No children found\n');
					} else {
						output.writeStdout('${styles.renderAccent("↳")} Children of ${group.issueId} (${group.items.length}):\n');
						for (child in group.items)
							output.writeStdout(invocation.showShort ? '  ${renderShortIssue(child.id, child.title, child.status, child.priority, child.issueType, styles)}\n' : '${renderDependencyLine("↳", child, styles)}\n');
						output.writeStdout("\n");
					}
				}
		}
		return 0;
	}

	/**
		Upstream show --children and --refs JSON: a map from each issue ID to its
		`types.IssueWithDependencyMetadata` rows (internal/types/types.go:1130-1133).
		Without the envelope, upstream round-trips the map through
		`map[string]interface{}` (cmd/bd/output.go:68-99), which sorts every key.
	**/
	static function renderShowDependencyMapJson(groups:Array<ShowDependencyGroup>, envelope:Bool, emptyAsNull:Bool):StoreResult<String> {
		final orderedGroups = groups.copy();
		orderedGroups.sort((left, right) -> compareIssueIds(left.issueId, right.issueId));
		final keys = ["schema_version"];
		for (group in orderedGroups)
			keys.push(group.issueId);
		keys.sort(compareIssueIds);
		final lines = ["{"];
		for (keyIndex in 0...keys.length) {
			final key = keys[keyIndex];
			final topSuffix = keyIndex == keys.length - 1 ? "" : ",";
			if (key == "schema_version") {
				lines.push('  "schema_version": 1${topSuffix}');
				continue;
			}
			var selected:Null<ShowDependencyGroup> = null;
			for (group in orderedGroups)
				if (group.issueId == key) {
					selected = group;
					break;
				}
			final children:Array<IssueDependency> = selected == null ? [] : selected.items;
			if (children.length == 0) {
				lines.push('  ${Json.stringify(key)}: ${emptyAsNull ? "null" : "[]"}${topSuffix}');
				continue;
			}
			lines.push('  ${Json.stringify(key)}: [');
			for (childIndex in 0...children.length) {
				final child = children[childIndex];
				final fields = switch renderIssueFields(child, !envelope, "      ", child.labels) {
					case Failure(message): return Failure(message);
					case Success(value): value;
				};
				fields.push('"dependency_type": ${Json.stringify(child.dependencyType)}');
				if (!envelope)
					fields.sort(compareJsonFields);
				lines.push("    {");
				for (fieldIndex in 0...fields.length) {
					final fieldSuffix = fieldIndex == fields.length - 1 ? "" : ",";
					lines.push('      ${fields[fieldIndex]}${fieldSuffix}');
				}
				lines.push(childIndex == children.length - 1 ? "    }" : "    },");
			}
			lines.push('  ]${topSuffix}');
		}
		lines.push("}");
		return Success(lines.join("\n") + "\n");
	}

	function runShowHuman(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final request:IssueDetailsRequest = {
			includeDependents: true,
			includeComments: true,
			briefDependencies: false
		};
		final found = new Array<IssueDetails>();
		for (id in ids) {
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case ReadHere(Success(IssueMissing)):
					output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
				case ReadHere(Success(IssueFound(summary))):
					switch query.issueDetails(location.path, summary.id, request, invocation.global) {
						case Failure(message): output.writeStderr('Error fetching ${id}: ${message}\n');
						case Success(DetailsMissing): output.writeStderr('Issue ${id} not found\n');
						case Success(DetailsFound(details)): found.push(details);
					}
			}
		}
		final localNode = () -> localNodeId(location);
		for (index in 0...found.length) {
			final rendered = switch renderIssueHuman(found[index], invocation.agentMode, invocation.showLong, localNode) {
				case Failure(message): return runStoreFailure(message);
				case Success(value): value;
			};
			if (index > 0)
				output.writeStdout("\n" + terminalStyles().renderMuted(StringTools.rpad("", "─", 60)) + "\n\n");
			output.writeStdout(rendered);
		}
		recordLastTouched();
		return found.length == 0 ? 1 : 0;
	}

	/**
		Upstream show's SetLastTouchedID after its text output, also when it
		found no issue (cmd/bd/show.go:267, :273), and after JSON output: it
		finds the workspace (last_touched.go:69). The record itself is a write,
		which this build leaves out.
	**/
	function recordLastTouched():Void {
		lookups.findBeadsDir();
	}

	function runShowShort(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final found = new Array<IssueSummary>();
		for (id in ids) {
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case ReadHere(Success(IssueMissing)):
					output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
				case ReadHere(Success(IssueFound(summary))):
					found.push(summary);
			}
		}
		if (found.length == 0) {
			return switch invocation.output {
				case Human:
					recordLastTouched();
					1;
				case Json: runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
			};
		}
		return switch invocation.output {
			case Human:
				for (summary in found)
					output.writeStdout(renderIssueShort(summary, terminalStyles()) + "\n");
				recordLastTouched();
				0;
			case Json:
				// Upstream checks --short before its JSON branch. Preserve the
				// resulting mixed output: compact rows, then the normal JSON error.
				for (summary in found)
					output.writeStdout(renderIssueShort(summary, terminalStyles()) + "\n");
				runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
		};
	}

	function runShowJson(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");

		final found = new Array<IssueDetails>();
		final request:IssueDetailsRequest = {
			includeDependents: invocation.showIncludeDependents,
			includeComments: invocation.showIncludeComments,
			briefDependencies: invocation.showBriefDependencies
		};
		for (id in ids) {
			switch lookupIssueWithRouting(location, id, invocation.global, query) {
				case ReadElsewhere:
					return runRoutedLookupRefusal(invocation);
				case ReadHere(Failure(message)):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case ReadHere(Success(IssueMissing)):
					output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
				case ReadHere(Success(IssueFound(summary))):
					switch query.issueDetails(location.path, summary.id, request, invocation.global) {
						case Failure(message): output.writeStderr('Error fetching ${id}: ${message}\n');
						case Success(DetailsMissing): output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
						case Success(DetailsFound(details)): found.push(details);
					}
			}
		}
		if (found.length == 0)
			return runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
		final result = writeRenderedJsonStdout(renderShowJson(found));
		if (result == 0)
			recordLastTouched();
		return result;
	}

	/** Upstream utils.ResolvePartialID: the exact ID first, and the issue prefix only after a miss. */
	function lookupIssueSummary(location:WorkspaceLocation, id:String, global:Bool, query:IssueQueryPort):StoreResult<IssueLookup> {
		final exact = query.issueSummary(location.path, location.databaseName, id, global);
		return switch exact {
			case Success(IssueMissing):
				final issuePrefix = partialIdPrefix(location);
				final prefixed = configuredPrefixCandidate(id, issuePrefix);
				final normalized = prefixed == id ? exact : query.issueSummary(location.path, location.databaseName, prefixed, global);
				switch normalized {
					case Success(IssueMissing): resolveAbbreviatedIssue(location, id, issuePrefix, prefixed, global, query);
					case Success(IssueFound(_)) | Failure(_): normalized;
				}
			case Success(IssueFound(_)) | Failure(_): exact;
		};
	}

	/**
		Upstream resolveAndGetIssueWithRouting (cmd/bd/routed.go:70-96), the
		lookup of show, comments, dep list and dep tree.

		After a miss upstream tries the routes.jsonl prefix routes (see
		prefixRouteLeaves) and then contributor auto-routing, which asks for the
		user's role and so prints the beads.role warning when Git sets no role
		(see autoRoute). Where either would open another repository, this is
		ReadElsewhere, and the command refuses (see runRoutedLookupRefusal). A
		route that opens this store again misses there again, so upstream
		reports the miss of this store. A proxied workspace does not route.
	**/
	function lookupIssueWithRouting(location:WorkspaceLocation, id:String, global:Bool, query:IssueQueryPort):RoutedRead<StoreResult<IssueLookup>> {
		final lookup = lookupIssueSummary(location, id, global, query);
		switch lookup {
			case Success(IssueMissing) if (!location.proxiedServer):
				if (prefixRouteLeaves(location.path, id, lookups.follow))
					return ReadElsewhere;
				warnUnconfiguredRole();
				if (autoRoute(location, global, query).match(AutoRouteElsewhere))
					return ReadElsewhere;
			case Success(_) | Failure(_):
		}
		return ReadHere(lookup);
	}

	/**
		The refusal of a command whose lookup upstream would answer from another
		repository. It stops the whole command before it prints an issue, also
		in a batch whose other IDs this store holds.
	**/
	function runRoutedLookupRefusal(invocation:Invocation):Int {
		return runModeAwareFailure(invocation.output, routedLookupUnavailable(commandPath(invocation.command)));
	}

	/** Upstream routing.DetectUserRole's warning on stderr, when Git sets no beads.role. It only reads Git's config. */
	function warnUnconfiguredRole():Void {
		if (!UserRole.configured())
			output.writeStderr(UserRole.WARNING);
	}

	/**
		The prefix that partial-ID lookup adds to an ID and strips from the
		candidates. Upstream ResolvePartialID takes the stored issue_prefix, also
		when config.yaml names another prefix. Without one, upstream takes `bd`
		and guesses each candidate's prefix, which this lookup does not do; it
		takes config.yaml's prefix instead, as it does where it reads no stored
		prefix (a server or proxied workspace).
	**/
	function partialIdPrefix(location:WorkspaceLocation):String {
		final stored = storedIssuePrefix(location, ReadNothing);
		return stored != "" ? stored : location.yamlPrefix;
	}

	function resolveAbbreviatedIssue(location:WorkspaceLocation, input:String, issuePrefix:String, normalized:String, global:Bool,
			query:IssueQueryPort):StoreResult<IssueLookup> {
		final prefix = normalizedPrefix(issuePrefix);
		final hashPart = StringTools.startsWith(normalized, prefix) ? normalized.substr(prefix.length) : normalized;
		if (!isPartialIdHash(hashPart))
			return Success(IssueMissing);
		return switch query.searchIssueIds(location.path, location.databaseName, hashPart, global) {
			case Failure(message): Failure('failed to search issues: ${message}');
			case Success(ids):
				final matches = new Array<String>();
				var exactMatch = "";
				for (candidate in ids) {
					final candidateHash = StringTools.startsWith(candidate, prefix) ? candidate.substr(prefix.length) : candidate;
					if (candidate == input || candidateHash == hashPart)
						exactMatch = candidate;
					else if (StringTools.startsWith(candidateHash, hashPart))
						matches.push(candidate);
				}
				if (exactMatch != "") {
					query.issueSummary(location.path, location.databaseName, exactMatch, global);
				} else if (matches.length == 0) {
					Success(IssueMissing);
				} else {
					matches.sort(compareIssueIds);
					if (matches.length > 1)
						Failure('${AMBIGUOUS_ISSUE_ID}"${input}" matches ${matches.length} issues: [${matches.join(" ")}]\nUse more characters to disambiguate');
					else
						query.issueSummary(location.path, location.databaseName, matches[0], global);
				}
		};
	}

	static function compareIssueIds(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}

	static function isPartialIdHash(value:String):Bool {
		if (value == "" || value.indexOf(" ") >= 0)
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			final accepted = code >= 48 && code <= 57 || code >= 97 && code <= 122 || code >= 65 && code <= 90 || code == 45 || code == 46;
			if (!accepted)
				return false;
		}
		return true;
	}

	static function normalizedPrefix(prefix:String):String {
		return StringTools.endsWith(prefix, "-") ? prefix : prefix + "-";
	}

	static function configuredPrefixCandidate(id:String, prefix:String):String {
		return prefix == "" || id.indexOf("-") >= 0 ? id : normalizedPrefix(prefix) + id;
	}

	function resolveCurrentIssueId(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):String {
		final currentActor = actor.resolve(invocation.actor);
		for (status in [IssueStatus.InProgress, IssueStatus.OtherStatus("hooked")]) {
			switch query.assignedIssueId(location.path, location.databaseName, currentActor, status, invocation.global) {
				case Success(id) if (id != ""):
					return id;
				case Success(_) | Failure(_):
			}
		}
		return invocation.global ? "" : store.lastTouchedId(location.path);
	}

	/** Upstream formatShortIssue (cmd/bd/show_format.go:19-43) of one summary. */
	static function renderIssueShort(issue:IssueSummary, styles:TerminalStyles):String {
		return renderShortIssue(issue.id, issue.title, issueStatusWireValue(issue.status), issue.priority, issueTypeWireValue(issue.issueType), styles);
	}

	/**
		Upstream formatIssueMetadata's close reason, which it trims like Go's
		strings.TrimSpace first, so a reason of only spaces prints nothing.

		Why: a reason too long or too structured for one line is body text.
		What: the line `Close reason: <reason>` when fitsMetadataLine accepts it
		for the Markdown wrap width, else a CLOSE REASON section that renders the
		reason as Markdown without its final line feeds. How: the wrap width and
		the cell count come from the stdout terminal only when the reason exists.
	**/
	function renderCloseReason(closeReason:String, agentMode:Bool):HumanCloseReason {
		final reason = goTrimSpace(closeReason);
		if (reason == "")
			return NoCloseReason;
		final line = 'Close reason: ${reason}';
		if (fitsMetadataLine(line, markdownWrapWidth(agentMode, output.stdoutColumns()), output.displayWidth(line)))
			return CloseReasonLine(line);
		return CloseReasonSection('\n${terminalStyles().renderBold("CLOSE REASON")}\n${trimTrailingNewlines(output.renderMarkdown(reason))}\n');
	}

	/**
		Upstream's human show of one issue: header, metadata lines, sections.
		`agentMode` sets the Markdown wrap width that decides whether the close
		reason fits on a metadata line (see renderCloseReason). `localNode` reads
		this node's `node_id`, which the lease line compares with the node that
		granted the lease.
	**/
	function renderIssueHuman(issue:IssueDetails, agentMode:Bool, longMode:Bool, localNode:() -> String,
			mode:HumanShowMode = StandardShow):StoreResult<String> {
		final styles = terminalStyles();
		// Upstream formatIssueHeader (cmd/bd/show_format.go:48-80) styles each part of the header.
		final typeBadge = switch issue.issueType {
			case "epic": " " + styles.typeEpic.render("[EPIC]");
			case "bug": " " + styles.typeBug.render("[BUG]");
			case _: "";
		};
		final compactionMarker = switch issue.longFields.compactionLevel.wireValue() {
			case "1": " 🗜️";
			case "2": " 📦";
			case _: "";
		};
		var rendered = '${styles.renderStatusIcon(issue.status)} ${styles.renderAccent(issue.id)}${typeBadge} · ${issue.title}${compactionMarker}   '
			+ '[${styles.renderPriority(issue.priority)} · ${styles.statusStyle(issue.status).render(issue.status.toUpperCase())}]\n';
		// Upstream formatIssueMetadata (show_format.go:85-198) colors an epic or bug type and mutes its notes.
		final metadata = new Array<String>();
		if (issue.createdBy != "")
			metadata.push('Owner: ${issue.createdBy}');
		if (issue.assignee != "")
			metadata.push('Assignee: ${issue.assignee}');
		final typeText = switch issue.issueType {
			case "epic": styles.typeEpic.render("epic");
			case "bug": styles.typeBug.render("bug");
			case _: issue.issueType;
		};
		metadata.push('Type: ${typeText}');
		rendered += metadata.join(" · ") + "\n";
		final dates = ['Created: ${issue.createdAt.substr(0, 10)}'];
		if (issue.startedAt != "")
			dates.push('Started: ${issue.startedAt.substr(0, 10)}');
		dates.push('Updated: ${issue.updatedAt.substr(0, 10)}');
		if (issue.dueAt != "")
			dates.push('Due: ${issue.dueAt.substr(0, 10)}');
		if (issue.deferUntil != "")
			dates.push('Deferred: ${issue.deferUntil.substr(0, 10)}');
		rendered += dates.join(" · ") + "\n";
		final lease = leaseLine(issue.status, issue.longFields, localNode, LeaseClock.secondsFromNow);
		if (lease != null)
			rendered += styles.renderMuted(lease) + "\n";
		final closeReason = issue.status == "closed" ? renderCloseReason(issue.closeReason, agentMode) : NoCloseReason;
		switch closeReason {
			case CloseReasonLine(line):
				rendered += styles.renderMuted(line) + "\n";
			case CloseReasonSection(_) | NoCloseReason:
		}
		if (issue.externalRef != null && issue.externalRef != "")
			rendered += 'External: ${issue.externalRef}\n';
		if (issue.specId != "")
			rendered += 'Spec: ${issue.specId}\n';
		if (issue.longFields.ephemeral && issue.wispType != "")
			rendered += 'Wisp type: ${styles.renderMuted(issue.wispType)}\n';
		final savings = switch compactionSavingsLine(issue) {
			case Failure(message): return Failure(message);
			case Success(value): value;
		};
		if (savings != "")
			rendered += savings + "\n";
		switch closeReason {
			case CloseReasonSection(section):
				rendered += section;
			case CloseReasonLine(_) | NoCloseReason:
		}
		// Upstream's show (cmd/bd/show.go:174-237) and watch view (show_display.go:106-145) print each heading in bold.
		if (issue.description != "" || mode == StandardShow) {
			rendered += '\n${styles.renderBold("DESCRIPTION")}\n';
			rendered += issue.description == "" ? '  ${styles.renderMuted("(none)")}\n' : output.renderMarkdown(issue.description) + "\n";
		}
		if (issue.design != "")
			rendered += '\n${styles.renderBold("DESIGN")}\n' + output.renderMarkdown(issue.design) + "\n";
		if (issue.notes != "")
			rendered += '\n${styles.renderBold("NOTES")}\n' + output.renderMarkdown(issue.notes) + "\n";
		if (issue.acceptanceCriteria != "")
			rendered += '\n${styles.renderBold("ACCEPTANCE CRITERIA")}\n' + output.renderMarkdown(issue.acceptanceCriteria) + "\n";
		if (issue.labels.length > 0)
			rendered += '\n${styles.renderBold("LABELS:")} ' + issue.labels.join(", ") + "\n";
		if (mode == StandardShow) {
			final metadataLines = issue.metadata.renderHumanLines();
			if (metadataLines.length > 0)
				rendered += '\n${styles.renderBold("METADATA")}\n' + metadataLines.join("\n") + "\n";
		}
		rendered += renderHumanDependencySections(issue, styles);
		if (issue.comments.length > 0) {
			rendered += '\n${styles.renderBold("COMMENTS")}\n';
			for (comment in issue.comments) {
				rendered += '  ${styles.renderMuted(formatHumanTime(comment.createdAt))} ${comment.author}\n';
				final body = trimTrailingNewlines(output.renderMarkdown(comment.text));
				for (line in body.split("\n"))
					rendered += '    ${line}\n';
			}
		}
		if (longMode)
			rendered += renderIssueLongExtras(issue, styles);
		return Success(rendered + "\n");
	}

	/** Upstream formatIssueLongExtras (cmd/bd/show_format.go:357-477): each section under its bold heading. */
	static function renderIssueLongExtras(issue:IssueDetails, styles:TerminalStyles):String {
		final rare = issue.longFields;
		final details = new Array<String>();
		if (issue.closedAt != "")
			details.push('  Closed at: ${formatHumanTime(issue.closedAt)}');
		if (issue.closedBySession != "")
			details.push('  Closed by session: ${issue.closedBySession}');
		switch issue.estimatedMinutes {
			case IntegerAbsent:
			case IntegerPresent(value):
				details.push('  Estimated: ${value} minutes');
		}
		if (issue.sourceSystem != "")
			details.push('  Source system: ${issue.sourceSystem}');
		if (rare.sender != "")
			details.push('  Sender: ${rare.sender}');
		if (rare.ephemeral)
			details.push("  Ephemeral: yes");
		if (rare.pinned)
			details.push("  Pinned: yes");
		if (rare.template)
			details.push("  Template: yes");
		if (issue.moleculeType != "")
			details.push('  Mol type: ${issue.moleculeType}');
		if (rare.workType != "")
			details.push('  Work type: ${rare.workType}');
		final sections = new Array<String>();
		if (details.length > 0)
			sections.push(styles.renderBold("EXTENDED DETAILS") + "\n" + details.join("\n"));
		if (rare.compactionLevel.compare(0) > 0) {
			final compaction = ['  Level: ${rare.compactionLevel}'];
			if (rare.compactedAt != "")
				compaction.push('  Compacted at: ${formatHumanTime(rare.compactedAt)}');
			if (rare.compactedAtCommit != null)
				compaction.push('  Compacted at commit: ${rare.compactedAtCommit}');
			if (rare.originalSize.compare(0) > 0)
				compaction.push('  Original size: ${rare.originalSize} bytes');
			sections.push(styles.renderBold("COMPACTION") + "\n" + compaction.join("\n"));
		}
		final gate = new Array<String>();
		if (rare.awaitType != "")
			gate.push('  Await type: ${rare.awaitType}');
		if (rare.awaitId != "")
			gate.push('  Await ID: ${rare.awaitId}');
		if (rare.timeout != "")
			gate.push('  Timeout: ${rare.timeout}');
		if (rare.waiters.length > 0)
			gate.push('  Waiters: ${rare.waiters.join(", ")}');
		if (gate.length > 0)
			sections.push(styles.renderBold("GATE") + "\n" + gate.join("\n"));
		final source = new Array<String>();
		if (rare.sourceFormula != "")
			source.push('  Formula: ${rare.sourceFormula}');
		if (rare.sourceLocation != "")
			source.push('  Location: ${rare.sourceLocation}');
		if (source.length > 0)
			sections.push(styles.renderBold("SOURCE TRACING") + "\n" + source.join("\n"));
		if (rare.bondedFrom.length > 0) {
			final references = new Array<String>();
			for (reference in rare.bondedFrom)
				references.push('  ${reference.sourceId} (${reference.bondType})');
			sections.push(styles.renderBold("BONDED FROM") + "\n" + references.join("\n"));
		}
		final event = new Array<String>();
		if (rare.eventKind != "")
			event.push('  Kind: ${rare.eventKind}');
		if (rare.actor != "")
			event.push('  Actor: ${rare.actor}');
		if (rare.target != "")
			event.push('  Target: ${rare.target}');
		if (rare.payload != "")
			event.push('  Payload: ${rare.payload}');
		if (event.length > 0)
			sections.push(styles.renderBold("EVENT") + "\n" + event.join("\n"));
		return sections.length == 0 ? "" : "\n" + sections.join("\n\n") + "\n";
	}

	static function compactionSavingsLine(issue:IssueDetails):StoreResult<String> {
		return beadshx.store.NativeIssueMath.compactionSavingsLine({
			level: issue.longFields.compactionLevel,
			original: issue.longFields.originalSize,
			description: issue.description,
			design: issue.design,
			notes: issue.notes,
			acceptance: issue.acceptanceCriteria
		});
	}

	/** Upstream printDepSection and printRelatedSection (cmd/bd/show_format.go:251-275): bold headings, one line per edge. */
	static function renderHumanDependencySections(issue:IssueDetails, styles:TerminalStyles):String {
		final related = new Map<String, IssueDependency>();
		var rendered = renderHumanDependencyDirection(issue.dependencies, true, related, false, styles);
		rendered += renderHumanDependencyDirection(issue.dependents, false, related, issue.issueType == "epic", styles);
		final relatedIds = [for (id in related.keys()) id];
		relatedIds.sort(compareIssueIds);
		if (relatedIds.length > 0) {
			rendered += '\n${styles.renderBold("RELATED")}\n';
			for (id in relatedIds)
				rendered += renderDependencyLine("↔", related.get(id), styles) + "\n";
		}
		return rendered;
	}

	static function renderHumanDependencyDirection(dependencies:Array<IssueDependency>, outgoing:Bool, related:Map<String, IssueDependency>, epic:Bool,
			styles:TerminalStyles):String {
		final groups = new Array<HumanDependencyGroup>();
		for (dependency in dependencies) {
			final relation = humanDependencyRelation(dependency.dependencyType);
			if (relation.related) {
				related.set(dependency.id, dependency);
				continue;
			}
			var group:Null<HumanDependencyGroup> = null;
			for (candidate in groups) {
				if (candidate.relation.canonical == relation.canonical) {
					group = candidate;
					break;
				}
			}
			if (group == null) {
				group = {relation: relation, dependencies: []};
				groups.push(group);
			}
			group.dependencies.push(dependency);
		}
		groups.sort(compareHumanDependencyGroups);
		var rendered = "";
		for (group in groups) {
			final heading = outgoing ? group.relation.outgoingHeading : group.relation.incomingHeading;
			final glyph = outgoing ? group.relation.outgoingGlyph : group.relation.incomingGlyph;
			rendered += '\n${styles.renderBold(heading)}\n';
			for (dependency in group.dependencies)
				rendered += renderDependencyLine(glyph, dependency, styles) + "\n";
			if (!outgoing && epic && group.relation.canonical == "parent-child")
				rendered += renderEpicChildProgress(group.dependencies, styles);
		}
		return rendered;
	}

	/**
		Upstream formatDependencyLine (cmd/bd/show_format.go:224-249), without a
		line feed: the plain status icon, then a closed issue's ID, title and
		priority each muted, or another issue's ID in its status style, an
		(EPIC) or (BUG) badge, the title and the styled priority.
	**/
	static function renderDependencyLine(glyph:String, dependency:IssueDependency, styles:TerminalStyles):String {
		final icon = statusIcon(dependency.status);
		if (dependency.status == "closed")
			return
				'  ${glyph} ${icon} ${styles.renderMuted(dependency.id)}: ${styles.renderMuted(dependency.title)} ${styles.renderMuted('P${dependency.priority}')}';
		final notableType = switch dependency.issueType {
			case "epic": styles.typeEpic.render("(EPIC)") + " ";
			case "bug": styles.typeBug.render("(BUG)") + " ";
			case _: "";
		};
		return
			'  ${glyph} ${icon} ${styles.statusStyle(dependency.status).render(dependency.id)}: ${notableType}${dependency.title} ${styles.renderPriority(dependency.priority)}';
	}

	/** Upstream printEpicChildProgress (cmd/bd/show_format.go:277-296), with a pass or muted mark. */
	static function renderEpicChildProgress(children:Array<IssueDependency>, styles:TerminalStyles):String {
		var closed = 0;
		for (child in children)
			if (child.status == "closed")
				closed++;
		final percentage = Std.int(closed * 100 / children.length);
		return
			closed == children.length ? '  ${styles.renderPass("✓")} ${closed}/${children.length} complete (${percentage}%) — eligible for close\n' : '  ${styles.renderMuted("◐")} ${closed}/${children.length} complete (${percentage}%)\n';
	}

	static function compareHumanDependencyGroups(left:HumanDependencyGroup, right:HumanDependencyGroup):Int {
		if (left.relation.order != right.relation.order)
			return left.relation.order < right.relation.order ? -1 : 1;
		return compareIssueIds(left.relation.canonical, right.relation.canonical);
	}

	static function humanDependencyRelation(value:String):HumanDependencyRelation {
		return switch value {
			case "parent-child": dependencyRelation(value, "PARENT", "CHILDREN", "↑", "↳", 0);
			case "blocks": dependencyRelation(value, "DEPENDS ON", "BLOCKS", "→", "←", 1);
			case "conditional-blocks": dependencyRelation(value, "CONDITIONALLY DEPENDS ON", "CONDITIONALLY BLOCKS", "→", "←", 2);
			case "waits-for": dependencyRelation(value, "WAITS FOR", "AWAITED BY", "→", "←", 3);
			case "discovered-from": dependencyRelation(value, "DISCOVERED FROM", "DISCOVERED", "◊", "◊", 4);
			case "replies-to": dependencyRelation(value, "IN REPLY TO", "REPLIES", "→", "←", 5);
			case "duplicates": dependencyRelation(value, "DUPLICATE OF", "DUPLICATED BY", "→", "←", 6);
			case "supersedes": dependencyRelation(value, "SUPERSEDED BY", "SUPERSEDES", "→", "←", 7);
			case "authored-by": dependencyRelation(value, "AUTHORED BY", "AUTHORED", "→", "←", 8);
			case "assigned-to": dependencyRelation(value, "ASSIGNED TO", "ASSIGNED", "→", "←", 9);
			case "approved-by": dependencyRelation(value, "APPROVED BY", "APPROVED", "→", "←", 10);
			case "attests": dependencyRelation(value, "ATTESTS", "ATTESTED BY", "→", "←", 11);
			case "tracks": dependencyRelation(value, "TRACKS", "TRACKED BY", "→", "←", 12);
			case "until": dependencyRelation(value, "ACTIVE UNTIL", "KEEPS ACTIVE", "→", "←", 13);
			case "caused-by": dependencyRelation(value, "CAUSED BY", "CAUSED", "→", "←", 14);
			case "validates": dependencyRelation(value, "VALIDATES", "VALIDATED BY", "→", "←", 15);
			case "delegated-from": dependencyRelation(value, "DELEGATED FROM", "DELEGATED TO", "→", "←", 16);
			case "related" | "relates-to": {
					canonical: "related",
					outgoingHeading: "RELATED",
					incomingHeading: "RELATED",
					outgoingGlyph: "↔",
					incomingGlyph: "↔",
					order: 17,
					related: true
				};
			case _:
				final heading = value.toUpperCase();
				dependencyRelation(value, heading, heading + " (INBOUND)", "→", "←", 100);
		};
	}

	static function dependencyRelation(canonical:String, outgoingHeading:String, incomingHeading:String, outgoingGlyph:String, incomingGlyph:String,
			order:Int):HumanDependencyRelation {
		return {
			canonical: canonical,
			outgoingHeading: outgoingHeading,
			incomingHeading: incomingHeading,
			outgoingGlyph: outgoingGlyph,
			incomingGlyph: incomingGlyph,
			order: order,
			related: false
		};
	}

	static function formatHumanTime(value:String):String {
		return value.length < 16 ? value : value.substr(0, 10) + " " + value.substr(11, 5);
	}

	static function trimTrailingNewlines(value:String):String {
		var end = value.length;
		while (end > 0 && value.charAt(end - 1) == "\n")
			end--;
		return value.substr(0, end);
	}

	/**
		Upstream show --thread JSON: each message's `types.Issue` with the labels
		that GetIssue and GetIssuesByIDsInTx read
		(internal/storage/issueops/get_issue.go:50-54, dependencies.go:1065-1086).
	**/
	static function renderThreadJson(entries:Array<ThreadEntry>):StoreResult<String> {
		final lines = ["["];
		for (index in 0...entries.length) {
			final issue = entries[index].issue;
			final fields = switch renderIssueFields(issue, false, "    ", issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == entries.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	/**
		Upstream renderStale's JSON (cmd/bd/stale.go:59-64): the stale issues as
		types.Issue records, with the labels that its read returns. It replaces a
		nil result with an empty slice, so no stale issue prints `[]` on one line.
	**/
	static function renderRawIssuesJson(issues:Array<StaleIssue>):StoreResult<String> {
		if (issues.length == 0)
			return Success("[]\n");
		final lines = ["["];
		for (index in 0...issues.length) {
			final issue = issues[index];
			final fields = switch renderIssueFields(issue, false, "    ", issue.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == issues.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	/**
		The fields of one upstream `types.Issue` in struct order, with Go's
		`omitempty` rules (internal/types/types.go:19-190). Every JSON view
		that prints an issue record renders it here, and adds the fields of its
		own wrapper type after it.

		`labels` and `dependencies` are the Issue's own collections, which it
		prints between original_size and sender (types.go:134-136). A view whose
		wrapper declares its own labels or dependencies (IssueDetails) passes
		none, and prints them after the Issue fields instead. `sorted` is for a
		view that upstream round-trips through a map, which sorts the keys of
		each nested object: metadata and each dependency here, and the record's
		own fields at the caller.
	**/
	static function renderIssueFields(issue:FullIssueRecord, sorted:Bool = false, fieldIndent:String = "    ", ?labels:Array<String>,
			?dependencies:Array<IssueListDependency>):StoreResult<Array<String>> {
		final rare = issue.longFields;
		final fields = new Array<String>();
		fields.push('"id": ${Json.stringify(issue.id)}');
		fields.push('"title": ${Json.stringify(issue.title)}');
		if (issue.description != "")
			fields.push('"description": ${Json.stringify(issue.description)}');
		if (issue.design != "")
			fields.push('"design": ${Json.stringify(issue.design)}');
		if (issue.acceptanceCriteria != "")
			fields.push('"acceptance_criteria": ${Json.stringify(issue.acceptanceCriteria)}');
		if (issue.notes != "")
			fields.push('"notes": ${Json.stringify(issue.notes)}');
		if (issue.specId != "")
			fields.push('"spec_id": ${Json.stringify(issue.specId)}');
		if (issue.status != "")
			fields.push('"status": ${Json.stringify(issue.status)}');
		fields.push('"priority": ${issue.priority}');
		if (issue.issueType != "")
			fields.push('"issue_type": ${Json.stringify(issue.issueType)}');
		if (rare.isBlocked)
			fields.push('"is_blocked": true');
		if (issue.assignee != "")
			fields.push('"assignee": ${Json.stringify(issue.assignee)}');
		if (issue.owner != "")
			fields.push('"owner": ${Json.stringify(issue.owner)}');
		switch issue.estimatedMinutes {
			case IntegerAbsent:
			case IntegerPresent(value):
				fields.push('"estimated_minutes": ${value}');
		}
		fields.push('"created_at": ${Json.stringify(issue.createdAt)}');
		if (issue.createdBy != "")
			fields.push('"created_by": ${Json.stringify(issue.createdBy)}');
		fields.push('"updated_at": ${Json.stringify(issue.updatedAt)}');
		if (issue.startedAt != "")
			fields.push('"started_at": ${Json.stringify(issue.startedAt)}');
		if (issue.closedAt != "")
			fields.push('"closed_at": ${Json.stringify(issue.closedAt)}');
		if (issue.closeReason != "")
			fields.push('"close_reason": ${Json.stringify(issue.closeReason)}');
		if (issue.closedBySession != "")
			fields.push('"closed_by_session": ${Json.stringify(issue.closedBySession)}');
		if (rare.leaseExpiresAt != "")
			fields.push('"lease_expires_at": ${Json.stringify(rare.leaseExpiresAt)}');
		if (rare.heartbeatAt != "")
			fields.push('"heartbeat_at": ${Json.stringify(rare.heartbeatAt)}');
		if (rare.leaseGrantedNode != "")
			fields.push('"lease_granted_node": ${Json.stringify(rare.leaseGrantedNode)}');
		if (issue.dueAt != "")
			fields.push('"due_at": ${Json.stringify(issue.dueAt)}');
		if (issue.deferUntil != "")
			fields.push('"defer_until": ${Json.stringify(issue.deferUntil)}');
		if (issue.externalRef != null)
			fields.push('"external_ref": ${Json.stringify(issue.externalRef)}');
		if (issue.sourceSystem != "")
			fields.push('"source_system": ${Json.stringify(issue.sourceSystem)}');
		if (!issue.metadata.isAbsent()) {
			final metadata = switch (sorted ? issue.metadata.renderSortedIndented(fieldIndent, "  ") : issue.metadata.renderIndented(fieldIndent, "  ")) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"metadata": ${metadata}');
		}
		if (rare.compactionLevel.compare(0) != 0)
			fields.push('"compaction_level": ${rare.compactionLevel}');
		if (rare.compactedAt != "")
			fields.push('"compacted_at": ${Json.stringify(rare.compactedAt)}');
		if (rare.compactedAtCommit != null)
			fields.push('"compacted_at_commit": ${Json.stringify(rare.compactedAtCommit)}');
		if (rare.originalSize.compare(0) != 0)
			fields.push('"original_size": ${rare.originalSize}');
		if (labels != null && labels.length > 0)
			fields.push(renderRawStringArray("labels", labels, fieldIndent));
		if (dependencies != null && dependencies.length > 0)
			fields.push(renderListDependencies(dependencies, sorted, fieldIndent));
		if (rare.sender != "")
			fields.push('"sender": ${Json.stringify(rare.sender)}');
		if (rare.ephemeral)
			fields.push('"ephemeral": true');
		if (rare.noHistory)
			fields.push('"no_history": true');
		if (issue.wispType != "")
			fields.push('"wisp_type": ${Json.stringify(issue.wispType)}');
		if (rare.storageClass != "")
			fields.push('"storage_class": ${Json.stringify(rare.storageClass)}');
		if (rare.pinned)
			fields.push('"pinned": true');
		if (rare.template)
			fields.push('"is_template": true');
		if (rare.bondedFrom.length > 0)
			fields.push(renderRawBondedFrom(rare.bondedFrom, fieldIndent));
		if (rare.awaitType != "")
			fields.push('"await_type": ${Json.stringify(rare.awaitType)}');
		if (rare.awaitId != "")
			fields.push('"await_id": ${Json.stringify(rare.awaitId)}');
		if (rare.timeoutNanos.wireValue() != "0")
			fields.push('"timeout": ${rare.timeoutNanos.wireValue()}');
		if (rare.waiters.length > 0)
			fields.push(renderRawStringArray("waiters", rare.waiters, fieldIndent));
		if (rare.sourceFormula != "")
			fields.push('"source_formula": ${Json.stringify(rare.sourceFormula)}');
		if (rare.sourceLocation != "")
			fields.push('"source_location": ${Json.stringify(rare.sourceLocation)}');
		if (issue.moleculeType != "")
			fields.push('"mol_type": ${Json.stringify(issue.moleculeType)}');
		if (rare.workType != "")
			fields.push('"work_type": ${Json.stringify(rare.workType)}');
		if (rare.eventKind != "")
			fields.push('"event_kind": ${Json.stringify(rare.eventKind)}');
		if (rare.actor != "")
			fields.push('"actor": ${Json.stringify(rare.actor)}');
		if (rare.target != "")
			fields.push('"target": ${Json.stringify(rare.target)}');
		if (rare.payload != "")
			fields.push('"payload": ${Json.stringify(rare.payload)}');
		return Success(fields);
	}

	static function renderRawBondedFrom(references:Array<beadshx.store.IssueBondReference>, fieldIndent:String):String {
		final nestedIndent = fieldIndent + "  ";
		final valueIndent = nestedIndent + "  ";
		final lines = ['"bonded_from": ['];
		for (index in 0...references.length) {
			final reference = references[index];
			lines.push('${nestedIndent}{');
			lines.push('${valueIndent}"source_id": ${Json.stringify(reference.sourceId)},');
			final bondTypeSuffix = reference.bondPoint == "" ? "" : ",";
			lines.push('${valueIndent}"bond_type": ${Json.stringify(reference.bondType)}${bondTypeSuffix}');
			if (reference.bondPoint != "")
				lines.push('${valueIndent}"bond_point": ${Json.stringify(reference.bondPoint)}');
			lines.push(index == references.length - 1 ? '${nestedIndent}}' : '${nestedIndent}},');
		}
		lines.push('${fieldIndent}]');
		return lines.join("\n");
	}

	static function renderRawStringArray(name:String, values:Array<String>, fieldIndent:String):String {
		final lines = ['${Json.stringify(name)}: ['];
		for (index in 0...values.length) {
			final suffix = index == values.length - 1 ? "" : ",";
			lines.push('${fieldIndent}  ${Json.stringify(values[index])}${suffix}');
		}
		lines.push('${fieldIndent}]');
		return lines.join("\n");
	}

	/**
		Upstream show JSON: each issue's `types.IssueDetails` (internal/types/types.go:1146-1195).
		Its own labels, dependencies, dependents and comments replace the Issue
		fields of the same names, so they follow the Issue's last field.
	**/
	static function renderShowJson(issues:Array<IssueDetails>):StoreResult<String> {
		final lines = ["["];
		for (index in 0...issues.length) {
			final issue = issues[index];
			final fields = switch renderIssueFields(issue) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			if (issue.labels.length > 0) {
				final labelLines = ['"labels": ['];
				for (labelIndex in 0...issue.labels.length) {
					final suffix = labelIndex == issue.labels.length - 1 ? "" : ",";
					labelLines.push('      ${Json.stringify(issue.labels[labelIndex])}${suffix}');
				}
				labelLines.push("    ]");
				fields.push(labelLines.join("\n"));
			}
			if (issue.dependencies.length > 0) {
				final rendered = switch renderIssueRelations("dependencies", issue.dependencies) {
					case Failure(message): return Failure(message);
					case Success(value): value;
				};
				fields.push(rendered);
			}
			if (issue.dependents.length > 0) {
				final rendered = switch renderIssueRelations("dependents", issue.dependents) {
					case Failure(message): return Failure(message);
					case Success(value): value;
				};
				fields.push(rendered);
			}
			if (issue.comments.length > 0)
				fields.push(renderIssueComments(issue.comments));
			if (issue.parent != "")
				fields.push('"parent": ${Json.stringify(issue.parent)}');
			fields.push('"dependent_count": ${issue.dependentCount}');
			fields.push('"dependency_count": ${issue.dependencyCount}');
			fields.push('"comment_count": ${issue.commentCount.wireValue()}');
			if (issue.commentsOmitted)
				fields.push('"comments_omitted": true');
			switch issue.epicProgress {
				case NoEpicProgress:
				case HasEpicProgress(totalChildren, closedChildren, closeable):
					fields.push('"epic_total_children": ${totalChildren}');
					fields.push('"epic_closed_children": ${closedChildren}');
					fields.push('"epic_closeable": ${closeable}');
			}
			fields.push('"revision": ${issue.revision.wireValue()}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == issues.length - 1 ? "" : ",";
			lines.push('  }${suffix}');
		}
		lines.push("]");
		return Success(lines.join("\n") + "\n");
	}

	/** Show's dependencies or dependents: each a whole `types.IssueWithDependencyMetadata` (internal/types/types.go:1130-1133). */
	static function renderIssueRelations(fieldName:String, relations:Array<IssueDependency>):StoreResult<String> {
		final lines = ['${Json.stringify(fieldName)}: ['];
		for (index in 0...relations.length) {
			final dependency = relations[index];
			final fields = switch renderIssueFields(dependency, false, "        ", dependency.labels) {
				case Failure(message): return Failure(message);
				case Success(value): value;
			};
			fields.push('"dependency_type": ${Json.stringify(dependency.dependencyType)}');
			lines.push("      {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('        ${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == relations.length - 1 ? "" : ",";
			lines.push('      }${suffix}');
		}
		lines.push("    ]");
		return Success(lines.join("\n"));
	}

	static function renderIssueComments(comments:Array<IssueComment>):String {
		final lines = ['"comments": ['];
		for (index in 0...comments.length) {
			final comment = comments[index];
			lines.push("      {");
			lines.push('        "id": ${Json.stringify(comment.id)},');
			lines.push('        "issue_id": ${Json.stringify(comment.issueId)},');
			lines.push('        "author": ${Json.stringify(comment.author)},');
			lines.push('        "text": ${Json.stringify(comment.text)},');
			lines.push('        "created_at": ${Json.stringify(comment.createdAt)}');
			final suffix = index == comments.length - 1 ? "" : ",";
			lines.push('      }${suffix}');
		}
		lines.push("    ]");
		return lines.join("\n");
	}

	static function issueTypeWireValue(issueType:IssueType):String {
		return switch issueType {
			case Epic: "epic";
			case Bug: "bug";
			case OtherType(value): value;
		};
	}

	/** The stored text of a summary's status. */
	static function issueStatusWireValue(status:IssueStatus):String {
		return switch status {
			case Open: "open";
			case InProgress: "in_progress";
			case Blocked: "blocked";
			case Closed: "closed";
			case Deferred: "deferred";
			case Pinned: "pinned";
			case OtherStatus(value): value;
		};
	}

	/**
		Whether upstream's pre-run finds a database for the command, or else
		stops with "no beads database found" before its warnings and its
		--global and --database checks.

		Why: upstream's root pre-run (cmd/bd/main.go) looks for the database
		only when no --db or BEADS_DB path names it, and then a workspace
		without a database writes nothing. A --db value that names a database
		is no path: upstream clears it and looks as without --db.

		What: a database path finds what the workspace facade found. Otherwise
		there is none for an embedded workspace whose metadata.json names a
		missing store (`databaseMissing`), and none for a workspace without
		metadata.json or a legacy config.json where FindDatabasePath found no
		embeddeddolt or dolt directory, unless a remote host in
		BEADS_DOLT_SERVER_HOST or the dolt.host setting makes it a server
		workspace (configfile HostImpliesServerMode over the default config).

		How: it reads metadata.json and the layered config only for a
		workspace without a database path.
	**/
	static function findsDatabase(invocation:Invocation, location:WorkspaceLocation):Bool {
		if (location.databaseMissing)
			return false;
		if (databasePathSelected(invocation, location) || location.databasePath != "" || location.proxiedServer)
			return true;
		return switch readMetadataFields(location.path) {
			case MetadataAbsent: LayeredConfig.forWorkspace(location.path).hostImpliesServerMode();
			case MetadataFields(_) | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: true;
		};
	}

	/** Whether a --db or BEADS_DB path, not a --db value that names a database, selects the database (upstream's `dbPath`). */
	static function databasePathSelected(invocation:Invocation, location:WorkspaceLocation):Bool {
		return invocation.databasePath != "" && location.databaseName == "";
	}

	static function selectedDatabaseName(invocation:Invocation, location:WorkspaceLocation):String {
		return invocation.databaseName == "" ? location.databaseName : invocation.databaseName;
	}

	/** Opens the command's query session, as upstream's root pre-run opens the store. */
	function openIssueQuery(invocation:Invocation, location:WorkspaceLocation):StoreResult<IssueQueryPort> {
		final serverStore = opensServerStore(location);
		final opened = store.openIssueQuery(location.path, serverStore, selectedDatabaseName(invocation, location), location.proxiedServer, invocation.global);
		finishStoreOpen(opened.match(Success(_)));
		switch opened {
			case Success(_) if (!serverStore && !location.proxiedServer && !invocation.global):
				uncheckedStore = {beadsDir: location.path, databaseName: selectedDatabaseName(invocation, location)};
			case Success(_) | Failure(_):
		}
		return opened;
	}

	/**
		Runs the pending schema check of the command's embedded store before the
		command reports a failure: upstream's pre-run would have stopped at schema
		skew before its command body found that failure. After a read it costs
		nothing, as that read checked.
	**/
	function checkSchemaBeforeFailure():Void {
		final pending = uncheckedStore;
		if (pending == null)
			return;
		uncheckedStore = null;
		store.checkSchema(pending.beadsDir, pending.databaseName);
	}

	/**
		Whether upstream's pre-run opens a SQL server for the workspace:
		configfile IsDoltServerMode, from metadata.json and the layered config.
		An embeddeddolt directory left in the workspace does not change it.
	**/
	static function opensServerStore(location:WorkspaceLocation):Bool {
		final metadata = switch readMetadataFields(location.path) {
			case MetadataFields(fields): fields;
			case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: new Map<String, String>();
		};
		return LayeredConfig.forWorkspace(location.path).doltServerMode(metadataField(metadata, "dolt_mode"), metadataField(metadata, "dolt_server_host"));
	}

	function closeIssueQuery(query:IssueQueryPort, operationResult:Int):Int {
		return switch query.close() {
			case Success(_): operationResult;
			case Failure(message):
				if (operationResult == 0) runStoreFailure('closing query session: ${message}'); else {
					output.writeStderr('Error: closing query session: ${message}\n');
					operationResult;
				}
		};
	}

	/**
		The prefix `bd where` prints, as upstream's where takes it: config.yaml's
		issue-prefix, or else its issue_prefix, or else the stored issue_prefix.
	**/
	function wherePrefix(location:WorkspaceLocation):String {
		if (location.yamlPrefix != "")
			return location.yamlPrefix;
		// Upstream's where ignores a store that does not open, also for schema skew, and prints no prefix.
		return SchemaSkewBoundary.orElse(() -> storedIssuePrefix(location, ReadEmbedded), "");
	}

	/**
		The issue_prefix row of the workspace's embedded database.

		Why: only `where` without a config.yaml prefix and partial-ID lookup after
		an exact miss need it. Reading it for them alone, instead of during
		workspace discovery, saves a database open in every other command.

		What: "" when upstream's where would read no embedded database: without a
		database path, in a proxied workspace, when metadata.json does not load
		or names another backend, or when configfile IsDoltServerMode makes it a
		server workspace (BEADS_DOLT_SHARED_SERVER counts). The dolt.shared-server
		setting does not count for that check; `sharedServerSetting` says whether
		it stops the read. A failed read also gives "".

		How: it opens the database that GetDoltDatabase names, with `-` and `.`
		changed to `_`, without creating it, and keeps the value for the rest of
		the command.
	**/
	function storedIssuePrefix(location:WorkspaceLocation, sharedServerSetting:SharedServerSettingRead):String {
		if (location.databasePath == "" || location.proxiedServer)
			return "";
		final metadata = switch readMetadataFields(location.path) {
			case MetadataFields(fields): fields;
			case MetadataAbsent: new Map<String, String>();
			// checkWorkspaceMetadata stopped the command for a metadata.json that does not load.
			case MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: return "";
		};
		final backend = metadataField(metadata, "backend");
		if (backend != "" && backend != "dolt")
			return "";
		final config = LayeredConfig.forWorkspace(location.path);
		switch sharedServerSetting {
			case ReadEmbedded:
			case ReadNothing:
				if (config.sharedServerMode())
					return "";
		}
		if (config.doltServerMode(metadataField(metadata, "dolt_mode"), metadataField(metadata, "dolt_server_host")))
			return "";
		final variable = environmentValue("BEADS_DOLT_SERVER_DATABASE");
		final recorded = metadataField(metadata, "dolt_database");
		final configured = variable != "" ? variable : (recorded != "" ? recorded : DEFAULT_EMBEDDED_DATABASE);
		final database = StringTools.replace(StringTools.replace(configured, "-", "_"), ".", "_");
		if (!isEmbeddedDatabaseIdentifier(database) || !embeddedDatabaseExists(location.path, database))
			return "";
		final key = location.path + "\n" + database;
		final previous = storedPrefixRead;
		if (previous != null && previous.key == key)
			return previous.value;
		final value = switch store.configValue(location.path, database, "issue_prefix", false) {
			case Success(value): value;
			case Failure(_): "";
		};
		storedPrefixRead = {key: key, value: value};
		return value;
	}

	function renderWhereHuman(location:WorkspaceLocation, prefix:String, redirectedFrom:String):String {
		var rendered = location.path + "\n";
		if (redirectedFrom != "")
			rendered += '  (via redirect from ${redirectedFrom})\n';
		if (prefix != "")
			rendered += '  prefix: ${prefix}\n';
		if (location.databasePath != "")
			rendered += '  database: ${location.databasePath}\n';
		return rendered;
	}

	function renderWhereJson(location:WorkspaceLocation, prefix:String, redirectedFrom:String):String {
		final lines = ["{"];
		if (location.databasePath != "")
			lines.push('  "database_path": ${Json.stringify(location.databasePath)},');
		lines.push('  "path": ${Json.stringify(location.path)},');
		if (prefix != "")
			lines.push('  "prefix": ${Json.stringify(prefix)},');
		if (redirectedFrom != "")
			lines.push('  "redirected_from": ${Json.stringify(redirectedFrom)},');
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	/**
		Upstream's pre-run when it finds no database. Its hint names `bd doctor`
		when the command uses a SQL server (`sqlServer`).
	**/
	function runDatabaseNotFound(sqlServer:Bool):Int {
		output.writeStderr("Error: no beads database found\n");
		output.writeStderr('Hint: ${workspaceDiagHint(true, sqlServer)}\n');
		output.writeStderr("      or set BEADS_DIR to point to your .beads directory\n");
		return 1;
	}

	/**
		runDatabaseNotFound for a selected workspace without a database. That is
		no server workspace, so upstream uses a SQL server only in shared-server
		mode, from the config reloaded for the workspace.
	**/
	function runWorkspaceDatabaseNotFound(location:WorkspaceLocation):Int {
		return runDatabaseNotFound(LayeredConfig.forWorkspace(location.path).sharedServerMode());
	}

	/**
		Whether upstream's pre-run, in shared-server mode, goes on to the store
		open that reaches the shared server: the workspace has a database that
		upstream finds, or a --db or BEADS_DB path names the database. Otherwise
		upstream finds no database and writes nothing, also for a --db value
		that names a database.
	**/
	static function reachesSharedServer(invocation:Invocation, location:WorkspaceLocation):Bool {
		return findsDatabase(invocation, location) || databasePathSelected(invocation, location);
	}

	/**
		Upstream's workspace gates, which its pre-run takes for a command that
		opens a store once the config of the workspace it binds has loaded
		(cmd/bd/main.go:1332, see WorkspaceGate). The pre-run reaches them
		where it reaches the shared server (see reachesSharedServer). Each
		gate file that exists is locked shared until the process ends; this
		build creates no missing one. A warning prints on stderr unless
		--quiet. Returns upstream's refusal while a maintenance operation
		holds a gate, which comes before every later pre-run warning.
	**/
	function holdWorkspaceGates(invocation:Invocation, location:WorkspaceLocation, config:LayeredConfig):Null<String> {
		if (!reachesSharedServer(invocation, location))
			return null;
		return switch WorkspaceGate.takeShared(gateBeadsDir(invocation, location), config) {
			case GatesHeld:
				null;
			case GatesUngated(warning):
				if (!invocation.quiet)
					output.writeStderr(warning);
				null;
			case GatesBusy(message):
				message;
		};
	}

	/**
		Upstream's legacy-workspace guard after its second setup
		(cmd/bd/main.go:1319), for the second target of a redirect chain that
		a command which opens a store binds (see discoverStoreWorkspace), with
		`config` reloaded for that target. Upstream's first guard read the
		first target. Returns the refusal, or null when the command goes on.
		A metadata.json there that does not load makes FindDatabasePath find
		no database, so upstream never sets that target up.
	**/
	static function guardBoundTarget(location:WorkspaceLocation, initializations:Int, config:LayeredConfig):Null<String> {
		if (initializations < 2 || location.foundPath == null)
			return null;
		return switch LegacyUpgradeGuard.check(location.path, () -> config.sharedServerMode()) {
			case GuardRefused(error): error;
			case GuardPasses | GuardLoadFailed(_) | GuardUnknown: null;
		};
	}

	/**
		The `.beads` directory that upstream gates: resolveCommandBeadsDir of
		the database path that its pre-run binds (cmd/bd/main.go:1316). A
		--db path is that path as typed, so `--db .beads` names a `.beads`
		link itself. Upstream's last candidate for it is the directory that
		FindBeadsDir finds; the workspace that discovery selected for the
		path stands in for it, which costs no second discovery. A BEADS_DB
		path selects the workspace with its symbolic links resolved, or, for
		a missing file, the absolute directory of that file. Otherwise it is
		the directory of upstream's second setup (see boundSetupDirectory).
	**/
	function gateBeadsDir(invocation:Invocation, location:WorkspaceLocation):String {
		if (databasePathSelected(invocation, location))
			return switch invocation.databaseVariable {
				case VariablePath(_, _, _):
					WorkspaceEnvironment.storeSetupDirectory(invocation.databaseVariable, location.path);
				case NoVariable | UnsupportedPath(_):
					WorkspaceEnvironment.commandBeadsDir(invocation.databasePath, location.path);
			};
		return boundSetupDirectory(location);
	}

	/**
		runDatabaseNotFound without a workspace: upstream then uses a SQL server
		only in shared-server mode, from the process-start config. Its
		legacy-workspace guard can stop the command first.
	**/
	function runDatabaseNotFoundWithoutWorkspace(invocation:Invocation):Int {
		final stop = storeLookupsWithoutWorkspace(invocation);
		if (stop != null)
			return stop;
		return runDatabaseNotFound(LayeredConfig.atStartup().sharedServerMode());
	}

	/**
		The lookups of upstream's pre-run for a command that opens a store when
		it finds no workspace: GetRedirectInfo with preserveRedirectSourceDatabase
		(cmd/bd/main.go:1210), FindBeadsDir (:1214), and FindDatabasePath
		(:1250) after guardUndiscoveredLegacyWorkspace (:1242). Returns the
		exit code when that guard stops the command.
	**/
	function storeLookupsWithoutWorkspace(invocation:Invocation):Null<Int> {
		lookups.preserveSourceDatabase(lookups.getRedirectInfo());
		lookups.findBeadsDir();
		final stop = guardUndiscoveredWorkspace(invocation);
		if (stop != null)
			return stop;
		lookups.findDatabasePath();
		return null;
	}

	/**
		storeLookupsWithoutWorkspace's guard for a command that opens a store
		when a BEADS_DB path selects its workspace, which needs no workspace
		from the current directory. BEADS_DIR is unset then, so the guard's walk
		prints nothing: its lookups and refusal print only when it refuses,
		and the store selection runs the lookups otherwise (see loadStoreConfig).
	**/
	function guardUndiscoveredStoreWorkspace(invocation:Invocation):Null<Int> {
		final outcome = undiscoveredGuardOutcome();
		if (outcome.match(GuardPasses))
			return null;
		lookups.preserveSourceDatabase(lookups.getRedirectInfo());
		lookups.findBeadsDir();
		return reportGuardStop(invocation, outcome);
	}

	/**
		Upstream guardUndiscoveredLegacyWorkspace
		(cmd/bd/legacy_upgrade_guard.go:177-200), which its pre-run runs when
		it finds no workspace: for `where` (guardLegacyNoStoreCommand,
		cmd/bd/main.go:865) and for every command that opens a store without a
		--db path (:1242).

		Why: workspace discovery skips a `.beads` directory that holds only a
		SQLite `vc.db`, or only a legacy config.json, but upstream still
		refuses such historical workspaces without a write. What: upstream's
		guard (LegacyUpgradeGuard.check) for each directory of its walk (see
		RedirectLookups.undiscoveredBeadsDirs); the first that does not pass
		stops the command with `Error: <reason>` in every output mode. Its
		shared-server check reads the process-start config, as no setup ran.
		Returns the exit code when it stops the command.
	**/
	function guardUndiscoveredWorkspace(invocation:Invocation):Null<Int> {
		final outcome = undiscoveredGuardOutcome();
		return outcome.match(GuardPasses) ? null : reportGuardStop(invocation, outcome);
	}

	/** The outcome of upstream's guard for the first directory of guardUndiscoveredWorkspace's walk that does not pass. */
	function undiscoveredGuardOutcome():LegacyGuardOutcome {
		final sharedServer = () -> LayeredConfig.atStartup().sharedServerMode();
		for (beadsDir in lookups.undiscoveredBeadsDirs()) {
			final outcome = LegacyUpgradeGuard.check(beadsDir, sharedServer);
			if (!outcome.match(GuardPasses))
				return outcome;
		}
		return GuardPasses;
	}

	/**
		Prints how upstream's guard stops a command for a directory that no
		setup bound: its load error or its refusal, as text in every output
		mode. A legacy file whose decoding this build cannot tell is refused.
	**/
	function reportGuardStop(invocation:Invocation, outcome:LegacyGuardOutcome):Int {
		return switch outcome {
			case GuardLoadFailed(error):
				output.writeStderr(metadataLoadFailure(error));
				1;
			case GuardRefused(error):
				output.writeStderr('Error: ${error}\n');
				1;
			case GuardUnknown:
				runModeAwareFailure(invocation.output,
					'${commandPath(invocation.command)} is not available yet when .beads/metadata.json does not decode in this build');
			case GuardPasses:
				0;
		};
	}

	/**
		Upstream workspaceDiagHint: the advice after a missing workspace or
		database, with `bd where` (`includeWhere`) or without it. It also names
		`bd doctor` when the command uses a SQL server (`sqlServer`).
	**/
	static function workspaceDiagHint(includeWhere:Bool, sqlServer:Bool):String {
		final doctor = sqlServer ? "run 'bd doctor' to diagnose, " : "";
		return includeWhere ? "run 'bd where' to inspect the resolved workspace, "
			+ doctor
			+ "or 'bd init' to create a new database" : "check BEADS_DIR/worktree setup, "
			+ doctor
			+ "or run 'bd init' to create a new database";
	}

	function runStoreFailure(message:String):Int {
		checkSchemaBeforeFailure();
		output.writeStderr('Error: ${message}\n');
		return 1;
	}

	/**
		Upstream's pre-run when its store open stops at schema skew
		(cmd/bd/main.go): a database ahead of the binary prints the stale-binary
		block, or under JSON output `handleSchemaSkewJSON`'s error on stderr. Any
		other refusal is a plain open error in every mode, in the words of the
		open that strict read-only mode selects for the bound workspace.
	**/
	function runSchemaSkewRefusal(invocation:Invocation, refusal:SchemaSkewRefusal):Int {
		final location = boundWorkspace;
		switch refusal {
			case DatabaseAhead(database, binary):
				switch invocation.output {
					case Human:
						output.writeStderr(schemaSkewUserMessage(database, binary));
					case Json:
						output.writeStderr(renderSchemaSkewJson(refusal, database, binary, output.usesJsonEnvelope()));
				}
			case RemoteGateStopped(stop):
				writeRemoteGateStop(invocation, stop);
			case RemoteGateWouldWrite(write):
				writeRemoteGateWrite(invocation, write);
			// The native facade opens with upstream's strict read-only open, which refuses before the plain open's gate could run.
			case DatabaseBehind(version, _) if (location != null && opensWithGate(embeddedOpenIntent(invocation))):
				switch store.remoteMigrateGate(location.path, selectedDatabaseName(invocation, location), version) {
					case MigratesWithoutGate:
						output.writeStderr('Error: failed to open database: ${schemaSkewOpenError(refusal, false)}\n');
					case GateStops(stop) if (isReadOnlyCommand(invocation.command)):
						// Upstream warns and reads; the native facade cannot read a database behind the binary.
						SchemaSkewWarning.holdGateWarning(remoteGateReadOnlyWarning(stop));
						writeCandidateRefusal(invocation,
							'${commandPath(invocation.command)} is not available yet on a database behind the binary in this build');
					case GateStops(stop):
						writeRemoteGateStop(invocation, stop);
					case GateWrites(write):
						writeRemoteGateWrite(invocation, write);
					case GateReadFailed(error):
						output.writeStderr('Error: failed to open database: ${schemaSkewOpenError(RemoteGateFailed(error), false)}\n');
				}
			case DatabaseBehind(_, _) | ForwardCheckFailed(_) | BehindCheckFailed(_) | RemoteGateFailed(_):
				final config = location != null ? LayeredConfig.forWorkspace(location.path) : LayeredConfig.atStartup();
				output.writeStderr('Error: failed to open database: ${schemaSkewOpenError(refusal, strictReadonly(invocation, config))}\n');
		}
		return 1;
	}

	/**
		Upstream's pre-run at a remote-migrate gate stop (cmd/bd/main.go): the
		full gate message on stderr, or `handleRemoteMigrateGateJSON`'s error on
		stderr under JSON output.
	**/
	function writeRemoteGateStop(invocation:Invocation, stop:RemoteGateStop):Void {
		switch invocation.output {
			case Human:
				output.writeStderr(remoteGateUserMessage(stop));
			case Json:
				output.writeStderr(escapeJsonHtml(remoteGateJson(stop, output.usesJsonEnvelope())));
		}
	}

	/** Whether upstream's open runs the remote-migrate gate: an embedded open without strict read-only mode. */
	static function opensWithGate(intent:EmbeddedOpenIntent):Bool {
		return switch intent {
			case ReadOnlyCommandOpen | PlainOpen: true;
			case NoEmbeddedOpen | StrictReadOnlyOpen: false;
		};
	}

	/** Where upstream's gate lets it migrate or fast-forward, this build, which never writes, refuses. */
	function writeRemoteGateWrite(invocation:Invocation, write:RemoteGateWrite):Void {
		final action = switch write {
			case EscapeHatchMigration | FirstMoverMigration: "migrate";
			case FastForward: "fast-forward";
		};
		writeCandidateRefusal(invocation,
			'${commandPath(invocation.command)} is not available yet where upstream would ${action} a database with a Dolt remote in this build');
	}

	/** `runModeAwareFailure` without its schema check, for a refusal at the schema check itself. */
	function writeCandidateRefusal(invocation:Invocation, message:String):Void {
		switch invocation.output {
			case Human:
				output.writeStderr('Error: ${message}\n');
			case Json:
				writeJsonStdout('{\n  "error": ${Json.stringify(message)},\n  "schema_version": 1\n}\n');
		}
	}

	/**
		Upstream `handleSchemaSkewJSON`: `buildJSONError` with the escape hint,
		plus `schema_skew` in the outer object, so it stays outside `data` under
		BD_JSON_ENVELOPE=1. Go's encoder prints the map keys in byte order.
	**/
	static function renderSchemaSkewJson(refusal:SchemaSkewRefusal, database:Int, binary:Int, envelope:Bool):String {
		final error = '"error": ${Json.stringify(schemaSkewRefusalError(refusal))}';
		final hint = '"hint": ${Json.stringify(SCHEMA_SKEW_ESCAPE_HINT)}';
		final skew = '"schema_skew": {\n    "current_version": ${database},\n    "delta": ${database - binary},\n    "required_version": ${binary}\n  }';
		final document = envelope ? '{\n  "data": {\n    ${error},\n    ${hint}\n  },\n  ${skew},\n  "schema_version": 1\n}\n' : '{\n  ${error},\n  ${hint},\n  ${skew},\n  "schema_version": 1\n}\n';
		return escapeJsonHtml(document);
	}

	/**
		Reports what upstream's command body finds while it gathers its input,
		after the root pre-run opened the store: the first failed argument check
		(see DeferredCheck), then what upstream finds when it reads --max-rows
		and BEADS_MAX_ROWS, then ready's metadata filter and --sort checks. Each
		command calls this where upstream gathers its input. Returns the exit
		code when a check failed.
	**/
	function runDeferredChecks(invocation:Invocation):Null<Int> {
		final checkExit = reportDeferredCheck(invocation, invocation.deferredCheck);
		if (checkExit != null)
			return checkExit;
		final maxRowsExit = runMaxRowsCheck(invocation);
		if (maxRowsExit != null)
			return maxRowsExit;
		return reportDeferredCheck(invocation, invocation.readyFilterCheck);
	}

	/** Upstream resolveMaxRows: the BEADS_MAX_ROWS warning, or the error for a negative --max-rows. */
	function runMaxRowsCheck(invocation:Invocation):Null<Int> {
		if (invocation.listWarning != "")
			output.writeStderr(invocation.listWarning);
		return reportDeferredCheck(invocation, invocation.maxRowsCheck);
	}

	/** Prints a failed check as upstream does and returns its exit code, or returns null when it passed. */
	function reportDeferredCheck(invocation:Invocation, check:DeferredCheck):Null<Int> {
		return switch check {
			case ChecksPassed: null;
			case PlainCheckFailure(message): runStoreFailure(message);
			case OutputCheckFailure(message): runModeAwareFailure(invocation.output, message);
			case ExactCheckFailure(message, exitCode):
				checkSchemaBeforeFailure();
				output.writeStderr(message);
				exitCode;
		};
	}

	/**
		The workspace that upstream's pre-run binds for a command that opens a
		store.

		Why: without a --db path, upstream sets BEADS_DIR to the workspace that
		FindBeadsDir finds (cmd/bd/main.go:1214-1219) before FindDatabasePath
		looks for the database through it (:1250). When that workspace has a
		redirect of its own to a workspace with project files, FindBeadsDir
		ignored that chain with a warning, but FindDatabasePath follows that
		redirect (internal/beads/beads.go:552), and the pre-run binds the
		second target (:1316-1317): it reads that workspace's config and its
		database. With -C, BEADS_DIR names the -C workspace before FindBeadsDir
		runs, which then already finds the second target.
		What: the second target's workspace, which keeps the directory that
		discovery found as its `foundPath`, or else the workspace that
		discovery finds. Upstream binds the found directory itself when its
		metadata routes it as the database (:1223-1240, see
		WorkspaceEnvironment.storeChainTarget). How: one more native
		discovery, with BEADS_DIR naming the found directory, only when
		FollowRedirect follows that directory's redirect.
	**/
	function discoverStoreWorkspace(invocation:Invocation):WorkspaceDiscovery {
		final discovery = workspace.discover(invocation.directory, invocation.databasePath);
		final found = switch discovery {
			case Found(location): location;
			case NotFound | InvalidSelection(_): return discovery;
		};
		if (databasePathSelected(invocation, found)
			|| WorkspaceEnvironment.storeChainTarget({directory: invocation.directory, databasePath: invocation.databasePath}, found) == null)
			return discovery;
		return switch WorkspaceEnvironment.discoverWithBeadsDir(workspace, found.path) {
			// A metadata.json there that does not load makes upstream's FindDatabasePath find no database (findDatabaseInBeadsDir, beads.go:476-482).
			case Found(target) if (target.path != found.path && invocation.directory == "" && !metadataLoads(target.path)):
				Found(withoutDatabase(found));
			case Found(target) if (target.path != found.path):
				Found(relocated(target, target.path, found.databaseName, found.path));
			case Found(_) | NotFound | InvalidSelection(_):
				discovery;
		};
	}

	/** Whether configfile.Load reads the metadata.json, or legacy config.json, of `beadsDir`, finds none, or may read it. */
	static function metadataLoads(beadsDir:String):Bool {
		return !readMetadataFields(beadsDir).match(MetadataFieldsUndecodable(_));
	}

	/** `location` where upstream's pre-run finds no database, so the command reports that (see findsDatabase). */
	static function withoutDatabase(location:WorkspaceLocation):WorkspaceLocation {
		return {
			path: location.path,
			yamlPrefix: location.yamlPrefix,
			databasePath: location.databasePath,
			databaseName: location.databaseName,
			databaseMissing: true,
			proxiedServer: location.proxiedServer,
			listLimitConfigured: location.listLimitConfigured,
			listLimit: location.listLimit,
			foundPath: location.foundPath
		};
	}

	/**
		Upstream's pre-run, in shared-server mode, creates the shared server's
		directory under HOME (`~/.beads/shared-server/dolt`) and a
		circuit-breaker file under TMPDIR, then fails to reach the server. It
		does this before its --database check, and before any command body.
		This build cannot reach the shared server, and the native store open
		would create the same directory, so every command that opens a store
		refuses first, before it opens anything (see reachesSharedServer).
		Without a database upstream writes nothing: it finds no database and
		prints its hint, which then names `bd doctor`, so this goes on as
		without shared-server mode. Commands that load layered config take this
		refusal from their runWithLayeredConfig preflight instead.

		Upstream's setups for the workspace it takes come first (see
		loadSelectedConfig and storeInitializations): each prints the
		reinitialize warning for a config file that does not parse, and the
		first also the shared-server notice. Its warning for a workspace without
		metadata.json, or for a deprecated dolt_server_port, comes next, before
		the database selection checks. The warning for a missing metadata.json
		also comes before upstream reaches the shared server, so it comes
		before that refusal too. When upstream finds no database it stops
		before all of these warnings and checks, so this accepts the selection
		and the command reports the missing database (see findsDatabase).
	**/
	function validateStoreSelection(invocation:Invocation, location:WorkspaceLocation):DatabaseSelectionValidation {
		boundWorkspace = location;
		final initializations = storeInitializations(invocation, location);
		final config = loadStoreConfig(invocation, location, initializations, true);
		final targetRefusal = guardBoundTarget(location, initializations, config);
		if (targetRefusal != null)
			return PlainFailure(targetRefusal);
		final gateRefusal = holdWorkspaceGates(invocation, location, config);
		if (gateRefusal != null)
			return ModeAwareFailure(gateRefusal);
		final strictRefusal = proxiedStrictReadonlyRefusal(invocation, location, config);
		if (strictRefusal != null)
			return PlainFailure(strictRefusal);
		trackVersionLookup(invocation, location, config);
		final selection = validateSelectedStore(invocation, location, config);
		// Upstream's warnMultipleDatabases looks for the workspaces above the current directory once the store is open (:1688).
		// The checks above stand for an embedded open; a server-mode store opens natively later (see finishStoreOpen).
		if (selection.match(Accepted) && findsDatabase(invocation, location) && looksUpDatabasesAfterOpen(invocation, location)) {
			if (opensServerStore(location))
				databaseLookupsAfterOpen = true;
			else
				lookups.findAllDatabases();
		}
		return selection;
	}

	/**
		Whether upstream's pre-run reaches warnMultipleDatabases (cmd/bd/main.go:1688)
		once its store open succeeds. A proxied-server workspace returns before it
		(:1554-1577). Outside shared-server mode, which this build refuses earlier,
		a server-mode open with --global fails.
	**/
	function looksUpDatabasesAfterOpen(invocation:Invocation, location:WorkspaceLocation):Bool {
		return !location.proxiedServer && !(invocation.global && opensServerStore(location));
	}

	/**
		Runs the warnMultipleDatabases lookups that validateStoreSelection left for
		after a server-mode store's native open, when that open `succeeded`. A
		failed open stops upstream's pre-run before them.
	**/
	function finishStoreOpen(succeeded:Bool):Void {
		if (databaseLookupsAfterOpen && succeeded)
			lookups.findAllDatabases();
		databaseLookupsAfterOpen = false;
	}

	/**
		Upstream's refusal of strict read-only mode in a proxied-server
		workspace, after the workspace gates and before anything else opens
		(cmd/bd/main.go:1339-1341, backendSupportsStrictReadonly): the server
		that the proxy starts cannot guarantee that it writes nothing. Null
		without strict read-only mode or outside a proxied-server workspace.
	**/
	static function proxiedStrictReadonlyRefusal(invocation:Invocation, location:WorkspaceLocation, config:LayeredConfig):Null<String> {
		if (!location.proxiedServer || !strictReadonly(invocation, config))
			return null;
		return "strict readonly is unavailable for dolt proxied-server backend; refusing to open a store that cannot guarantee mutation-free access";
	}

	/**
		Upstream's trackBdVersion finds the workspace once more after the
		workspace gates (cmd/bd/main.go:1391), when the pre-run found a
		database and strict read-only mode is off; `config` is the one loaded
		for the workspace.
	**/
	function trackVersionLookup(invocation:Invocation, location:WorkspaceLocation, config:LayeredConfig):Void {
		if (findsDatabase(invocation, location) && !strictReadonly(invocation, config))
			lookups.findBeadsDir();
	}

	/** validateStoreSelection's checks after the workspace gates, with `config` loaded for the workspace. */
	function validateSelectedStore(invocation:Invocation, location:WorkspaceLocation, config:LayeredConfig):DatabaseSelectionValidation {
		final defaultDirectory = missingMetadataDirectory(invocation, location);
		if (config.sharedServerMode() && reachesSharedServer(invocation, location)) {
			warnMissingMetadata(defaultDirectory);
			return ModeAwareFailure(sharedServerRefusal(commandPath(invocation.command)));
		}
		if (!findsDatabase(invocation, location))
			return Accepted;
		warnStoreConfiguration(location, defaultDirectory, invocation.global);
		return switch validateDatabaseSelection(invocation, location) {
			case Accepted: validateOpenedDatabase(invocation, location, defaultDirectory);
			case refusal: refusal;
		};
	}

	/**
		Upstream's pre-run takes the embedded database `beads` for a selected
		workspace that has no metadata.json and no legacy config.json. Before it
		checks --global and --database it prints a warning that names the
		workspace directory, which this returns as upstream names it, or null
		when upstream takes another route. A remote host in BEADS_DOLT_SERVER_HOST
		or the dolt.host setting makes the workspace a server workspace instead.
		Without a --db path, a workspace where upstream finds no database stops
		earlier with "no beads database found". A --db path names the directory
		that upstream derives from the path as given, which can be relative.
		BEADS_DB never gets here: it selects only a workspace with metadata.json.
	**/
	function missingMetadataDirectory(invocation:Invocation, location:WorkspaceLocation):Null<String> {
		final pathSelected = databasePathSelected(invocation, location);
		if (location.proxiedServer || (!pathSelected && location.databasePath == ""))
			return null;
		switch readMetadataFields(location.path) {
			case MetadataAbsent:
			case MetadataFields(_) | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly:
				return null;
		}
		if (LayeredConfig.forWorkspace(location.path).hostImpliesServerMode())
			return null;
		return pathSelected ? WorkspaceEnvironment.databasePathBeadsDir(invocation.databasePath) : location.path;
	}

	/**
		Upstream's pre-run warnings before its --global and --database checks
		and its store open: the missing metadata.json warning when
		`defaultDirectory` names the workspace, or else the dolt_server_port
		deprecation warning that resolving the Dolt server port prints. Upstream
		resolves the port for a workspace whose metadata.json loads and names a
		Dolt backend, once it has found a database; in shared-server mode it
		reads the shared server's directory instead, which has no metadata.json.
		The native server open resolves the port itself and prints the warning,
		so this prints it only for an embedded or proxied workspace, and for a
		server workspace with `global`: outside shared-server mode the native
		open fails the --global check before it resolves the port.
	**/
	function warnStoreConfiguration(location:WorkspaceLocation, defaultDirectory:Null<String>, global:Bool):Void {
		if (defaultDirectory != null) {
			warnMissingMetadata(defaultDirectory);
			return;
		}
		if (location.databaseMissing)
			return;
		final metadata = switch readMetadataFields(location.path) {
			case MetadataFields(fields): fields;
			case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly: return;
		};
		final backend = metadataField(metadata, "backend");
		if (backend != "" && backend != "dolt")
			return;
		final config = LayeredConfig.forWorkspace(location.path);
		if (config.sharedServerMode())
			return;
		if (!location.proxiedServer
			&& !global
			&& config.doltServerMode(metadataField(metadata, "dolt_mode"), metadataField(metadata, "dolt_server_host")))
			return;
		if (DeprecatedServerPort.fromMetadata(location.path, metadata, config))
			output.writeStderr(DeprecatedServerPort.WARNING);
	}

	/** Upstream's warning for a workspace without metadata.json, when `defaultDirectory` (see missingMetadataDirectory) names it. */
	function warnMissingMetadata(defaultDirectory:Null<String>):Void {
		if (defaultDirectory != null)
			output.writeStderr(missingConfigurationWarning(defaultDirectory));
	}

	static function metadataField(fields:Map<String, String>, tag:String):String {
		final value = fields.get(tag);
		return value == null ? "" : value;
	}

	/** The embedded database checks after the database selection checks: the default database, or the one metadata.json selects. */
	function validateOpenedDatabase(invocation:Invocation, location:WorkspaceLocation, defaultDirectory:Null<String>):DatabaseSelectionValidation {
		return defaultDirectory == null ? validateEmbeddedDatabase(invocation, location) : validateDefaultDatabase(invocation, location, defaultDirectory);
	}

	/**
		Upstream's pre-run, after its warning for a workspace without
		metadata.json, opens `beads` with `CREATE DATABASE IF NOT EXISTS`, so it
		creates that database when the embedded store lacks it, which is a write.
		Dolt finds the database by its lower-case name, so a `BEADS` directory
		holds it. This build refuses before it opens anything. In strict
		read-only mode upstream fails with the open error instead, which this
		prints as upstream does while the store directory exists. --global fails
		first, in the native open as upstream.

		This build also refuses where its store open would differ from
		upstream's: a --db path for which upstream takes another directory, and
		BEADS_DOLT_SERVER_DATABASE naming another database or server mode from
		BEADS_DOLT_SERVER_MODE or the dolt.mode setting. Upstream ignores those
		without metadata.json, but the native read-only facade reads them: it
		takes server mode from configfile IsDoltServerMode over the default
		config, which matches dolt.mode to `server` with strings.EqualFold.
		Dolt looks the database name up in lower case (strings.ToLower), so
		`toLowerCase` is the comparison for BEADS_DOLT_SERVER_DATABASE. A
		dolt_database that a redirect kept in that variable does not count:
		upstream's open ignores it here too, so it goes before the native
		open reads it (RedirectLookups.dropPreservedServerDatabase).
	**/
	function validateDefaultDatabase(invocation:Invocation, location:WorkspaceLocation, defaultDirectory:String):DatabaseSelectionValidation {
		if (invocation.global)
			return Accepted;
		final path = commandPath(invocation.command);
		if (defaultDirectory != location.path)
			return ModeAwareFailure('${path} is not available yet when --db names this path in a workspace without .beads/metadata.json in this build');
		final config = LayeredConfig.forWorkspace(location.path);
		lookups.dropPreservedServerDatabase();
		final variable = environmentValue("BEADS_DOLT_SERVER_DATABASE");
		if (variable != "" && variable.toLowerCase() != DEFAULT_EMBEDDED_DATABASE)
			return ModeAwareFailure('${path} is not available yet when BEADS_DOLT_SERVER_DATABASE names a database other than "${DEFAULT_EMBEDDED_DATABASE}"'
				+ " and the workspace has no .beads/metadata.json in this build");
		if (config.doltServerMode("", ""))
			return ModeAwareFailure('${path} is not available yet when server mode is configured and the workspace has no .beads/metadata.json in this build');
		if (embeddedDatabaseExists(location.path, DEFAULT_EMBEDDED_DATABASE))
			return Accepted;
		final storeDirectory = switch ConfigProbes.statPath(Path.join([location.path, "embeddeddolt"])) {
			case StatDirectory: true;
			case StatMissing | StatNotDirectory | StatFailed(_): false;
		};
		final strict = strictReadonly(invocation, config);
		if (storeDirectory && strict)
			return storeOpenFailure(location.path, 'embeddeddolt: open db: Error 1049: database not found: ${DEFAULT_EMBEDDED_DATABASE}');
		// Without the store directory the strict open stops before Dolt starts.
		final storeError = strict ? ConfigProbes.embeddedStoreOpenError(RedirectSource.canonicalizePath(location.path)) : null;
		if (storeError != null && ConfigProbes.statPath(Path.join([location.path, "embeddeddolt"])).match(StatMissing))
			return PlainFailure('failed to open database: ${storeError}');
		return missingDatabaseOpen(path, location.path, DEFAULT_EMBEDDED_DATABASE);
	}

	/**
		Upstream's strict read-only mode: the --readonly value, or the
		`readonly` setting when the flag is absent (`Changed("readonly")`), so
		`--readonly=false` turns the setting off.
	**/
	static function strictReadonly(invocation:Invocation, config:LayeredConfig):Bool {
		final flag = invocation.readonly;
		return flag == null ? config.getBool("readonly") : flag;
	}

	/**
		Upstream's pre-run opens the embedded store with `CREATE DATABASE IF NOT
		EXISTS` for every command that opens a store, so a metadata.json that
		selects a database the store lacks makes upstream create it, which is a
		write. That happens for `null`, `{}` and an empty dolt_database, which
		select `beads`, and for any other missing name, also through
		BEADS_DOLT_SERVER_DATABASE. This build refuses those commands before it
		opens anything. Dolt finds a database by its lower-case name, so `TEST`
		opens `test` without a write and runs as usual, and so does a selection
		that falls back to an existing `beads`.

		In strict read-only mode (--readonly, or the `readonly` setting when the
		flag is absent) upstream opens the store without the create and fails
		with the open error, which this prints as upstream does. Where the
		create itself fails, as for a directory or a file named like the
		database, this prints upstream's error too (missingDatabaseRefusal).

		Without a --db path, upstream keeps the dolt_database of the workspace
		that GetRedirectInfo names when its redirect is followed: it sets
		BEADS_DOLT_SERVER_DATABASE, which every later store open reads. When
		that sets none, the setup of a found directory whose own redirect
		upstream follows keeps that directory's dolt_database (see
		discoverStoreWorkspace). The setups (loadStoreConfig) did the same
		before this runs (RedirectLookups.preserveSourceDatabase), so this,
		the readers and the native facade take that database.

		Upstream refuses a name that is not an identifier before it reads or
		creates anything, and so does this, with upstream's words: those of its
		schema initialization for a plain open, or of its strict read-only open.

		Upstream finds the database at the data directory that
		BEADS_DOLT_DATA_DIR or dolt_data_dir names when `.beads/embeddeddolt`
		is missing, but its embedded open still uses `.beads/embeddeddolt`.
		A plain open then creates that directory and the database, which this
		build refuses. A strict read-only open fails after its identifier
		check, with the error that this prints as upstream does
		(ConfigProbes.embeddedStoreOpenError). When a file takes the place of
		that directory, both opens fail before they write, and this prints
		their errors (ConfigProbes.embeddedStoreCreateError for a plain open).
	**/
	function validateEmbeddedDatabase(invocation:Invocation, location:WorkspaceLocation):DatabaseSelectionValidation {
		if (invocation.global || location.proxiedServer)
			return Accepted;
		// The workspace facade names .beads/embeddeddolt only for a workspace that upstream opens embedded and that has that directory.
		final storeNamed = Path.withoutDirectory(location.databasePath) == "embeddeddolt";
		final storeError = storeNamed ? null : ConfigProbes.embeddedStoreOpenError(location.path);
		if (!storeNamed && (storeError == null || opensServerStore(location)))
			return Accepted;
		switch readMetadataFields(location.path) {
			case MetadataFields(_):
			case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly:
				return Accepted;
		}
		final path = commandPath(invocation.command);
		final selected = resolveEmbeddedDatabaseName(location.path, "");
		final strict = strictReadonly(invocation, LayeredConfig.forWorkspace(location.path));
		if (storeError != null && !strict) {
			// A plain open that cannot create the directory, as for a file of that name, fails before it writes.
			final createError = ConfigProbes.embeddedStoreCreateError(location.path);
			if (createError != null)
				return PlainFailure('failed to open database: ${createError}');
			return ModeAwareFailure('${path} is not available yet for an embedded workspace without .beads/embeddeddolt in this build');
		}
		if (!isEmbeddedDatabaseIdentifier(selected))
			return PlainFailure('failed to open database: ${InvalidDatabaseName.error(selected, strict ? ReadOnlyOpenName : InitSchemaName)}');
		if (storeError != null)
			return PlainFailure('failed to open database: ${storeError}');
		if (embeddedDatabaseExists(location.path, selected))
			return Accepted;
		if (strict)
			return storeOpenFailure(location.path, 'embeddeddolt: open db: Error 1049: database not found: ${selected}');
		return missingDatabaseOpen(path, location.path, selected);
	}

	/**
		missingDatabaseRefusal, with Dolt's warnings for the store's in-progress
		directories (see storeOpenFailure) when upstream's open fails there
		without a write.
	**/
	function missingDatabaseOpen(path:String, beadsDir:String, name:String):DatabaseSelectionValidation {
		return switch missingDatabaseRefusal(path, beadsDir, name) {
			case PlainFailure(message): storeOpenFailure(beadsDir, message);
			case refusal: refusal;
		};
	}

	/**
		Upstream's failed open of the embedded store in `beadsDir`, with the
		error `message` after `failed to open database: `. Dolt first warns on
		stderr for each in-progress database directory that it skips, through
		logrus's text format with the time of the open.
	**/
	function storeOpenFailure(beadsDir:String, message:String):DatabaseSelectionValidation {
		final warnings = DoltStoreOpen.inProgressWarnings(beadsDir);
		if (warnings != "")
			output.writeStderr(warnings);
		return PlainFailure(StringTools.startsWith(message, "failed to open database: ") ? message : 'failed to open database: ${message}');
	}

	/**
		Upstream's plain open of the database `name`, which the embedded store
		lacks, runs `CREATE DATABASE IF NOT EXISTS`. Dolt first checks the path
		named like the database: for a directory that holds no database it
		creates nothing, and the `USE` that follows fails; for a file, and for a
		directory that a create left unfinished, it refuses to create. These
		fail without a write, and this prints upstream's error. Otherwise
		upstream creates the database, which this build refuses.
	**/
	static function missingDatabaseRefusal(path:String, beadsDir:String, name:String):DatabaseSelectionValidation {
		return switch missingDatabaseEntry(beadsDir, name) {
			case EntryDirectory:
				PlainFailure('failed to open database: embeddeddolt: init schema: embeddeddolt: switching to database: Error 1049: database not found: ${name}');
			case EntryFile:
				PlainFailure('failed to open database: embeddeddolt: init schema: embeddeddolt: creating database: Error 1105: cannot create DB, file exists at ${name}');
			case EntryIncomplete:
				PlainFailure('failed to open database: embeddeddolt: init schema: embeddeddolt: creating database: Error 1105: cannot create database ${name}: '
					+ "incomplete database directory from an interrupted create already exists; remove the directory and try again");
			case EntryAbsent:
				ModeAwareFailure('${path} is not available yet when the embedded store has no database named "${name}" in this build');
		};
	}

	/** Upstream's `dbPath` before its redirect check: a --db flag path; a BEADS_DB or BD_DB path is not one yet. */
	static function databaseFlagSelectsPath(invocation:Invocation):Bool {
		return switch invocation.databaseVariable {
			case VariablePath(_, _, _): false;
			case NoVariable | UnsupportedPath(_): invocation.databasePath != "";
		};
	}

	function validateDatabaseSelection(invocation:Invocation, location:WorkspaceLocation):DatabaseSelectionValidation {
		var selectedName = location.databaseName;
		if (invocation.databaseName != "") {
			if (selectedName != "" && selectedName != invocation.databaseName)
				return PlainFailure('conflicting database selection: --db="${selectedName}" vs --database="${invocation.databaseName}"');
			selectedName = invocation.databaseName;
		}
		if (selectedName == "")
			return Accepted;
		if (location.proxiedServer)
			return Accepted;
		return ModeAwareFailure("--database (or a --db value naming a database) is only supported in proxied-server mode");
	}

	function runModeAwareFailure(mode:OutputMode, message:String):Int {
		checkSchemaBeforeFailure();
		switch mode {
			case Human:
				output.writeStderr('Error: ${message}\n');
			case Json:
				writeJsonStdout('{\n  "error": ${Json.stringify(message)},\n  "schema_version": 1\n}\n');
		}
		return 1;
	}

	function renderInfoHuman(snapshot:InfoSnapshot, databasePath:String, includeSchema:Bool):String {
		var rendered = "\nBeads Database Information\n" + "===========================\n" + 'Database: ${databasePath}\n' + 'Mode: ${snapshot.mode}\n'
			+ '\nIssue Count: ${snapshot.issueCount}\n';
		if (includeSchema) {
			rendered += "\nSchema Information:\n";
			rendered += "  Tables: [issues dependencies labels config metadata]\n";
			rendered += '  Schema Version: ${snapshot.schemaVersion}\n';
			final detectedPrefix = extractPrefix(snapshot.sampleIssueIds);
			if (detectedPrefix != "")
				rendered += '  Detected Prefix: ${detectedPrefix}\n';
			if (snapshot.sampleIssueIds.length > 0)
				rendered += '  Sample Issues: [${snapshot.sampleIssueIds.join(" ")}]\n';
		}
		// Upstream renderInfo (cmd/bd/info.go:175-178) then warns about missing or outdated git hooks.
		final warning = hookWarnings(gitHookStatuses(ConfigProbes.gitHooksDirectory()));
		if (warning != "")
			rendered += '\n${warning}\n';
		return rendered + "\n";
	}

	function renderInfoJson(snapshot:InfoSnapshot, databasePath:String, includeSchema:Bool):String {
		final lines = new Array<String>();
		lines.push("{");
		if (snapshot.config.length > 0) {
			lines.push('  "config": {');
			for (index in 0...snapshot.config.length) {
				final entry = snapshot.config[index];
				final suffix = index + 1 == snapshot.config.length ? "" : ",";
				lines.push('    ${Json.stringify(entry.key)}: ${Json.stringify(entry.value)}${suffix}');
			}
			lines.push("  },");
		}
		lines.push('  "database_path": ${Json.stringify(databasePath)},');
		lines.push('  "issue_count": ${snapshot.issueCount},');
		lines.push('  "mode": ${Json.stringify(snapshot.mode)},');
		if (includeSchema) {
			lines.push('  "schema": {');
			lines.push('    "config": {');
			if (snapshot.issuePrefix != "")
				lines.push('      "issue_prefix": ${Json.stringify(snapshot.issuePrefix)}');
			lines.push("    },");
			lines.push('    "detected_prefix": ${Json.stringify(extractPrefix(snapshot.sampleIssueIds))},');
			lines.push('    "sample_issue_ids": [');
			for (index in 0...snapshot.sampleIssueIds.length) {
				final suffix = index + 1 == snapshot.sampleIssueIds.length ? "" : ",";
				lines.push('      ${Json.stringify(snapshot.sampleIssueIds[index])}${suffix}');
			}
			lines.push("    ],");
			lines.push('    "schema_version": ${Json.stringify(snapshot.schemaVersion)},');
			lines.push('    "tables": [');
			for (index in 0...schemaTables.length) {
				final suffix = index + 1 == schemaTables.length ? "" : ",";
				lines.push('      ${Json.stringify(schemaTables[index])}${suffix}');
			}
			lines.push("    ]");
			lines.push("  },");
		}
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	function extractPrefix(issueIds:Array<String>):String {
		if (issueIds.length == 0)
			return "";
		final issueId = issueIds[0];
		final lastHyphen = issueId.lastIndexOf("-");
		if (lastHyphen <= 0)
			return "";
		final suffix = issueId.substr(lastHyphen + 1);
		final numericPart = suffix.split(".")[0];
		if (Std.parseInt(numericPart) != null)
			return issueId.substr(0, lastHyphen);
		return issueId.split("-")[0];
	}

	static final schemaTables = ["issues", "dependencies", "labels", "config", "metadata"];

	function renderPing(mode:OutputMode, snapshot:PingSnapshot):Void {
		switch mode {
			case Human:
				// Upstream's ping (cmd/bd/ping.go:81).
				output.writeStdout('${terminalStyles().renderPass("✓")} bd ping: ok (${snapshot.totalMs}ms)\n');
			case Json:
				final document:PingDocument = {
					schema_version: 1,
					status: "ok",
					resolve_ms: snapshot.resolveMs,
					store_ms: snapshot.storeMs,
					query_ms: snapshot.queryMs,
					total_ms: snapshot.totalMs
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
		}
	}

	function renderStatus(mode:OutputMode, snapshot:StatusSnapshot):Void {
		switch mode {
			case Json:
				if (!snapshot.blockedAvailable) {
					final summary:SkippedStatusSummaryDocument = {
						total_issues: snapshot.totalIssues,
						open_issues: snapshot.openIssues,
						in_progress_issues: snapshot.inProgressIssues,
						closed_issues: snapshot.closedIssues,
						blocked_issues: null,
						deferred_issues: snapshot.deferredIssues,
						ready_issues: null,
						pinned_issues: snapshot.pinnedIssues,
						epics_eligible_for_closure: snapshot.epicsEligibleForClosure,
						average_lead_time_hours: snapshot.averageLeadTime
					};
					final document:SkippedStatusDocument = {
						schema_version: 1,
						summary: summary,
						blocked_count_skipped: true
					};
					writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				} else {
					final summary:StatusSummaryDocument = {
						total_issues: snapshot.totalIssues,
						open_issues: snapshot.openIssues,
						in_progress_issues: snapshot.inProgressIssues,
						closed_issues: snapshot.closedIssues,
						blocked_issues: snapshot.blockedIssues,
						deferred_issues: snapshot.deferredIssues,
						ready_issues: snapshot.readyIssues,
						pinned_issues: snapshot.pinnedIssues,
						epics_eligible_for_closure: snapshot.epicsEligibleForClosure,
						average_lead_time_hours: snapshot.averageLeadTime
					};
					final document:StatusDocument = {schema_version: 1, summary: summary};
					writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				}
			case Human:
				output.writeStdout(renderStatusHuman(snapshot));
		}
	}

	/**
		Upstream's status view (cmd/bd/status.go:135-175): open, ready and closable
		epic counts in the pass style, in-progress in the warning style, a blocked
		count above zero in the fail style, and a skipped count muted.
	**/
	function renderStatusHuman(snapshot:StatusSnapshot):String {
		final styles = terminalStyles();
		final blocked = !snapshot.blockedAvailable ? styles.renderMuted("(skipped)") : snapshot.blockedIssues > 0 ? styles.renderFail(Std.string(snapshot.blockedIssues)) : Std.string(snapshot.blockedIssues);
		final ready = snapshot.readyAvailable ? styles.renderPass(Std.string(snapshot.readyIssues)) : styles.renderMuted("(skipped)");
		final lines = [
			"",
			'${styles.renderAccent("📊")} Issue Database Status',
			"",
			"Summary:",
			'  Total Issues:           ${snapshot.totalIssues}',
			'  Open:                   ${styles.renderPass(Std.string(snapshot.openIssues))}',
			'  In Progress:            ${styles.renderWarn(Std.string(snapshot.inProgressIssues))}',
			'  Blocked:                ${blocked}',
			'  Closed:                 ${snapshot.closedIssues}',
			'  Ready to Work:          ${ready}'
		];
		if (snapshot.pinnedIssues > 0 || snapshot.epicsEligibleForClosure > 0 || snapshot.averageLeadTime > 0) {
			lines.push("");
			lines.push("Extended:");
			if (snapshot.pinnedIssues > 0)
				lines.push('  Pinned:                 ${snapshot.pinnedIssues}');
			if (snapshot.epicsEligibleForClosure > 0)
				lines.push('  Epics Ready to Close:   ${styles.renderPass(Std.string(snapshot.epicsEligibleForClosure))}');
			if (snapshot.averageLeadTime > 0)
				lines.push('  Avg Lead Time:          ${snapshot.averageLeadTime} hours');
		}
		lines.push("");
		lines.push("For more details, use 'bd list' to see individual issues.");
		lines.push("");
		return lines.join("\n") + "\n";
	}

	function rootHelp():String {
		return "Issues chained together like beads. A lightweight issue tracker with first-class dependency support.\n\n"
			+ "Usage:\n  bdhx [flags]\n  bdhx [command]\n\n"
			+ "Read-only commands:\n"
			+ "  children          List child beads of a parent\n"
			+ "  count             Count issues matching filters\n"
			+ "  dep               Inspect dependency edges\n"
			+ "  info              Show database information\n"
			+ "  list              List issues\n"
			+ "  orphans           Identify orphaned issues (referenced in commits but still open)\n"
			+ "  ping              Check database connectivity\n"
			+ "  ready             Show ready work (open, no active blockers)\n"
			+ "  query             Query issues using a simple query language\n"
			+ "  search            Search issues by text query\n"
			+ "  show              Show issue details (compact mode available)\n"
			+ "  stale             Show stale issues (not updated recently)\n"
			+ "  status            Show issue database overview and statistics\n"
			+ "  version           Print version information\n"
			+ "  where             Show active beads location\n\n"
			+ "Flags:\n"
			+ "      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)\n"
			+ "      --cpu-profile               Generate CPU profile for performance analysis\n"
			+
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)\n"
			+
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)\n"
			+ "  -C, --directory string          Change to this directory before running the command (like git -C)\n"
			+
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit\n"
			+ "      --global                    Use the global shared-server database (beads_global)\n"
			+ "  -h, --help                      help for bdhx\n"
			+ "      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)\n"
			+ "      --json                      Output in JSON format\n"
			+ "      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)\n"
			+ "      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)\n"
			+ "  -q, --quiet                     Suppress non-essential output (errors only)\n"
			+ "      --readonly                  Read-only mode: block write operations (for worker sandboxes)\n"
			+ "      --sandbox                   Sandbox mode: disables Dolt auto-push\n"
			+ "  -v, --verbose                   Enable verbose/debug output\n"
			+ "  -V, --version                   Print version information\n";
	}

	function commandHelp(command:Command):String {
		return switch command {
			case RootHelp: rootHelp();
			case Version: basicCommandHelp("Print version information", "version", "");
			case Where:
				basicCommandHelp("Show the active Beads workspace and database paths.", "where", "");
			case Ping:
				basicCommandHelp("Check that BeadsHX can open and query the active database.", "ping", "");
			case Info:
				basicCommandHelp("Show information about the active database.", "info",
					"      --schema      Include schema information in output\n" + "      --thanks      Show thank you page for contributors\n" +
					"      --whats-new   Show agent-relevant changes from recent versions\n");
			case Status:
				"Show a summary of issue counts and ready work.\n\n"
				+ "Usage:\n  bdhx status [flags]\n\nAliases:\n  status, stats\n\nFlags:\n"
				+ "      --all           Show all issues (default behavior)\n"
				+ "      --assigned      Show issues assigned to the selected actor\n"
				+ "  -h, --help          help for status\n"
				+ "      --no-activity   Skip activity output\n"
				+ "      --no-blocked    Skip blocked and ready counts\n\n"
				+ supportedGlobalFlags();
			case Count: countHelp();
			case Ready: readyHelp();
			case Search: searchHelp();
			case Query: queryHelp();
			case Stale: staleHelp();
			case Orphans: orphansHelp();
			case Children: childrenHelp();
			case DepList: depListHelp();
			case DepCycles: basicCommandHelp("Detect dependency cycles", "dep cycles", "");
			case DepTree: depTreeHelp();
			case GraphCheck: basicCommandHelp("Check dependency graph integrity", "graph check", "");
			case Graph: graphHelp();
			case Blocked: basicCommandHelp("Show blocked issues", "blocked", "      --parent string   Filter to descendants of this bead/epic\n");
			case Comments: commentsHelp();
			case History: historyHelp();
			case Events: eventsHelp(upstreamGlobalFlags());
			case EventsTail: eventsTailHelp(upstreamGlobalFlags());
			case EventsExport: eventsExportHelp(upstreamGlobalFlags());
			case Types: basicCommandHelp("List valid issue types", "types", "      --sections   Show required sections for each issue type\n");
			case Statuses: basicCommandHelp("List valid issue statuses", "statuses", "");
			case Label: labelHelp();
			case Config: configHelp(upstreamGlobalFlags());
			case ConfigGet: configSubcommandHelp("Get a configuration value", "get <key>", "get", upstreamGlobalFlags());
			case ConfigList: configSubcommandHelp("List all configuration", "list", "list", upstreamGlobalFlags());
			case ConfigShow: configShowHelp(upstreamGlobalFlags());
			case ConfigValidate: configValidateHelp(upstreamGlobalFlags());
			case ConfigDrift: configDriftHelp(upstreamGlobalFlags());
			case LabelList: labelSubcommandHelp("List labels for an issue", "list [issue-id]", "list");
			case LabelListAll: labelSubcommandHelp("List all unique labels in the database", "list-all", "list-all");
			case List: listHelp();
			case Show: showHelp();
			case Snapshot: snapshotHelp();
		};
	}

	function historyHelp():String {
		return [
			"Show the complete version history of an issue, including all commits",
			"where the issue was modified.",
			"",
			"Examples:",
			"  bd history bd-123           # Show all history for issue bd-123",
			"  bd history bd-123 --limit 5 # Show last 5 changes",
			"  bd history bd-123 --events  # Show database audit events",
			"",
			"Usage:",
			"  bd history <id> [flags]",
			"",
			"Flags:",
			"      --events      Show database audit events instead of commit snapshots",
			"  -h, --help        help for history",
			"      --limit int   Limit number of history entries (0 = all)",
			""
		].join("\n") + "\n" + upstreamGlobalFlags();
	}

	function commentsHelp():String {
		return [
			"View or manage comments on an issue.",
			"",
			"Examples:",
			"  # List all comments on an issue (issue id is required — there is no \"comments list\")",
			"  bd comments bd-123",
			"",
			"  # List comments in JSON format",
			"  bd comments bd-123 --json",
			"",
			"  # Add a comment",
			"  bd comments add bd-123 \"This is a comment\"",
			"",
			"  # Add a comment from a file",
			"  bd comments add bd-123 -f notes.txt",
			"",
			"Usage:",
			"  bd comments [issue-id] [flags]",
			"  bd comments [command]",
			"",
			"Available Commands:",
			"  add         Add a comment to an issue",
			"  list        Invalid — use bd comments <issue-id> to list comments",
			"",
			"Flags:",
			"  -h, --help         help for comments",
			"      --local-time   Show timestamps in local time instead of UTC",
			""
		].join("\n")
			+ "\n"
			+ upstreamGlobalFlags()
			+ "\nUse \"bd comments [command] --help\" for more information about a command.\n";
	}

	function labelHelp():String {
		return [
			"Manage issue labels",
			"",
			"Usage:",
			"  bd label [command]",
			"",
			"Available Commands:",
			"  add         Add one or more labels to one or more issues",
			"  list        List labels for an issue",
			"  list-all    List all unique labels in the database",
			"  propagate   Propagate a label from a parent issue to all its children",
			"  remove      Remove one or more labels from one or more issues",
			"",
			"Flags:",
			"  -h, --help   help for label",
			""
		].join("\n")
			+ "\n"
			+ upstreamGlobalFlags()
			+ "\nUse \"bd label [command] --help\" for more information about a command.\n";
	}

	static function labelSubcommandHelp(short:String, usage:String, name:String):String {
		return '${short}\n\nUsage:\n  bd label ${usage} [flags]\n\nFlags:\n  -h, --help   help for ${name}\n\n' + upstreamGlobalFlags();
	}

	/** The Global Flags section upstream prints under each command's help. */
	static function upstreamGlobalFlags():String {
		return [
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function graphHelp():String {
		return "Display a visualization of an issue's dependency graph.\n\nWith --all, shows all open issues grouped by connected component.\n\n"
			+ "Usage:\n  bdhx graph [issue-id] [flags]\n\n"
			+ "Flags:\n"
			+ "      --all            Show graph for all open issues\n"
			+ "      --box            ASCII boxes showing layers\n"
			+ "      --compact        Tree format, one line per issue, more scannable\n"
			+ "      --dot            Output Graphviz DOT format (pipe to: dot -Tsvg > graph.svg)\n"
			+ "  -h, --help           help for graph\n"
			+ "      --html           Output self-contained interactive HTML (redirect to file)\n"
			+
			"      --max-rows int   Hard upper bound on the number of issues in the graph. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation.\n"
			+ "      --open           Show only open issues (filters out closed/deferred), forces compact layer format\n\n"
			+ supportedGlobalFlags();
	}

	function depTreeHelp():String {
		return "Show dependency tree rooted at the given issue.\n\n"
			+ "Usage:\n  bdhx dep tree [issue-id] [flags]\n\n"
			+ "Flags:\n"
			+ "      --direction string   Tree direction: 'down' (dependencies), 'up' (dependents), or 'both'\n"
			+ "      --format string      Output format: 'mermaid' for Mermaid.js flowchart\n"
			+ "  -h, --help               help for tree\n"
			+
			"      --max-rows int       Hard upper bound on rows returned. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation.\n"
			+ "  -d, --max-depth int      Maximum tree depth to display (safety limit) (default 50)\n"
			+ "      --reverse            Show dependent tree (deprecated: use --direction=up)\n"
			+ "      --show-all-paths     Deprecated no-op: accepted and ignored. A node reached by two paths is shown once, under the first.\n"
			+ "      --status string      Filter to only show issues with this status (open, in_progress, blocked, deferred, closed)\n\n"
			+ supportedGlobalFlags();
	}

	function depListHelp():String {
		return "List dependencies for one or more issues.\n\n"
			+ "Usage:\n  bdhx dep list [issue-id...] [flags]\n\n"
			+ "Flags:\n  -h, --help               help for list\n"
			+ "  -t, --type string        Filter by dependency type\n"
			+ "      --direction string   Direction: 'down' (dependencies), 'up' (dependents) (default \"down\")\n\n"
			+ supportedGlobalFlags();
	}

	function childrenHelp():String {
		return [
			"List all beads that are children of the specified parent bead.",
			"",
			"This is a convenience alias for 'bd list --parent <id> --status all'.",
			"Unlike plain 'bd list', children includes closed issues by default,",
			"since the primary use case is inspecting all work under a parent.",
			"",
			"Examples:",
			"  bd children hq-abc123        # List all children of hq-abc123",
			"  bd children hq-abc123 --json # List children in JSON format",
			"  bd children hq-abc123 --pretty # Show children in tree format",
			"",
			"Usage:",
			"  bd children <parent-id> [flags]",
			"",
			"Flags:",
			"  -h, --help     help for children",
			"      --pretty   Show children in tree format",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function orphansHelp():String {
		return [
			"Identify orphaned issues - issues that are referenced in commit messages but remain open or in_progress in the database.",
			"",
			"This helps identify work that has been implemented but not formally closed.",
			"",
			"Examples:",
			"  bd orphans              # Show orphaned issues",
			"  bd orphans --json       # Machine-readable output",
			"  bd orphans --details    # Show full commit information",
			"  bd orphans --fix        # Close orphaned issues with confirmation",
			"  bd orphans --label theme:personal             # Only orphans with this label",
			"  bd orphans --label-any theme:personal,theme:ventures  # Orphans with either label",
			"",
			"Usage:",
			"  bd orphans [flags]",
			"",
			"Flags:",
			"      --details             Show full commit information",
			"  -f, --fix                 Close orphaned issues with confirmation",
			"  -h, --help                help for orphans",
			"  -l, --label strings       Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings   Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function staleHelp():String {
		return [
			"Show issues that haven't been updated recently and may need attention.",
			"This helps identify:",
			"- In-progress issues with no recent activity (may be abandoned)",
			"- Open issues that have been forgotten",
			"- Issues that might be outdated or no longer relevant",
			"",
			"Usage:",
			"  bd stale [flags]",
			"",
			"Flags:",
			"  -d, --days int        Issues not updated in this many days (default 30)",
			"  -h, --help            help for stale",
			"  -n, --limit int       Maximum issues to show (default 50)",
			"  -s, --status string   Filter by status (open|in_progress|blocked|deferred)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function countHelp():String {
		return [
			"Count issues matching the specified filters.",
			"",
			"By default, returns the total count of issues matching the filters.",
			"Use --by-* flags to group counts by different attributes.",
			"",
			"Examples:",
			"  bd count                          # Count all issues",
			"  bd count --status open            # Count open issues",
			"  bd count --by-status              # Group count by status",
			"  bd count --by-priority            # Group count by priority",
			"  bd count --by-type                # Group count by issue type",
			"  bd count --by-assignee            # Group count by assignee",
			"  bd count --by-label               # Group count by label",
			"  bd count --assignee alice --by-status  # Count alice's issues by status",
			"  bd count --include-infra          # Count issues + wisps tier (matches 'bd list --include-infra --all' cardinality)",
			"",
			"",
			"Usage:",
			"  bd count [flags]",
			"",
			"Flags:",
			"  -a, --assignee string         Filter by assignee",
			"      --by-assignee             Group count by assignee",
			"      --by-label                Group count by label",
			"      --by-priority             Group count by priority",
			"      --by-status               Group count by status",
			"      --by-type                 Group count by issue type",
			"      --closed-after string     Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string    Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string    Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string   Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --desc-contains string    Filter by description substring",
			"      --empty-description       Filter issues with empty description",
			"  -h, --help                    help for count",
			"      --id string               Filter by specific issue IDs (comma-separated)",
			"      --include-infra           Include infrastructure beads and the wisps tier (matches 'bd list --include-infra --all' cardinality)",
			"  -l, --label strings           Filter by labels (AND: must have ALL)",
			"      --label-any strings       Filter by labels (OR: must have AT LEAST ONE)",
			"      --no-assignee             Filter issues with no assignee",
			"      --no-labels               Filter issues with no labels",
			"      --notes-contains string   Filter by notes substring",
			"  -p, --priority int            Filter by priority (0-4: 0=critical, 1=high, 2=medium, 3=low, 4=backlog)",
			"      --priority-max int        Filter by maximum priority (inclusive)",
			"      --priority-min int        Filter by minimum priority (inclusive)",
			"  -s, --status string           Filter by stored status (open, in_progress, blocked, deferred, closed). Note: dependency-blocked issues use 'bd blocked'",
			"      --title string            Filter by title text (case-insensitive substring match)",
			"      --title-contains string   Filter by title substring",
			"  -t, --type string             Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate)",
			"      --updated-after string    Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string   Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function readyHelp():String {
		return [
			"Show ready work (open issues with no active blockers).",
			"",
			"Excludes in_progress, blocked, deferred, and hooked issues. This uses the",
			"GetReadyWork API which applies blocker-aware semantics to find truly claimable work.",
			"",
			"Note: 'bd list --ready' uses the same blocker-aware ready-work semantics.",
			"",
			"Use --mol to filter to a specific molecule's steps:",
			"  bd ready --mol bd-patrol   # Show ready steps within molecule",
			"",
			"Use --gated to find molecules ready for gate-resume dispatch:",
			"  bd ready --gated           # Find molecules where a gate closed",
			"",
			"Use --claim to atomically claim the first ready issue matching the filters:",
			"  bd ready --claim --json",
			"",
			"This is useful for agents executing molecules to see which steps can run next.",
			"",
			"Usage:",
			"  bd ready [flags]",
			"",
			"Flags:",
			"  -a, --assignee string              Filter by assignee",
			"      --brief                        Omit the free-form text (description, design, acceptance criteria, notes, payload, waiters) from each row. Filters that read those fields still select on them. An omitted field is indistinguishable from an empty one; fetch a whole issue with bd show. Requires --json, and cannot be combined with --claim, --gated, --mol or --explain.",
			"      --claim                        Atomically claim the first ready issue matching the filters",
			"      --exclude-label strings        Exclude issues that have ANY of these labels",
			"      --exclude-type strings         Exclude issue types from results (comma-separated or repeatable, e.g., --exclude-type=convoy,epic)",
			"      --explain                      Show dependency-aware reasoning for why issues are ready or blocked",
			"      --gated                        Find molecules ready for gate-resume dispatch",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for ready",
			"      --include-deferred             Include issues with future defer_until timestamps",
			"      --include-ephemeral            Include ephemeral issues (wisps) in results",
			"  -l, --label strings                Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"      --label-pattern string         Filter by label glob pattern (e.g., 'tech-*' matches tech-debt, tech-legacy)",
			"      --label-regex string           Filter by label regex pattern (e.g., 'tech-(debt|legacy)')",
			"  -n, --limit int                    Maximum issues to show (use 0 for unlimited) (default 100)",
			"      --max-rows int                 Hard upper bound on rows fetched from storage. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation. Useful in CI/agent rigs that want a circuit breaker against pathological queries. Not supported under --proxied-server: an explicit --max-rows or BEADS_MAX_ROWS cap errors out rather than silently going unenforced.",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --mol string                   Filter to steps within a specific molecule",
			"      --mol-type string              Filter by molecule type: swarm, patrol, or work",
			"      --offset int                   Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --parent string                Filter to descendants of this bead/epic",
			"      --plain                        Display issues as a plain numbered list",
			"      --pretty                       Display issues in a tree format with status/priority symbols (default true)",
			"  -p, --priority int                 Filter by priority",
			"  -s, --sort string                  Sort policy: priority (default), hybrid, oldest (default \"priority\")",
			"  -t, --type string                  Filter by issue type (task, bug, feature, epic, decision, merge-request). Aliases: mr→merge-request, feat→feature, mol→molecule, dec/adr→decision",
			"  -u, --unassigned                   Show only unassigned issues",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output\n"
		].join("\n");
	}

	function queryHelp():String {
		return [
			"Query issues using a simple query language that supports compound filters,",
			"boolean operators, and date-relative expressions.",
			"",
			"The query language enables complex filtering that would otherwise require",
			"multiple flags or piping through jq.",
			"",
			"Syntax:",
			"  field=value       Equality comparison",
			"  field!=value      Inequality comparison",
			"  field>value       Greater than",
			"  field>=value      Greater than or equal",
			"  field<value       Less than",
			"  field<=value      Less than or equal",
			"",
			"Boolean operators (case-insensitive):",
			"  expr AND expr     Both conditions must match",
			"  expr OR expr      Either condition can match",
			"  NOT expr          Negates the condition",
			"  (expr)            Grouping with parentheses",
			"",
			"Supported fields:",
			"  status            Stored status (open, in_progress, blocked, deferred, closed). Note: dependency-blocked issues stay \"open\"; use 'bd blocked' to find them",
			"  priority          Priority level (0-4)",
			"  type              Issue type (bug, feature, task, epic, chore, decision)",
			"  assignee          Assigned user (use \"none\" for unassigned)",
			"  owner             Issue owner",
			"  label             Issue label (use \"none\" for unlabeled)",
			"  title             Search in title (contains)",
			"  description       Search in description (contains, \"none\" for empty)",
			"  notes             Search in notes (contains)",
			"  created           Creation date/time",
			"  updated           Last update date/time",
			"  started           Date/time issue first transitioned to in_progress",
			"  closed            Close date/time",
			"  id                Issue ID (supports wildcards: bd-*)",
			"  spec              Spec ID (supports wildcards)",
			"  pinned            Boolean (true/false)",
			"  ephemeral         Boolean (true/false)",
			"  template          Boolean (true/false)",
			"  parent            Parent issue ID",
			"  mol_type          Molecule type (swarm, patrol, work)",
			"",
			"Date values:",
			"  Relative durations: 7d (7 days ago), 24h (24 hours ago), 2w (2 weeks ago)",
			"  Absolute dates: 2025-01-15, 2025-01-15T10:00:00Z",
			"  Natural language: tomorrow, \"next monday\", \"in 3 days\"",
			"",
			"Examples:",
			"  bd query \"status=open AND priority>1\"",
			"  bd query \"status=open AND priority<=2 AND updated>7d\"",
			"  bd query \"(status=open OR status=blocked) AND priority<2\"",
			"  bd query \"type=bug AND label=urgent\"",
			"  bd query \"NOT status=closed\"",
			"  bd query \"assignee=none AND type=task\"",
			"  bd query \"created>30d AND status!=closed\"",
			"  bd query \"label=frontend OR label=backend\"",
			"  bd query \"title=authentication AND priority=0\"",
			"",
			"Usage:",
			"  bd query [expression] [flags]",
			"",
			"Flags:",
			"  -a, --all           Include closed issues (default: exclude closed)",
			"  -h, --help          help for query",
			"  -n, --limit int     Limit results (default: 50, 0 = unlimited) (default 50)",
			"      --long          Show detailed multi-line output for each issue",
			"      --offset int    Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --parse-only    Only parse the query and show the AST (for debugging)",
			"  -r, --reverse       Reverse sort order",
			"      --sort string   Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function searchHelp():String {
		return [
			"Search issues across title and ID (all statuses, including closed).",
			"",
			"ID-like queries (e.g., \"bd-123\", \"hq-319\") use fast exact/prefix matching.",
			"Text queries search titles. Use --desc-contains for description search.",
			"Use --status open (etc.) to narrow; closed issues are included by default",
			"so \"was this already filed/fixed?\" cannot silently answer no. Matches",
			"beyond --limit are dropped status-blind, so when hunting live work in a",
			"large DB, narrow with --status open or raise --limit.",
			"",
			"Examples:",
			"  bd search \"authentication bug\"",
			"  bd search \"login\" --status open",
			"  bd search \"database\" --label backend --limit 10",
			"  bd search --query \"performance\" --assignee alice",
			"  bd search \"bd-5q\" # Search by partial ID (fast prefix match)",
			"  bd search \"security\" --priority-min 0 --priority-max 2",
			"  bd search \"bug\" --created-after 2025-01-01",
			"  bd search \"refactor\" --status open  # Only open issues",
			"  bd search \"bug\" --sort priority",
			"  bd search \"task\" --sort created --reverse",
			"  bd search \"api\" --desc-contains \"endpoint\"",
			"  bd search \"cleanup\" --no-assignee --no-labels",
			"",
			"Usage:",
			"  bd search [query] [flags]",
			"",
			"Flags:",
			"  -a, --assignee string              Filter by assignee",
			"      --closed-after string          Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string         Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string         Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string        Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --desc-contains string         Filter by description substring (case-insensitive)",
			"      --empty-description            Filter issues with empty or missing description",
			"      --external-contains string     Filter by external ref substring (case-insensitive)",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for search",
			"  -l, --label strings                Filter by labels (AND: must have ALL)",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE)",
			"  -n, --limit int                    Limit results (default: 50) (default 50)",
			"      --long                         Show detailed multi-line output for each issue",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --no-assignee                  Filter issues with no assignee",
			"      --no-labels                    Filter issues with no labels",
			"      --notes-contains string        Filter by notes substring (case-insensitive)",
			"      --priority-max string          Filter by maximum priority (inclusive, 0-4 or P0-P4)",
			"      --priority-min string          Filter by minimum priority (inclusive, 0-4 or P0-P4)",
			"      --query string                 Search query (alternative to positional argument)",
			"  -r, --reverse                      Reverse sort order",
			"      --sort string                  Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"  -s, --status string                Filter by stored status (comma-separated for OR; open, in_progress, blocked, deferred, closed, all). Default searches all statuses including closed. Note: dependency-blocked issues use 'bd blocked'",
			"  -t, --type string                  Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate)",
			"      --updated-after string         Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string        Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function showHelp():String {
		return [
			"Show issue details",
			"",
			"Usage:",
			"  bd show [id...] [--id=<id>...] [--current] [flags]",
			"",
			"Aliases:",
			"  show, view",
			"",
			"Flags:",
			"      --as-of string         Show issue as it existed at a specific commit hash or branch (requires Dolt)",
			"      --brief-deps           Reduce each dependency to its identity fields in JSON output (--json only; drops description, design, notes and acceptance criteria)",
			"      --children             Show only the children of this issue",
			"      --current              Show the currently active issue (in-progress, hooked, or last touched)",
			"  -h, --help                 help for show",
			"      --id stringArray       Issue ID (use for IDs that look like flags, e.g., --id=gt--xyz)",
			"      --include-comments     Stream full comment bodies in JSON output (--json only; may be slow on issues with many comments)",
			"      --include-dependents   Stream full dependent issues in JSON output (--json only; may be slow on hub beads)",
			"      --local-time           Show timestamps in local time instead of UTC",
			"      --long                 Show all available fields (extended metadata, agent identity, gate fields, etc.)",
			"      --refs                 Show issues that reference this issue (reverse lookup)",
			"      --short                Show compact one-line output per issue",
			"      --thread               Show full conversation thread (for messages)",
			"  -w, --watch                Watch for changes and auto-refresh display",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function listHelp():String {
		return [
			"List issues",
			"",
			"Usage:",
			"  bd list [flags]",
			"",
			"Flags:",
			"      --all                          Show all issues including closed (overrides default filter)",
			"  -a, --assignee string              Filter by assignee",
			"      --brief                        Omit the free-form text (description, design, acceptance criteria, notes, payload, waiters) from each row. Filters that read those fields, such as --desc-contains, still select on them. An omitted field is indistinguishable from an empty one in --json; fetch a whole issue with bd show.",
			"      --closed-after string          Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string         Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string         Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string        Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --defer-after string           Filter issues deferred after date (supports relative: +6h, tomorrow)",
			"      --defer-before string          Filter issues deferred before date (supports relative: +6h, tomorrow)",
			"      --deferred                     Show only issues with defer_until set",
			"      --deps string[=\"scheduling\"]   Annotate tree with dependency edges and order siblings by them: 'scheduling' (bare --deps) or 'all'",
			"      --desc-contains string         Filter by description substring (case-insensitive)",
			"      --due-after string             Filter issues due after date (supports relative: +6h, tomorrow)",
			"      --due-before string            Filter issues due before date (supports relative: +6h, tomorrow)",
			"      --empty-description            Filter issues with empty or missing description",
			"      --exclude-label strings        Exclude issues that have ANY of these labels",
			"      --exclude-type strings         Exclude issue types from results (comma-separated or repeatable, e.g., --exclude-type=convoy,epic)",
			"      --external-contains string     Filter by external ref substring (case-insensitive)",
			"      --external-ref string          Filter by exact external_ref value",
			"      --flat                         Disable tree format and use legacy flat list output",
			"      --format string                Output format: 'digraph' (for golang.org/x/tools/cmd/digraph), 'dot' (Graphviz), or Go template",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for list",
			"      --id string                    Filter by specific issue IDs (comma-separated, e.g., bd-1,bd-5,bd-10)",
			"      --include-gates                Include gate issues in output (normally hidden)",
			"      --include-infra                Include infrastructure beads (agent/role/message) in output",
			"      --include-templates            Include template molecules in output",
			"  -l, --label strings                Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"      --label-pattern string         Filter by label glob pattern (e.g., 'tech-*' matches tech-debt, tech-legacy)",
			"      --label-regex string           Filter by label regex pattern (e.g., 'tech-(debt|legacy)')",
			"  -n, --limit int                    Limit results (default 50, use 0 for unlimited) (default 50)",
			"      --long                         Show detailed multi-line output for each issue",
			"      --max-rows int                 Hard upper bound on rows returned. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation. Useful in CI/agent rigs that want a circuit breaker against pathological queries. Honored on both the direct and the --proxied-server route.",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --mol-type string              Filter by molecule type: swarm, patrol, or work",
			"      --no-assignee                  Filter issues with no assignee",
			"      --no-labels                    Filter issues with no labels",
			"      --no-pager                     Disable pager output",
			"      --no-parent                    Exclude child issues (show only top-level issues)",
			"      --no-pinned                    Exclude pinned issues",
			"      --notes-contains string        Filter by notes substring (case-insensitive)",
			"      --offset int                   Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --overdue                      Show only issues with due_at in the past (not closed)",
			"      --parent string                Filter by parent issue ID (shows children of specified issue)",
			"      --pinned                       Show only pinned issues",
			"      --pretty                       Display issues in a tree format with status/priority symbols",
			"  -p, --priority string              Priority (0-4 or P0-P4, 0=highest)",
			"      --priority-max string          Filter by maximum priority (inclusive, 0-4 or P0-P4)",
			"      --priority-min string          Filter by minimum priority (inclusive, 0-4 or P0-P4)",
			"      --ready                        Show only ready issues (no active blockers, same semantics as bd ready)",
			"  -r, --reverse                      Reverse sort order",
			"      --skip-labels                  Skip label hydration. The labels field in output will be empty regardless of actual labels. Use only when the caller does not depend on label data. Cannot combine with --label, --label-any, --label-pattern, --label-regex, --exclude-label, or --no-labels.",
			"      --sort string                  Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"      --spec string                  Filter by spec_id prefix",
			"  -s, --status string                Filter by stored status (open, in_progress, blocked, deferred, closed). Comma-separated for multiple: --status open,in_progress. Note: repeating -s/--status silently overwrites the previous value — always use the comma-separated form for multi-status filters.",
			"      --title string                 Filter by title text (case-insensitive substring match)",
			"      --title-contains string        Filter by title substring (case-insensitive)",
			"      --tree                         Hierarchical tree format (default: true; use --flat to disable) (default true)",
			"  -t, --type string                  Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate, convoy). Aliases: mr→merge-request, feat→feature, mol→molecule, dec/adr→decision",
			"      --updated-after string         Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string        Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"  -w, --watch                        Watch for changes and auto-update display (implies --pretty)",
			"      --wisp-type string             Filter by wisp type: heartbeat, ping, patrol, gc_report, recovery, error, escalation",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	/** The help of the hidden BeadsHX snapshot extension; the root help does not list the command. */
	function snapshotHelp():String {
		return [
			"Print a read-only snapshot of every issue in the embedded workspace.",
			"",
			"This is a BeadsHX extension; upstream bd has no snapshot command. The snapshot",
			"is JSON Lines (schema beadshx-task-snapshot/1). Line 1 is a header with the Dolt",
			"revision of the read: _dolt_branch, _dolt_commit, _dolt_state, _project_id,",
			"_records, _schema, _scope and _sort. Each other line is the line that",
			"'bd export --all' prints for one issue, sorted by issue ID in byte order.",
			"Memories and config rows are not included.",
			"",
			"The command reads one Dolt read transaction and writes nothing. It prints the",
			"snapshot on stdout when the whole read is done. Redirect it to a file in a",
			"git-ignored build directory, never under .beads/. The snapshot holds the issue",
			"text: do not commit it to a public repository.",
			"",
			"Usage:",
			"  bdhx snapshot [flags]",
			"",
			"Flags:",
			"  -h, --help   help for snapshot",
			""
		].join("\n") + "\n" + supportedGlobalFlags();
	}

	function basicCommandHelp(description:String, name:String, flags:String):String {
		return '${description}\n\nUsage:\n  bdhx ${name} [flags]\n\nFlags:\n  -h, --help   help for ${name}\n${flags}\n' + supportedGlobalFlags();
	}

	function supportedGlobalFlags():String {
		return "Global Flags:\n"
			+ "      --actor string   Actor name for assigned-work lookup\n"
			+ "  -C, --directory string   Change to this directory before running the command (like git -C)\n"
			+
			"      --database string   Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)\n"
			+
			"      --db string         Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)\n"
			+
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit\n"
			+ "      --ignore-schema-skew   Proceed despite forward schema drift (some queries may fail)\n"
			+ "      --global          Use the global shared-server database (beads_global)\n"
			+ "      --cpu-profile     Generate CPU profile for performance analysis\n"
			+ "      --mem-profile string   Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)\n"
			+ "      --json           Output in JSON format\n"
			+ "      --no-color       Disable color output\n"
			+ "  -q, --quiet          Suppress non-essential output\n"
			+ "      --readonly       Block write operations\n"
			+ "      --sandbox        Disable remote publication\n"
			+ "  -v, --verbose        Enable verbose/debug output\n";
	}
}
