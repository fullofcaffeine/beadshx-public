import beadshx.relation.DependencyTree.TreeDirection;
import beadshx.relation.RelationRead.prepareRelationRead;
import beadshx.store.EmbeddedAssignedIssueReader;
import beadshx.store.EmbeddedBlockedReader;
import beadshx.store.EmbeddedCommentReader;
import beadshx.store.EmbeddedCountReader;
import beadshx.store.EmbeddedCustomConfigReader;
import beadshx.store.EmbeddedCycleReader;
import beadshx.store.EmbeddedDependencyReader;
import beadshx.store.EmbeddedEventsJournalReader;
import beadshx.store.EmbeddedGraphReader;
import beadshx.store.EmbeddedHistoryReader;
import beadshx.store.EmbeddedIssueDetailsReader;
import beadshx.store.EmbeddedIssueIdSearch;
import beadshx.store.EmbeddedIssueListReader;
import beadshx.store.EmbeddedIssueSummaryReader;
import beadshx.store.EmbeddedReadyReader;
import beadshx.store.EmbeddedRelationReader;
import beadshx.store.EmbeddedStaleReader;
import beadshx.store.EmbeddedTreeReader;
import beadshx.store.IssueListRequests;
import beadshx.store.IssueListResult;
import beadshx.store.StoreResult;

/**
	Calls every embedded reader once and reports, in one line each, whether it
	succeeded or the exact error it returned.
	Why: the readers kept their own error words when they moved onto the shared
	session; these lines pin those words for a store directory that does not
	exist and for a database that does not exist.
**/
@:goNative
class ReaderMessages {
	public static function observe(scenario:String, beadsDir:String, databaseName:String, issueId:String):Array<String> {
		final lines = new Array<String>();
		final add = (reader:String, result:StoreResult<Bool>) -> lines.push(line(scenario, beadsDir, reader, result));
		add("types", done(EmbeddedCustomConfigReader.readTypes(beadsDir, databaseName)));
		add("statuses", done(EmbeddedCustomConfigReader.readStatuses(beadsDir, databaseName)));
		add("config-get", done(EmbeddedCustomConfigReader.readSetting(beadsDir, databaseName, "issue_prefix")));
		add("config-list", done(EmbeddedCustomConfigReader.readSettings(beadsDir, databaseName)));
		add("blocked", done(EmbeddedBlockedReader.read(beadsDir, databaseName, "")));
		add("stale", done(EmbeddedStaleReader.read(beadsDir, databaseName, {days: 1, status: "", limit: 0})));
		add("list",
			switch EmbeddedIssueListReader.read(beadsDir, databaseName, IssueListRequests.everyIssue(), 0,
				{customTypes: [], customStatuses: [], infraTypes: []}) {
				case ListSuccess(_): Success(true);
				case ListFailure(message): Failure(message);
				case ListRowLimitExceeded(found, _, cap): Failure('row cap: $found over $cap');
			});
		add("ready", switch EmbeddedReadyReader.read(beadsDir, databaseName, {
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
			sort: Hybrid,
			limit: IntAbsent,
			offset: IntAbsent,
			brief: false,
			maxRows: IntAbsent,
			maxRowsSource: ""
		}) {
			case ReadySuccess(_): Success(true);
			case ReadyFailure(message): Failure(message);
			case ReadyRowLimitExceeded(found, _, cap): Failure('row cap: $found over $cap');
		});
		add("count", done(EmbeddedCountReader.read(beadsDir, databaseName, {
			status: "",
			issueType: "",
			assignee: "",
			priority: IntAbsent,
			priorityMin: IntAbsent,
			priorityMax: IntAbsent,
			labels: [],
			labelsAny: [],
			titleSearch: "",
			idFilter: "",
			titleContains: "",
			descriptionContains: "",
			notesContains: "",
			timeFilters: [],
			emptyDescription: false,
			noAssignee: false,
			noLabels: false,
			includeInfra: false
		}, ByStatus, {customTypes: [], customStatuses: [], infraTypes: []})));
		add("comments", done(EmbeddedCommentReader.read(beadsDir, databaseName, issueId)));
		add("cycles", done(EmbeddedCycleReader.read(beadsDir, databaseName)));
		add("events", done(EmbeddedEventsJournalReader.read(beadsDir, databaseName, 0, 10)));
		add("graph-cycles", done(EmbeddedGraphReader.readCycles(beadsDir, databaseName)));
		add("graph-subgraph", done(EmbeddedGraphReader.readSubgraph(beadsDir, databaseName, issueId)));
		add("graph-all", done(EmbeddedGraphReader.readAll(beadsDir, databaseName, 100)));
		add("history", done(EmbeddedHistoryReader.readHistory(beadsDir, databaseName, issueId)));
		add("history-events", done(EmbeddedHistoryReader.readEvents(beadsDir, databaseName, issueId, 10)));
		final plan = switch prepareRelationRead(issueId, "in", []) {
			case RelationPlanInvalid(message): throw message;
			case RelationPlanReady(value): value;
		};
		add("relations", done(EmbeddedRelationReader.read(beadsDir, databaseName, plan)));
		add("tree", done(EmbeddedTreeReader.read(beadsDir, databaseName, {
			rootId: issueId,
			direction: TreeDown,
			maxDepth: 5,
			status: ""
		})));
		add("assigned", switch new EmbeddedAssignedIssueReader(beadsDir, databaseName).read("fixture", "open") {
			case EmbeddedAssignedIssueFailure(message): Failure(message);
			case EmbeddedAssignedIssueMissing | EmbeddedAssignedIssueFound(_): Success(true);
		});
		add("id-search", switch new EmbeddedIssueIdSearch(beadsDir, databaseName).read(issueId.substr(0, 4)) {
			case EmbeddedIssueIdSearchFailure(message): Failure(message);
			case EmbeddedIssueIds(_): Success(true);
		});
		add("dependencies", switch new EmbeddedDependencyReader(beadsDir, databaseName).read([issueId]) {
			case EmbeddedDependencyFailure(message): Failure(message);
			case EmbeddedDependencySnapshot(_): Success(true);
		});
		add("summary", switch new EmbeddedIssueSummaryReader(beadsDir, databaseName).read(issueId) {
			case EmbeddedIssueSummaryFailure(message): Failure(message);
			case EmbeddedIssueSummaryMissing | EmbeddedIssueSummaryFound(_): Success(true);
		});
		// These reads always open the workspace's configured database.
		if (databaseName == "") {
			add("details", done(new EmbeddedIssueDetailsReader(beadsDir).read(issueId, {
				includeDependents: false,
				includeComments: true,
				briefDependencies: false
			})));
			add("dependents", done(new EmbeddedIssueDetailsReader(beadsDir).readDependents(issueId)));
		}
		return lines;
	}

	static function done<T>(result:StoreResult<T>):StoreResult<Bool> {
		return switch result {
			case Success(_): Success(true);
			case Failure(message): Failure(message);
		};
	}

	static function line(scenario:String, beadsDir:String, reader:String, result:StoreResult<Bool>):String {
		return '$scenario/$reader: ' + switch result {
			case Success(_): "ok";
			case Failure(message): 'error: ${StringTools.replace(message, beadsDir, "<beads>")}';
		};
	}
}
