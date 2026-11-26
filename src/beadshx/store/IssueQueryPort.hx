package beadshx.store;

import beadshx.query.QueryTimePort;

/** Command-scoped issue queries with an explicit native-resource lifetime. */
interface IssueQueryPort extends QueryTimePort {
	function relatedIssues(beadsDir:String, databaseName:String, plan:beadshx.relation.RelationRead.RelationReadPlan,
		global:Bool):StoreResult<Array<beadshx.relation.RelatedIssue>>;

	/**
		The rows of one planned `bd query` fetch, which Haxe filters and pages.
		An embedded workspace reads every candidate with Haxe-owned SQL; a
		server-mode or proxied workspace through the native facade.
	**/
	function issueQuery(beadsDir:String, databaseName:String, request:QueryStorageRequest, global:Bool):QueryRowResult;

	/**
		The total, and the buckets of a grouping, of `bd count`. An embedded
		workspace counts with Haxe-owned SQL; a server-mode or proxied
		workspace through the native facade.
	**/
	function issueCount(beadsDir:String, databaseName:String, request:CountRequest, group:CountGroup, global:Bool):StoreResult<CountResult>;

	/**
		The ready work of `bd ready` and the first read of ready --gated, --mol
		and --explain, with the total of a full page and, for an empty one,
		whether any issue is open. An embedded workspace reads it with
		Haxe-owned SQL, with the read that `query` names; a server-mode or
		proxied workspace through the native facade, which reads the counted
		query for both.
	**/
	function issueReady(beadsDir:String, databaseName:String, request:ReadyRequest, query:ReadyQuery, global:Bool):ReadyLoadResult;

	/**
		The issues of `bd search`, and of `label list-all` with no query text,
		in display order. An embedded workspace searches with Haxe-owned SQL; a
		server-mode or proxied workspace through the native facade.
	**/
	function issueSearch(beadsDir:String, databaseName:String, query:String, request:IssueListRequest, global:Bool):IssueListResult;

	/** The stale issues, as `bd stale` lists them, stalest first. */
	function issueStale(beadsDir:String, databaseName:String, request:StaleRequest, global:Bool):StoreResult<Array<StaleIssue>>;

	function issueOrphanCandidates(beadsDir:String, request:IssueListRequest, global:Bool):StoreResult<OrphanCandidateScan>;

	/**
		One list page, as upstream's issueops.Reader.List reads it: the page of
		`bd list`, and the later list reads of a command, such as the exact
		parent and each level of a --parent tree, or the issues that ready
		--gated, --mol and --explain read. Upstream reads them all in the store
		that its pre-run opened once. An embedded workspace reads them with
		Haxe-owned SQL, whose session checks the schema at the command's first
		read only; a server-mode or proxied workspace reads them through the
		native facade.
	**/
	function issueList(beadsDir:String, databaseName:String, request:IssueListRequest, effectiveLimit:Int, global:Bool):IssueListResult;

	function dependencyEdges(beadsDir:String, databaseName:String, ids:Array<String>, dependencyTypes:Array<String>, global:Bool):DependencyEdgeResult;
	function issueSummary(beadsDir:String, databaseName:String, id:String, global:Bool):StoreResult<IssueLookup>;
	function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest, global:Bool):StoreResult<IssueDetailsLookup>;
	function issueDependents(beadsDir:String, id:String, global:Bool):StoreResult<Array<IssueDependency>>;
	function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:IssueStatus, global:Bool):StoreResult<String>;
	function searchIssueIds(beadsDir:String, databaseName:String, query:String, global:Bool):StoreResult<Array<String>>;

	/** The comments of an exact issue ID, as `bd comments` lists them. */
	function issueComments(beadsDir:String, databaseName:String, issueId:String, global:Bool):StoreResult<Array<IssueComment>>;

	/** One entry for each commit that holds an exact issue ID, newest first, as `bd history` reads them. */
	function issueHistory(beadsDir:String, databaseName:String, issueId:String, global:Bool):StoreResult<Array<IssueHistory.IssueHistoryEntry>>;

	/** The audit events of an exact issue ID, newest first, as `bd history --events` reads them; a positive `limit` caps them. */
	function issueEvents(beadsDir:String, databaseName:String, issueId:String, limit:Int, global:Bool):StoreResult<Array<IssueHistory.IssueEvent>>;

	/** The events journal after `since`, as `bd events tail` reads it; a positive `limit` caps the rows. */
	function eventsJournal(beadsDir:String, databaseName:String, since:haxe.Int64, limit:haxe.Int64, global:Bool):StoreResult<EventsJournal.EventsJournalRead>;

	/** Blocked issues, as `bd blocked` reports them; an empty `parentId` means no parent filter. */
	function blockedIssues(beadsDir:String, databaseName:String, parentId:String, global:Bool):StoreResult<Array<SqlBlockedReader.BlockedIssue>>;

	/** Every dependency cycle, as `bd dep cycles` reports it. */
	function dependencyCycles(beadsDir:String, databaseName:String,
		global:Bool):StoreResult<Array<beadshx.relation.DependencyCycle<beadshx.relation.RelatedIssue>>>;

	/** The flattened dependency tree of an exact root ID, as `bd dep tree` walks it. */
	function dependencyTree(beadsDir:String, databaseName:String, request:beadshx.relation.DependencyTree.DependencyTreeRequest,
		global:Bool):StoreResult<Array<beadshx.relation.DependencyTree.TreeNode<beadshx.relation.RelatedIssue>>>;

	/** The cycles `bd graph check` reports, as member ID lists; an empty list means a clean graph. */
	function graphCycles(beadsDir:String, databaseName:String, global:Bool):StoreResult<Array<Array<String>>>;

	/** The connected issues of an exact root ID and their rows, as `bd graph <id>` loads them. */
	function graphSubgraph(beadsDir:String, databaseName:String, rootId:String, global:Bool):StoreResult<SqlGraphReader.GraphLoad>;

	/** The issues of exact IDs, as `bd graph` reads the issues that its external rows find. */
	function graphIssues(beadsDir:String, databaseName:String, ids:Array<String>, global:Bool):StoreResult<Array<beadshx.relation.RelatedIssue>>;

	/** The open issues and their rows, as `bd graph --all` loads them; a positive `maxRows` caps each status. */
	function graphAll(beadsDir:String, databaseName:String, maxRows:Int, global:Bool):StoreResult<SqlGraphReader.AllGraphLoad>;

	/** The database custom types; `bd types` adds the layered config ones and lists them after the built-in ones. */
	function customTypes(beadsDir:String, databaseName:String, global:Bool):StoreResult<CustomConfig.DatabaseCustomTypes>;

	/** The database custom statuses; without them `bd statuses` falls back to the layered config ones. */
	function customStatuses(beadsDir:String, databaseName:String, global:Bool):StoreResult<CustomConfig.DatabaseCustomStatuses>;

	/** One config table value as `bd config get` reads it, or "" when no row holds the key. */
	function configValue(beadsDir:String, databaseName:String, key:String, global:Bool):StoreResult<String>;

	/** Every config table row, as `bd config list` reads them before it filters and sorts. */
	function configSettings(beadsDir:String, databaseName:String, global:Bool):StoreResult<Array<beadshx.config.ConfigKeys.ConfigSetting>>;

	/** The number of rows of the issues table, upstream GetStatistics' TotalIssues, for the note of contributor auto-routing. */
	function issueTotal(beadsDir:String, databaseName:String, global:Bool):StoreResult<Int>;

	function close():StoreResult<Bool>;
}
