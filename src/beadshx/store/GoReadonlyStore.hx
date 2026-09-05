package beadshx.store;

import beadshx.store.WorkspaceState.readLastTouchedId;
import beadshx.query.QueryTimePort.QueryNormalizedTime;
import beadshx.query.QueryTimePort.QueryTimeInput;
import beadshx.query.QueryTimePort.QueryTimeOutcome;
import beadshx.query.QueryFilter;
import beadshx.query.QueryPage;
import beadshx.relation.DependencyRead;
import beadshx.relation.DependencyRead.DependencyPlanResult;
import beadshx.relation.RawDependencyEdge;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.issueops.EdgeReadRequest;
import beadshx.nativeextern.issueops.EdgeReader;
import beadshx.nativeextern.issueops.IssuePage;
import beadshx.nativeextern.issueops.ListRequest;
import beadshx.nativeextern.issueops.Reader;
import beadshx.nativeextern.time.Time;
import beadshx.nativeextern.time.TimePkg;
import beadshx.nativeextern.timeparsing.TimeparsingPkg;
import beadshx.store.QueryStorageRequest.QueryFetch;
import go.NativeSlice;
import go.NativeStringSlice;
import go.Result;
import beadshx.store.InfoSnapshot.ConfigEntry;

/**
	Typed adapter over the narrow native read-only facade.

	The Go package owns storage selection and lifetime. This adapter narrows its
	value/error results immediately and copies concrete DTO values into Haxe-owned
	structures before command policy or rendering sees them.
**/
@:goNative
final class GoReadonlyStore implements ReadonlyStorePort {
	static inline final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";

	public function new() {}

	public function openIssueQuery(beadsDir:String, databaseName:String, proxiedServer:Bool, global:Bool):StoreResult<IssueQueryPort> {
		if (global)
			if (proxiedServer)
				return Failure("--global is not supported with --proxied-server");
		if (!proxiedServer)
			return Success(this);
		final result = NativeReadonlyFacade.openProxiedQuerySession(beadsDir, databaseName);
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		return native.route() == "proxied" ? Success(new GoProxiedQuerySession(native)) : Failure('unknown native query route "${native.route()}"');
	}

	public function close():StoreResult<Bool> {
		return Success(true);
	}

	public function issueCount(beadsDir:String, request:CountRequest, group:CountGroup, global:Bool):StoreResult<CountResult> {
		return projectCountOutcome(NativeReadonlyFacade.readCountOutcome(beadsDir, countOptions(request), countGroupWireValue(group), global));
	}

	public function issueReady(beadsDir:String, request:ReadyRequest, global:Bool):ReadyLoadResult {
		return projectReadyOutcome(NativeReadonlyFacade.readReadyOutcome(beadsDir, readyOptions(request), global));
	}

	public function issueQuery(beadsDir:String, request:QueryStorageRequest, global:Bool):QueryRowResult {
		final opened = NativeReadonlyFacade.openDirectQuerySession(beadsDir, global);
		if (opened.isErr())
			return QueryRowsFailure(errorMessage(opened));
		final native = opened.unwrap();
		final outcome = readQueryRows(native, request);
		final closed = native.closeResult();
		if (closed.isErr())
			return QueryRowsFailure(errorMessage(closed));
		return outcome;
	}

	public function dependencyEdges(beadsDir:String, databaseName:String, ids:Array<String>, dependencyTypes:Array<String>, global:Bool):DependencyEdgeResult {
		final plan = switch DependencyRead.prepare(ids, dependencyTypes) {
			case DependencyPlanInvalid(message): return DependencyEdgeFailure(message);
			case DependencyPlanReady(value): value;
		};
		if (!global && sys.FileSystem.exists(haxe.io.Path.join([beadsDir, "embeddeddolt"]))) {
			final embedded = EmbeddedStoreAccess.dependencyEdges(beadsDir, databaseName, plan);
			if (embedded != null)
				return embedded;
		}
		final opened = NativeReadonlyFacade.openDirectQuerySession(beadsDir, global);
		if (opened.isErr())
			return DependencyEdgeFailure(errorMessage(opened));
		final native = opened.unwrap();
		final outcome = readDependencyEdges(native, ids, dependencyTypes);
		final closed = native.closeResult();
		if (closed.isErr())
			return DependencyEdgeFailure(errorMessage(closed));
		return outcome;
	}

	/**
		Re-applies Haxe-owned dependency semantics to the current tracer snapshot.

		The `EdgeReader` call remains removal-tracked scaffolding until the native
		boundary supplies only raw presence and edge rows from one read snapshot.
	**/
	public static function readDependencyEdges(native:NativeQuerySession, ids:Array<String>, dependencyTypes:Array<String>):DependencyEdgeResult {
		final plan = switch DependencyRead.prepare(ids, dependencyTypes) {
			case DependencyPlanInvalid(message): return DependencyEdgeFailure(message);
			case DependencyPlanReady(value): value;
		};
		final openedReader = native.edgeReader();
		if (openedReader.isErr())
			return DependencyEdgeFailure(errorMessage(openedReader));
		final request = new EdgeReadRequest();
		request.ids = NativeStringSlice.fromArray([for (id in plan.anchors) id]);
		final read = openedReader.unwrap().readEdges(ContextPkg.background(), request);
		if (read.value2 != null)
			return DependencyEdgeFailure(read.value2.toString());
		final presentIds = new Array<String>();
		final edges = new Array<RawDependencyEdge>();
		final nativeAnchors = read.value1.anchors;
		for (anchorIndex in 0...nativeAnchors.length) {
			final nativeAnchor = nativeAnchors[anchorIndex];
			if (!nativeAnchor.missing)
				presentIds.push(nativeAnchor.id);
			final nativeEdges = nativeAnchor.edges;
			for (edgeIndex in 0...nativeEdges.length) {
				final nativeEdge = nativeEdges[edgeIndex];
				final dependencyType = Std.string(nativeEdge.dependencyType);
				edges.push({
					id: nativeEdge.id,
					issueId: nativeEdge.issueId,
					dependsOnId: nativeEdge.dependsOnId,
					dependencyType: dependencyType,
					createdAt: nativeEdge.createdAt.format(GO_RFC3339_NANO),
					createdBy: nativeEdge.createdBy,
					metadata: nativeEdge.metadata,
					threadId: nativeEdge.threadId
				});
			}
		}
		return switch DependencyRead.finish(plan, {presentIds: presentIds, edges: edges}) {
			case DependencyFinishInvalid(message): DependencyEdgeFailure(message);
			case DependencyFinishReady(anchors): DependencyEdges(anchors);
		};
	}

	/**
		Enumerates the exported Reader role in Haxe, then applies Haxe-owned query
		filtering and paging. Native code only constructs the reader and projects
		row fields whose Go ABI is not yet expressible by the compiler.
	**/
	public static function readQueryRows(native:NativeQuerySession, request:QueryStorageRequest):QueryRowResult {
		final openedReader = native.reader();
		if (openedReader.isErr())
			return QueryRowsFailure(errorMessage(openedReader));
		final reader = openedReader.unwrap();
		final context = ContextPkg.background();
		final nativeRequest = new ListRequest();
		nativeRequest.allFlag = true;
		nativeRequest.includeAllTypes = true;
		final candidates = new Array<IssueQueryRow>();
		var sourceOffset = 0;
		var reading = true;
		while (reading) {
			nativeRequest.offset = sourceOffset;
			final read = reader.list(context, nativeRequest);
			if (read.value2 != null)
				return QueryRowsFailure(read.value2.toString());
			final nativePage = read.value1;
			final projected = projectQueryRowsOutcome(NativeReadonlyFacade.projectQueryPage(nativePage));
			switch projected {
				case QueryRowsFailure(message):
					return QueryRowsFailure(message);
				case QueryRows(page):
					for (row in page.rows)
						candidates.push(row);
					if (!nativePage.hasMore) {
						reading = false;
					} else if (page.rows.length == 0) {
						return QueryRowsFailure("native issue reader reported another page without returning a row");
					} else {
						sourceOffset += page.rows.length;
					}
			}
		}
		final matches = [for (row in candidates) if (QueryFilter.matches(request.filter, row)) row];
		return switch request.fetch {
			case CompleteCandidates: QueryRows({rows: matches, sourceHasMore: false, complete: true});
			case OrderedPage(limit, offset, sortBy, reverse):
				final page = QueryPage.finish(matches, {
					limit: limit,
					offset: offset,
					sortBy: sortBy,
					reverse: reverse
				}, false);
				QueryRows({rows: page.rows, sourceHasMore: page.hasMore, complete: true});
		};
	}

	public function normalize(inputs:Array<QueryTimeInput>):Array<QueryTimeOutcome> {
		return normalizeQueryTimes(inputs);
	}

	public static function normalizeQueryTimes(inputs:Array<QueryTimeInput>):Array<QueryTimeOutcome> {
		final outcomes = new Array<QueryTimeOutcome>();
		if (inputs.length == 0)
			return outcomes;
		final now = TimePkg.now();
		final dayDuration = TimePkg.parseDuration("24h");
		if (dayDuration.value2 != null) {
			outcomes.push(TimeInvalid(dayDuration.value2.toString()));
			return outcomes;
		}
		for (input in inputs) {
			if (input.durationAgo) {
				final value = input.value.charAt(0) == "+" ? input.value.substr(1) : input.value;
				final parsed = TimeparsingPkg.parseCompactDuration("-" + value, now);
				outcomes.push(parsed.value2 == null ? normalizeParsedTime(parsed.value1, dayDuration.value1) : TimeInvalid(parsed.value2.toString()));
			} else {
				final parsed = TimeparsingPkg.parseRelativeTime(input.value, now);
				outcomes.push(parsed.value2 == null ? normalizeParsedTime(parsed.value1, dayDuration.value1) : TimeInvalid(parsed.value2.toString()));
			}
		}
		return outcomes;
	}

	static function normalizeParsedTime(target:Time, dayDuration:beadshx.nativeextern.time.Duration):QueryTimeOutcome {
		final dayStart = TimePkg.date(target.year(), target.month(), target.day(), 0, 0, 0, 0, target.location());
		final nextDay = dayStart.add(dayDuration);
		final endOfDay = TimePkg.date(target.year(), target.month(), target.day(), 23, 59, 59, 999999999, target.location());
		final projectedTarget = projectNativeTime(target);
		final projectedDayStart = projectNativeTime(dayStart);
		final projectedNextDay = projectNativeTime(nextDay);
		final projectedEndOfDay = projectNativeTime(endOfDay);
		if (projectedTarget == null || projectedDayStart == null || projectedNextDay == null || projectedEndOfDay == null)
			return TimeInvalid("native time package returned an invalid month");
		return TimeNormalized({
			target: projectedTarget,
			dayStart: projectedDayStart,
			nextDay: projectedNextDay,
			endOfDay: projectedEndOfDay
		});
	}

	static function projectNativeTime(native:Time):Null<QueryInstant> {
		final month = Std.parseInt(native.format("1"));
		if (month == null || month < 1 || month > 12)
			return null;
		return {
			canonical: native.format(GO_RFC3339_NANO),
			epochSeconds: Std.string(native.unix()),
			nanosecond: native.nanosecond(),
			year: native.year(),
			month: month,
			day: native.day()
		};
	}

	static function projectQueryInstant(native:NativeQueryInstant):QueryInstant {
		return {
			canonical: native.canonical(),
			epochSeconds: native.epochSeconds(),
			nanosecond: native.nanosecond(),
			year: native.year(),
			month: native.month(),
			day: native.day()
		};
	}

	public static function projectQueryRowsOutcome(outcome:NativeQueryRowsOutcome):QueryRowResult {
		if (outcome.failed())
			return QueryRowsFailure(outcome.message());
		final rows = new Array<IssueQueryRow>();
		for (index in 0...outcome.count()) {
			final native = outcome.row(index);
			switch projectIssueListItem(native.item()) {
				case Failure(message):
					return QueryRowsFailure(message);
				case Success(item):
					rows.push({
						item: item,
						pinned: native.pinned(),
						ephemeral: native.ephemeral(),
						template: native.template(),
						created: projectQueryInstant(native.created()),
						updated: projectQueryInstant(native.updated()),
						started: native.hasStarted() ? InstantPresent(projectQueryInstant(native.started())) : InstantAbsent,
						closed: native.hasClosed() ? InstantPresent(projectQueryInstant(native.closed())) : InstantAbsent
					});
			}
		}
		return QueryRows({rows: rows, sourceHasMore: outcome.sourceHasMore(), complete: outcome.complete()});
	}

	public static function readyOptions(request:ReadyRequest):NativeReadyOptions {
		final options = NativeReadyOptions.create();
		if (request.issueType != "")
			options.setIssueType(request.issueType);
		if (request.assignee != "")
			options.setAssignee(request.assignee);
		if (request.unassigned)
			options.enableUnassigned();
		for (label in request.labels)
			options.addLabel(label);
		for (label in request.labelsAny)
			options.addLabelAny(label);
		for (label in request.excludeLabels)
			options.addExcludeLabel(label);
		if (request.labelPattern != "")
			options.setLabelPattern(request.labelPattern);
		if (request.labelRegex != "")
			options.setLabelRegex(request.labelRegex);
		switch request.priority {
			case IntPresent(value):
				options.setPriority(value);
			case IntAbsent:
		}
		if (request.parentId != "")
			options.setParentID(request.parentId);
		if (request.moleculeType != "")
			options.setMoleculeType(request.moleculeType);
		if (request.includeDeferred)
			options.enableDeferred();
		if (request.includeEphemeral)
			options.enableEphemeral();
		for (issueType in request.excludeTypes)
			options.addExcludeType(issueType);
		for (filter in request.metadataFields)
			options.addMetadataField(filter.key, filter.value);
		if (request.hasMetadataKey != "")
			options.setHasMetadataKey(request.hasMetadataKey);
		options.setSort(readySortWireValue(request.sort));
		switch request.limit {
			case IntPresent(value):
				options.setLimit(value);
			case IntAbsent:
		}
		switch request.offset {
			case IntPresent(value):
				options.setOffset(value);
			case IntAbsent:
		}
		if (request.brief)
			options.enableBrief();
		switch request.maxRows {
			case IntPresent(value):
				options.setMaxRows(value, request.maxRowsSource);
			case IntAbsent:
		}
		return options;
	}

	public static function readySortWireValue(sort:ReadySort):String {
		return switch sort {
			case Priority: "priority";
			case Hybrid: "hybrid";
			case Oldest: "oldest";
		};
	}

	public static function projectReadyOutcome(outcome:NativeReadyOutcome):ReadyLoadResult {
		if (outcome.rowLimitExceeded())
			return ReadyRowLimitExceeded(outcome.found(), outcome.source(), outcome.cap());
		if (outcome.failed())
			return ReadyFailure(outcome.message());
		if (outcome.total() == "")
			return readySuccess(outcome, ReadyTotal.TotalUnknown);
		return switch JsonInteger.parse(outcome.total()) {
			case Failure(message): ReadyFailure(message);
			case Success(value): readySuccess(outcome, ReadyTotal.TotalKnown(value));
		};
	}

	static function readySuccess(outcome:NativeReadyOutcome, total:ReadyTotal):ReadyLoadResult {
		return switch projectIssueListPage(outcome.page()) {
			case Failure(message): ReadyFailure(message);
			case Success(page):
				ReadySuccess({
					page: page,
					truncated: outcome.truncated(),
					total: total,
					hasOpenIssues: outcome.hasOpenIssues()
				});
		};
	}

	public static function countOptions(request:CountRequest):NativeCountOptions {
		final options = NativeCountOptions.create();
		if (request.status != "")
			options.setStatus(request.status);
		if (request.issueType != "")
			options.setIssueType(request.issueType);
		if (request.assignee != "")
			options.setAssignee(request.assignee);
		if (request.titleSearch != "")
			options.setTitleSearch(request.titleSearch);
		if (request.idFilter != "")
			options.setIDFilter(request.idFilter);
		if (request.titleContains != "")
			options.setTitleContains(request.titleContains);
		if (request.descriptionContains != "")
			options.setDescContains(request.descriptionContains);
		if (request.notesContains != "")
			options.setNotesContains(request.notesContains);
		for (label in request.labels)
			options.addLabel(label);
		for (label in request.labelsAny)
			options.addLabelAny(label);
		switch request.priority {
			case IntPresent(value):
				options.setPriority(value);
			case IntAbsent:
		}
		switch request.priorityMin {
			case IntPresent(value):
				options.setPriorityMin(value);
			case IntAbsent:
		}
		switch request.priorityMax {
			case IntPresent(value):
				options.setPriorityMax(value);
			case IntAbsent:
		}
		for (filter in request.timeFilters)
			switch filter {
				case CreatedAfter(value):
					options.setCreatedAfter(value);
				case CreatedBefore(value):
					options.setCreatedBefore(value);
				case UpdatedAfter(value):
					options.setUpdatedAfter(value);
				case UpdatedBefore(value):
					options.setUpdatedBefore(value);
				case ClosedAfter(value):
					options.setClosedAfter(value);
				case ClosedBefore(value):
					options.setClosedBefore(value);
				case DeferAfter(_) | DeferBefore(_) | DueAfter(_) | DueBefore(_):
			}
		if (request.emptyDescription)
			options.setEmptyDescription();
		if (request.noAssignee)
			options.setNoAssignee();
		if (request.noLabels)
			options.setNoLabels();
		if (request.includeInfra)
			options.setIncludeInfra();
		return options;
	}

	public static function countGroupWireValue(group:CountGroup):String {
		return switch group {
			case Ungrouped: "";
			case ByStatus: "status";
			case ByPriority: "priority";
			case ByType: "type";
			case ByAssignee: "assignee";
			case ByLabel: "label";
		};
	}

	public static function projectCountOutcome(outcome:NativeCountOutcome):StoreResult<CountResult> {
		if (outcome.failed())
			return Failure(outcome.message());
		return switch JsonInteger.parse(outcome.total()) {
			case Failure(message): Failure(message);
			case Success(total): projectCountGroups(outcome, total, 0, []);
		};
	}

	static function projectCountGroups(outcome:NativeCountOutcome, total:JsonInteger, index:Int, groups:Array<CountBucket>):StoreResult<CountResult> {
		if (index == outcome.groupCount()) {
			groups.sort((left, right) -> left.group < right.group ? -1 : left.group == right.group ? 0 : 1);
			return Success({total: total, groups: groups});
		}
		return switch JsonInteger.parse(outcome.count(index)) {
			case Failure(message): Failure(message);
			case Success(count):
				groups.push({group: outcome.group(index), count: count});
				projectCountGroups(outcome, total, index + 1, groups);
		};
	}

	public function validate(beadsDir:String, global:Bool):StoreResult<Bool> {
		final result = NativeReadonlyFacade.validateOpen(beadsDir, global);
		return result.isErr() ? Failure(errorMessage(result)) : Success(result.unwrap());
	}

	public function info(beadsDir:String, includeSchema:Bool, global:Bool):StoreResult<InfoSnapshot> {
		final result = NativeReadonlyFacade.readInfo(beadsDir, includeSchema, global);
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		final config = new Array<ConfigEntry>();
		for (index in 0...native.configCount()) {
			config.push({key: native.configKey(index), value: native.configValue(index)});
		}
		final sampleIssueIds = new Array<String>();
		for (index in 0...native.sampleCount()) {
			sampleIssueIds.push(native.sampleId(index));
		}
		return Success({
			databasePath: native.databasePath(),
			mode: native.mode(),
			issueCount: native.issueCount(),
			config: config,
			schemaVersion: native.schemaVersion(),
			issuePrefix: native.issuePrefix(),
			sampleIssueIds: sampleIssueIds
		});
	}

	public function ping(beadsDir:String, global:Bool):StoreResult<PingSnapshot> {
		final result = NativeReadonlyFacade.checkPing(beadsDir, global);
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		return Success({
			resolveMs: native.resolveMs(),
			storeMs: native.storeMs(),
			queryMs: native.queryMs(),
			totalMs: native.totalMs()
		});
	}

	public function status(beadsDir:String, skipBlocked:Bool, assignee:String, global:Bool):StoreResult<StatusSnapshot> {
		final result = NativeReadonlyFacade.readStatus(beadsDir, skipBlocked, assignee, global);
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		return Success({
			totalIssues: native.totalIssues(),
			openIssues: native.openIssues(),
			inProgressIssues: native.inProgressIssues(),
			closedIssues: native.closedIssues(),
			blockedIssues: native.blockedIssues(),
			blockedAvailable: native.blockedAvailable(),
			deferredIssues: native.deferredIssues(),
			readyIssues: native.readyIssues(),
			readyAvailable: native.readyAvailable(),
			pinnedIssues: native.pinnedIssues(),
			epicsEligibleForClosure: native.epicsEligibleForClosure(),
			averageLeadTime: native.averageLeadTime()
		});
	}

	public function issueList(beadsDir:String, request:IssueListRequest, effectiveLimit:Int, global:Bool):IssueListResult {
		final options = issueListOptions(request, effectiveLimit);
		if (request.format != "") {
			final outcome = NativeReadonlyFacade.readIssueListFormatOutcome(beadsDir, options, global, request.format);
			if (outcome.rowLimitExceeded())
				return ListRowLimitExceeded(outcome.found(), outcome.source(), outcome.cap());
			if (outcome.failed())
				return ListFailure(outcome.message());
			return ListSuccess({items: [], hasMore: false, formatted: outcome.value()});
		}
		return projectIssueListOutcome(NativeReadonlyFacade.readIssueListOutcome(beadsDir, options, global));
	}

	public function issueSearch(beadsDir:String, query:String, request:IssueListRequest, global:Bool):IssueListResult {
		final options = searchOptions(request);
		return projectIssueListOutcome(NativeReadonlyFacade.readSearchOutcome(beadsDir, query, options, global));
	}

	public function issueStale(beadsDir:String, request:StaleRequest, global:Bool):StoreResult<Array<StaleIssue>> {
		return projectStaleOutcome(NativeReadonlyFacade.readStaleOutcome(beadsDir, request.days, request.status, request.limit, global));
	}

	public function issueOrphanCandidates(beadsDir:String, request:IssueListRequest, global:Bool):StoreResult<OrphanCandidateScan> {
		return projectOrphanCandidatesResult(NativeReadonlyFacade.readOrphanCandidates(beadsDir, searchOptions(request), global));
	}

	public static function searchOptions(request:IssueListRequest):NativeIssueListOptions {
		final options = NativeIssueListOptions.create();
		applyIssueListRequest(options, request);
		return options;
	}

	public static function issueListOptions(request:IssueListRequest, effectiveLimit:Int):NativeIssueListOptions {
		final options = NativeIssueListOptions.create();
		applyIssueListRequest(options, request);
		options.setLimit(effectiveLimit);
		return options;
	}

	static function applyIssueListRequest(options:NativeIssueListOptions, request:IssueListRequest):Void {
		if (request.status != "")
			options.setStatus(request.status);
		if (request.issueType != "")
			options.setIssueType(request.issueType);
		if (request.assignee != "")
			options.setAssignee(request.assignee);
		if (request.titleSearch != "")
			options.setTitleSearch(request.titleSearch);
		if (request.specPrefix != "")
			options.setSpecPrefix(request.specPrefix);
		if (request.idFilter != "")
			options.setIDFilter(request.idFilter);
		for (label in request.labels)
			options.addLabel(label);
		for (label in request.labelsAny)
			options.addLabelAny(label);
		for (label in request.excludeLabels)
			options.addExcludeLabel(label);
		if (request.labelPattern != "")
			options.setLabelPattern(request.labelPattern);
		if (request.labelRegex != "")
			options.setLabelRegex(request.labelRegex);
		if (request.titleContains != "")
			options.setTitleContains(request.titleContains);
		if (request.descriptionContains != "")
			options.setDescriptionContains(request.descriptionContains);
		if (request.notesContains != "")
			options.setNotesContains(request.notesContains);
		if (request.externalContains != "")
			options.setExternalContains(request.externalContains);
		if (request.externalRef != "")
			options.setExternalRef(request.externalRef);
		for (filter in request.timeFilters)
			switch filter {
				case CreatedAfter(value):
					options.setCreatedAfter(value);
				case CreatedBefore(value):
					options.setCreatedBefore(value);
				case UpdatedAfter(value):
					options.setUpdatedAfter(value);
				case UpdatedBefore(value):
					options.setUpdatedBefore(value);
				case ClosedAfter(value):
					options.setClosedAfter(value);
				case ClosedBefore(value):
					options.setClosedBefore(value);
				case DeferAfter(value):
					options.setDeferAfter(value);
				case DeferBefore(value):
					options.setDeferBefore(value);
				case DueAfter(value):
					options.setDueAfter(value);
				case DueBefore(value):
					options.setDueBefore(value);
			}
		switch request.priority {
			case IntAbsent:
			case IntPresent(value):
				options.setPriority(value);
		}
		switch request.priorityMin {
			case IntAbsent:
			case IntPresent(value):
				options.setPriorityMin(value);
		}
		switch request.priorityMax {
			case IntAbsent:
			case IntPresent(value):
				options.setPriorityMax(value);
		}
		if (request.all)
			options.enableAll();
		if (request.ready)
			options.enableReady();
		if (request.noAssignee)
			options.enableNoAssignee();
		if (request.noLabels)
			options.enableNoLabels();
		if (request.emptyDescription)
			options.enableEmptyDescription();
		if (request.skipLabels)
			options.enableSkipLabels();
		if (request.brief)
			options.enableBrief();
		if (request.pinned)
			options.enablePinned();
		if (request.noPinned)
			options.enableNoPinned();
		if (request.includeTemplates)
			options.enableTemplates();
		if (request.includeGates)
			options.enableGates();
		if (request.includeInfra)
			options.enableInfra();
		for (issueType in request.excludeTypes)
			options.addExcludeType(issueType);
		if (request.parentId != "")
			options.setParentID(request.parentId);
		if (request.noParent)
			options.enableNoParent();
		if (request.moleculeType != "")
			options.setMoleculeType(request.moleculeType);
		if (request.wispType != "")
			options.setWispType(request.wispType);
		if (request.deferred)
			options.enableDeferred();
		if (request.overdue)
			options.enableOverdue();
		for (filter in request.metadataFields)
			options.addMetadataField(filter.key, filter.value);
		if (request.hasMetadataKey != "")
			options.setHasMetadataKey(request.hasMetadataKey);
		if (request.sortBy != "")
			options.setSortBy(request.sortBy);
		if (request.reverse)
			options.enableReverse();
		switch request.limit {
			case IntAbsent:
			case IntPresent(value):
				options.setLimit(value);
		}
		switch request.offset {
			case IntAbsent:
			case IntPresent(value):
				options.setOffset(value);
		}
		switch request.maxRows {
			case IntAbsent:
			case IntPresent(value):
				options.setMaxRows(value, request.maxRowsSource);
		}
		if (request.skipCounts)
			options.enableSkipCounts();
		if (request.blockingAnnotations)
			options.enableBlockingAnnotations();
	}

	public static function projectIssueListOutcome(outcome:NativeIssueListOutcome):IssueListResult {
		if (outcome.rowLimitExceeded())
			return ListRowLimitExceeded(outcome.found(), outcome.source(), outcome.cap());
		if (outcome.failed())
			return ListFailure(outcome.message());
		return switch projectIssueListPage(outcome.page()) {
			case Failure(message): ListFailure(message);
			case Success(page): ListSuccess(page);
		};
	}

	public static function projectStaleOutcome(outcome:NativeIssueListOutcome):StoreResult<Array<StaleIssue>> {
		if (outcome.failed())
			return Failure(outcome.message());
		final issues = new Array<StaleIssue>();
		final page = outcome.page();
		for (index in 0...page.count()) {
			final native = page.item(index);
			var longFields:Null<IssueLongFields> = null;
			switch copyIssueLongFields(native.record()) {
				case Failure(message):
					return Failure(message);
				case Success(value):
					longFields = value;
			}
			if (longFields == null)
				return Failure("native store returned no long issue fields");
			issues.push({
				id: native.id(),
				title: native.title(),
				description: native.description(),
				design: native.design(),
				acceptanceCriteria: native.acceptanceCriteria(),
				notes: native.notes(),
				specId: native.specId(),
				status: native.status(),
				priority: native.priority(),
				issueType: native.issueType(),
				assignee: native.assignee(),
				owner: native.owner(),
				estimatedMinutes: native.hasEstimatedMinutes() ? OptionalInt.IntPresent(native.estimatedMinutes()) : OptionalInt.IntAbsent,
				createdAt: native.createdAt(),
				createdBy: native.createdBy(),
				updatedAt: native.updatedAt(),
				startedAt: native.startedAt(),
				closedAt: native.closedAt(),
				closeReason: native.closeReason(),
				closedBySession: native.closedBySession(),
				dueAt: native.dueAt(),
				deferUntil: native.deferUntil(),
				externalRef: native.externalRef(),
				sourceSystem: native.sourceSystem(),
				metadata: JsonValue.fromValidatedNative(native.metadata()),
				wispType: native.wispType(),
				moleculeType: native.moleculeType(),
				longFields: longFields,
				updatedAtMillis: native.updatedAtMillis()
			});
		}
		return Success(issues);
	}

	public static function projectOrphanCandidatesResult(result:Result<NativeOrphanCandidates>):StoreResult<OrphanCandidateScan> {
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		final candidates = new Array<OrphanCandidate>();
		for (index in 0...native.count()) {
			final candidate = native.item(index);
			candidates.push({id: candidate.id(), title: candidate.title(), status: candidate.status()});
		}
		return Success({prefix: native.prefix(), candidates: candidates});
	}

	public static function copyIssueLongFields(native:NativeIssueRecord):StoreResult<IssueLongFields> {
		final bondedFrom = new Array<IssueBondReference>();
		for (index in 0...native.bondedFromCount()) {
			final reference = native.bondedFrom(index);
			bondedFrom.push({sourceId: reference.sourceId(), bondType: reference.bondType(), bondPoint: reference.bondPoint()});
		}
		final waiters = new Array<String>();
		for (index in 0...native.waiterCount())
			waiters.push(native.waiter(index));
		return switch JsonInteger.parse(native.timeoutNanos()) {
			case Failure(message): Failure(message);
			case Success(timeoutNanos): Success({
					isBlocked: native.isBlocked(),
					leaseExpiresAt: native.leaseExpiresAt(),
					heartbeatAt: native.heartbeatAt(),
					leaseGrantedNode: native.leaseGrantedNode(),
					compactionLevel: native.compactionLevel(),
					compactedAt: native.compactedAt(),
					compactedAtCommit: native.compactedAtCommit(),
					originalSize: native.originalSize(),
					sender: native.sender(),
					ephemeral: native.ephemeral(),
					noHistory: native.noHistory(),
					storageClass: native.storageClass(),
					pinned: native.pinned(),
					template: native.template(),
					bondedFrom: bondedFrom,
					awaitType: native.awaitType(),
					awaitId: native.awaitId(),
					timeout: native.timeout(),
					timeoutNanos: timeoutNanos,
					waiters: waiters,
					sourceFormula: native.sourceFormula(),
					sourceLocation: native.sourceLocation(),
					workType: native.workType(),
					eventKind: native.eventKind(),
					actor: native.actor(),
					target: native.target(),
					payload: native.payload()
				});
		};
	}

	public static function projectIssueListPage(native:NativeIssueListPage):StoreResult<IssueListPage> {
		final items = new Array<IssueListItem>();
		for (index in 0...native.count())
			switch projectIssueListItem(native.item(index)) {
				case Failure(message):
					return Failure(message);
				case Success(item):
					items.push(item);
			}
		return Success({items: items, hasMore: native.hasMore(), formatted: ""});
	}

	public static function projectIssueListItem(item:NativeIssueListItem):StoreResult<IssueListItem> {
		final labels = new Array<String>();
		for (labelIndex in 0...item.labelCount())
			labels.push(item.label(labelIndex));
		final dependencies = new Array<IssueListDependency>();
		for (dependencyIndex in 0...item.dependencyLength()) {
			final dependency = item.dependency(dependencyIndex);
			dependencies.push({
				id: dependency.id(),
				issueId: dependency.issueId(),
				dependsOnId: dependency.dependsOnId(),
				dependencyType: dependency.dependencyType(),
				createdAt: dependency.createdAt(),
				createdBy: dependency.createdBy(),
				metadata: dependency.metadata(),
				threadId: dependency.threadId()
			});
		}
		final blockedBy = new Array<String>();
		for (blockingIndex in 0...item.blockedByCount())
			blockedBy.push(item.blockedBy(blockingIndex));
		final blocks = new Array<String>();
		for (blockingIndex in 0...item.blocksCount())
			blocks.push(item.blocks(blockingIndex));
		return switch copyIssueLongFields(item.record()) {
			case Failure(message): Failure(message);
			case Success(longFields): Success({
					id: item.id(),
					title: item.title(),
					description: item.description(),
					design: item.design(),
					acceptanceCriteria: item.acceptanceCriteria(),
					notes: item.notes(),
					specId: item.specId(),
					status: item.status(),
					priority: item.priority(),
					issueType: item.issueType(),
					assignee: item.assignee(),
					owner: item.owner(),
					estimatedMinutes: item.hasEstimatedMinutes() ? OptionalInt.IntPresent(item.estimatedMinutes()) : OptionalInt.IntAbsent,
					createdAt: item.createdAt(),
					createdBy: item.createdBy(),
					updatedAt: item.updatedAt(),
					startedAt: item.startedAt(),
					closedAt: item.closedAt(),
					closeReason: item.closeReason(),
					closedBySession: item.closedBySession(),
					dueAt: item.dueAt(),
					deferUntil: item.deferUntil(),
					externalRef: item.externalRef(),
					sourceSystem: item.sourceSystem(),
					metadata: JsonValue.fromValidatedNative(item.metadata()),
					wispType: item.wispType(),
					moleculeType: item.moleculeType(),
					longFields: longFields,
					sender: item.sender(),
					labels: labels,
					dependencies: dependencies,
					dependencyCount: item.dependencyCount(),
					dependentCount: item.dependentCount(),
					commentCount: item.commentCount(),
					parent: item.parent(),
					blockedBy: blockedBy,
					blocks: blocks,
					blockingParent: item.blockingParent()
				});
		};
	}

	public function issueSummary(beadsDir:String, databaseName:String, id:String, global:Bool):StoreResult<IssueLookup> {
		if (!global && sys.FileSystem.exists(haxe.io.Path.join([beadsDir, "embeddeddolt"]))) {
			final embedded = EmbeddedStoreAccess.issueSummary(beadsDir, databaseName, id);
			if (embedded != null)
				return embedded;
		}
		return projectIssueSummaryResult(NativeReadonlyFacade.readIssueSummary(beadsDir, id, global));
	}

	public static function projectIssueSummaryResult(result:Result<NativeIssueLookup>):StoreResult<IssueLookup> {
		if (result.isErr())
			return Failure(errorMessage(result));
		final lookup = result.unwrap();
		if (!lookup.found())
			return Success(IssueMissing);
		final native = lookup.summary();
		return Success(IssueFound({
			id: native.id(),
			title: native.title(),
			status: parseIssueStatus(native.status()),
			priority: native.priority(),
			issueType: parseIssueType(native.issueType())
		}));
	}

	public function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest, global:Bool):StoreResult<IssueDetailsLookup> {
		if (!global && sys.FileSystem.exists(haxe.io.Path.join([beadsDir, "embeddeddolt"]))) {
			final embedded = EmbeddedStoreAccess.issueDetails(beadsDir, id);
			if (embedded != null)
				return embedded;
		}
		return projectIssueDetailsResult(NativeReadonlyFacade.readIssueDetails(beadsDir, id, issueDetailsOptions(request), global));
	}

	public static function issueDetailsOptions(request:IssueDetailsRequest):NativeIssueDetailsOptions {
		final options = NativeIssueDetailsOptions.create();
		if (request.includeDependents)
			options.enableDependents();
		if (request.includeComments)
			options.enableComments();
		if (request.briefDependencies)
			options.enableBriefDeps();
		return options;
	}

	public static function projectIssueDetailsResult(result:Result<NativeIssueDetailsLookup>):StoreResult<IssueDetailsLookup> {
		if (result.isErr())
			return Failure(errorMessage(result));
		final lookup = result.unwrap();
		if (!lookup.found())
			return Success(DetailsMissing);
		final native = lookup.details();
		final labels = new Array<String>();
		for (index in 0...native.labelCount())
			labels.push(native.label(index));
		final dependencies = new Array<IssueDependency>();
		for (index in 0...native.dependencyRowCount())
			dependencies.push(copyIssueDependency(native.dependency(index)));
		final dependents = new Array<IssueDependency>();
		for (index in 0...native.dependentRowCount())
			dependents.push(copyIssueDependency(native.dependent(index)));
		final comments = new Array<IssueComment>();
		for (index in 0...native.commentRowCount()) {
			final comment = native.comment(index);
			comments.push({
				id: comment.id(),
				issueId: comment.issueId(),
				author: comment.author(),
				text: comment.text(),
				createdAt: comment.createdAt()
			});
		}
		final estimatedMinutes:OptionalInt = native.hasEstimatedMinutes() ? OptionalInt.IntPresent(native.estimatedMinutes()) : OptionalInt.IntAbsent;
		var longFields:Null<IssueLongFields> = null;
		switch copyIssueLongFields(native.record()) {
			case Failure(message):
				return Failure(message);
			case Success(value):
				longFields = value;
		}
		if (longFields == null)
			return Failure("native store returned no long issue fields");
		final epicProgress:EpicProgress = native.hasEpicProgress() ? EpicProgress.HasEpicProgress(native.epicTotalChildren(), native.epicClosedChildren(),
			native.epicCloseable()) : EpicProgress.NoEpicProgress;
		return switch JsonInteger.parse(native.revision()) {
			case Failure(message): Failure(message);
			case Success(revision):
				Success(DetailsFound({
					id: native.id(),
					title: native.title(),
					description: native.description(),
					design: native.design(),
					acceptanceCriteria: native.acceptanceCriteria(),
					notes: native.notes(),
					specId: native.specId(),
					status: native.status(),
					priority: native.priority(),
					issueType: native.issueType(),
					assignee: native.assignee(),
					owner: native.owner(),
					estimatedMinutes: estimatedMinutes,
					createdAt: native.createdAt(),
					createdBy: native.createdBy(),
					updatedAt: native.updatedAt(),
					startedAt: native.startedAt(),
					closedAt: native.closedAt(),
					closeReason: native.closeReason(),
					closedBySession: native.closedBySession(),
					dueAt: native.dueAt(),
					deferUntil: native.deferUntil(),
					externalRef: native.externalRef(),
					sourceSystem: native.sourceSystem(),
					metadata: JsonValue.fromValidatedNative(native.metadata()),
					wispType: native.wispType(),
					moleculeType: native.moleculeType(),
					labels: labels,
					dependencies: dependencies,
					dependents: dependents,
					comments: comments,
					parent: native.parent(),
					dependentCount: native.dependentCount(),
					dependencyCount: native.dependencyCount(),
					commentCount: native.commentCount(),
					commentsOmitted: native.commentsOmitted(),
					epicProgress: epicProgress,
					revision: revision,
					longFields: longFields
				}));
		};
	}

	public function issueDependents(beadsDir:String, id:String, global:Bool):StoreResult<Array<IssueDependency>> {
		return projectIssueDependentsResult(NativeReadonlyFacade.readIssueDependents(beadsDir, id, global));
	}

	public static function projectIssueDependentsResult(result:Result<NativeIssueDependencyRows>):StoreResult<Array<IssueDependency>> {
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		final dependents = new Array<IssueDependency>();
		for (index in 0...native.count())
			dependents.push(copyIssueDependency(native.item(index)));
		return Success(dependents);
	}

	public static function copyIssueDependency(native:NativeIssueDependency):IssueDependency {
		final estimatedMinutes:OptionalInt = native.hasEstimatedMinutes() ? OptionalInt.IntPresent(native.estimatedMinutes()) : OptionalInt.IntAbsent;
		return {
			id: native.id(),
			title: native.title(),
			description: native.description(),
			design: native.design(),
			acceptanceCriteria: native.acceptanceCriteria(),
			notes: native.notes(),
			specId: native.specId(),
			status: native.status(),
			priority: native.priority(),
			issueType: native.issueType(),
			assignee: native.assignee(),
			owner: native.owner(),
			estimatedMinutes: estimatedMinutes,
			createdAt: native.createdAt(),
			createdBy: native.createdBy(),
			updatedAt: native.updatedAt(),
			startedAt: native.startedAt(),
			closedAt: native.closedAt(),
			closeReason: native.closeReason(),
			closedBySession: native.closedBySession(),
			dueAt: native.dueAt(),
			deferUntil: native.deferUntil(),
			externalRef: native.externalRef(),
			sourceSystem: native.sourceSystem(),
			metadata: JsonValue.fromValidatedNative(native.metadata()),
			wispType: native.wispType(),
			moleculeType: native.moleculeType(),
			dependencyType: native.dependencyType()
		};
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:IssueStatus, global:Bool):StoreResult<String> {
		if (!global && sys.FileSystem.exists(haxe.io.Path.join([beadsDir, "embeddeddolt"]))) {
			final embedded = EmbeddedStoreAccess.assignedIssueId(beadsDir, databaseName, actor, issueStatusWireValue(status));
			if (embedded != null)
				return embedded;
		}
		final result = NativeReadonlyFacade.findAssignedIssue(beadsDir, actor, issueStatusWireValue(status), global);
		return result.isErr() ? Failure(errorMessage(result)) : Success(result.unwrap());
	}

	public function lastTouchedId(beadsDir:String):String {
		return readLastTouchedId(beadsDir);
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String, global:Bool):StoreResult<Array<String>> {
		if (!global && sys.FileSystem.exists(haxe.io.Path.join([beadsDir, "embeddeddolt"]))) {
			final embedded = EmbeddedStoreAccess.searchIssueIds(beadsDir, databaseName, query);
			if (embedded != null)
				return embedded;
		}
		final result = NativeReadonlyFacade.searchIssueIds(beadsDir, query, global);
		if (result.isErr())
			return Failure(errorMessage(result));
		final native = result.unwrap();
		final ids = new Array<String>();
		for (index in 0...native.count())
			ids.push(native.id(index));
		return Success(ids);
	}

	public static function issueStatusWireValue(status:IssueStatus):String {
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

	public static function parseIssueStatus(value:String):IssueStatus {
		return switch value {
			case "open": Open;
			case "in_progress": InProgress;
			case "blocked": Blocked;
			case "closed": Closed;
			case "deferred": Deferred;
			case "pinned": Pinned;
			case other: OtherStatus(other);
		};
	}

	public static function parseIssueType(value:String):IssueType {
		return switch value {
			case "epic": Epic;
			case "bug": Bug;
			case other: OtherType(other);
		};
	}

	public static function errorMessage<T>(result:Result<T>):String {
		final message = result.error();
		return message == null ? "native read-only operation failed" : message;
	}
}

/** Typed Haxe owner of one strict proxied native query session. */
@:goNative
private final class GoProxiedQuerySession implements IssueQueryPort {
	final native:NativeQuerySession;

	public function new(native:NativeQuerySession) {
		this.native = native;
	}

	public function issueList(beadsDir:String, request:IssueListRequest, effectiveLimit:Int, global:Bool):IssueListResult {
		final options = GoReadonlyStore.issueListOptions(request, effectiveLimit);
		if (request.format != "") {
			final outcome = native.readIssueListFormatOutcome(options, request.format);
			if (outcome.rowLimitExceeded())
				return ListRowLimitExceeded(outcome.found(), outcome.source(), outcome.cap());
			if (outcome.failed())
				return ListFailure(outcome.message());
			return ListSuccess({items: [], hasMore: false, formatted: outcome.value()});
		}
		return GoReadonlyStore.projectIssueListOutcome(native.readIssueListOutcome(options));
	}

	public function issueCount(beadsDir:String, request:CountRequest, group:CountGroup, global:Bool):StoreResult<CountResult> {
		return GoReadonlyStore.projectCountOutcome(native.readCountOutcome(GoReadonlyStore.countOptions(request), GoReadonlyStore.countGroupWireValue(group)));
	}

	public function issueReady(beadsDir:String, request:ReadyRequest, global:Bool):ReadyLoadResult {
		return GoReadonlyStore.projectReadyOutcome(native.readReadyOutcome(GoReadonlyStore.readyOptions(request)));
	}

	public function issueQuery(beadsDir:String, request:QueryStorageRequest, global:Bool):QueryRowResult {
		return GoReadonlyStore.readQueryRows(native, request);
	}

	public function dependencyEdges(beadsDir:String, databaseName:String, ids:Array<String>, dependencyTypes:Array<String>, global:Bool):DependencyEdgeResult {
		return GoReadonlyStore.readDependencyEdges(native, ids, dependencyTypes);
	}

	public function normalize(inputs:Array<QueryTimeInput>):Array<QueryTimeOutcome> {
		return GoReadonlyStore.normalizeQueryTimes(inputs);
	}

	public function issueSearch(beadsDir:String, query:String, request:IssueListRequest, global:Bool):IssueListResult {
		return GoReadonlyStore.projectIssueListOutcome(native.readSearchOutcome(query, GoReadonlyStore.searchOptions(request)));
	}

	public function issueStale(beadsDir:String, request:StaleRequest, global:Bool):StoreResult<Array<StaleIssue>> {
		return GoReadonlyStore.projectStaleOutcome(native.readStaleOutcome(request.days, request.status, request.limit));
	}

	public function issueOrphanCandidates(beadsDir:String, request:IssueListRequest, global:Bool):StoreResult<OrphanCandidateScan> {
		return GoReadonlyStore.projectOrphanCandidatesResult(native.readOrphanCandidates(GoReadonlyStore.searchOptions(request)));
	}

	public function issueSummary(beadsDir:String, databaseName:String, id:String, global:Bool):StoreResult<IssueLookup> {
		return GoReadonlyStore.projectIssueSummaryResult(native.readIssueSummary(id));
	}

	public function issueDetails(beadsDir:String, id:String, request:IssueDetailsRequest, global:Bool):StoreResult<IssueDetailsLookup> {
		return GoReadonlyStore.projectIssueDetailsResult(native.readIssueDetails(id, GoReadonlyStore.issueDetailsOptions(request)));
	}

	public function issueDependents(beadsDir:String, id:String, global:Bool):StoreResult<Array<IssueDependency>> {
		return GoReadonlyStore.projectIssueDependentsResult(native.readIssueDependents(id));
	}

	public function assignedIssueId(beadsDir:String, databaseName:String, actor:String, status:IssueStatus, global:Bool):StoreResult<String> {
		final result = native.findAssignedIssue(actor, GoReadonlyStore.issueStatusWireValue(status));
		return result.isErr() ? Failure(GoReadonlyStore.errorMessage(result)) : Success(result.unwrap());
	}

	public function searchIssueIds(beadsDir:String, databaseName:String, query:String, global:Bool):StoreResult<Array<String>> {
		final result = native.searchIssueIds(query);
		if (result.isErr())
			return Failure(GoReadonlyStore.errorMessage(result));
		final nativeIds = result.unwrap();
		final ids = new Array<String>();
		for (index in 0...nativeIds.count())
			ids.push(nativeIds.id(index));
		return Success(ids);
	}

	public function close():StoreResult<Bool> {
		final result = native.closeResult();
		if (result.isErr()) {
			final message = result.error();
			return Failure(message == null ? "closing native query session failed" : message);
		}
		return Success(result.unwrap());
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("Info")
extern class NativeInfo {
	@:go.name("DatabasePath") function databasePath():String;
	@:go.name("Mode") function mode():String;
	@:go.name("IssueCount") function issueCount():Int;
	@:go.name("ConfigCount") function configCount():Int;
	@:go.name("ConfigKey") function configKey(index:Int):String;
	@:go.name("ConfigValue") function configValue(index:Int):String;
	@:go.name("SchemaVersion") function schemaVersion():String;
	@:go.name("IssuePrefix") function issuePrefix():String;
	@:go.name("SampleCount") function sampleCount():Int;
	@:go.name("SampleID") function sampleId(index:Int):String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("Ping")
extern class NativePing {
	@:go.name("ResolveMS") function resolveMs():Int;
	@:go.name("StoreMS") function storeMs():Int;
	@:go.name("QueryMS") function queryMs():Int;
	@:go.name("TotalMS") function totalMs():Int;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("Status")
extern class NativeStatus {
	@:go.name("TotalIssues") function totalIssues():Int;
	@:go.name("OpenIssues") function openIssues():Int;
	@:go.name("InProgressIssues") function inProgressIssues():Int;
	@:go.name("ClosedIssues") function closedIssues():Int;
	@:go.name("BlockedIssues") function blockedIssues():Int;
	@:go.name("BlockedAvailable") function blockedAvailable():Bool;
	@:go.name("DeferredIssues") function deferredIssues():Int;
	@:go.name("ReadyIssues") function readyIssues():Int;
	@:go.name("ReadyAvailable") function readyAvailable():Bool;
	@:go.name("PinnedIssues") function pinnedIssues():Int;
	@:go.name("EpicsEligibleForClosure") function epicsEligibleForClosure():Int;
	@:go.name("AverageLeadTime") function averageLeadTime():Float;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueSummary")
extern class NativeIssueSummary {
	@:go.name("ID") function id():String;
	@:go.name("Title") function title():String;
	@:go.name("Status") function status():String;
	@:go.name("Priority") function priority():Int;
	@:go.name("IssueType") function issueType():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueLookup")
extern class NativeIssueLookup {
	@:go.name("Found") function found():Bool;
	@:go.name("Summary") function summary():NativeIssueSummary;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("OrphanCandidate")
extern class NativeOrphanCandidate {
	@:go.name("ID") function id():String;
	@:go.name("Title") function title():String;
	@:go.name("Status") function status():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("OrphanCandidates")
extern class NativeOrphanCandidates {
	@:go.name("Prefix") function prefix():String;
	@:go.name("Count") function count():Int;
	@:go.name("Item") function item(index:Int):NativeOrphanCandidate;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListItem")
extern class NativeIssueListItem extends NativeIssueRecord {
	@:go.name("Record") function record():NativeIssueRecord;
	@:go.name("Sender") function sender():String;
	@:go.name("LabelCount") function labelCount():Int;
	@:go.name("Label") function label(index:Int):String;
	@:go.name("DependencyLength") function dependencyLength():Int;
	@:go.name("Dependency") function dependency(index:Int):NativeIssueListDependency;
	@:go.name("DependencyCount") function dependencyCount():Int;
	@:go.name("DependentCount") function dependentCount():Int;
	@:go.name("CommentCount") function commentCount():Int;
	@:go.name("Parent") function parent():String;
	@:go.name("BlockedByCount") function blockedByCount():Int;
	@:go.name("BlockedBy") function blockedBy(index:Int):String;
	@:go.name("BlocksCount") function blocksCount():Int;
	@:go.name("Blocks") function blocks(index:Int):String;
	@:go.name("BlockingParent") function blockingParent():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListDependency")
extern class NativeIssueListDependency {
	@:go.name("ID") function id():String;
	@:go.name("IssueID") function issueId():String;
	@:go.name("DependsOnID") function dependsOnId():String;
	@:go.name("DependencyType") function dependencyType():String;
	@:go.name("CreatedAt") function createdAt():String;
	@:go.name("CreatedBy") function createdBy():String;
	@:go.name("Metadata") function metadata():String;
	@:go.name("ThreadID") function threadId():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListPage")
extern class NativeIssueListPage {
	@:go.name("Count") function count():Int;
	@:go.name("HasMore") function hasMore():Bool;
	@:go.name("Item") function item(index:Int):NativeIssueListItem;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListOutcome")
extern class NativeIssueListOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("RowLimitExceeded") function rowLimitExceeded():Bool;
	@:go.name("Found") function found():Int;
	@:go.name("Source") function source():String;
	@:go.name("Cap") function cap():Int;
	@:go.name("Page") function page():NativeIssueListPage;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("QueryInstant")
extern class NativeQueryInstant {
	@:go.name("Canonical") function canonical():String;
	@:go.name("EpochSeconds") function epochSeconds():String;
	@:go.name("Nanosecond") function nanosecond():Int;
	@:go.name("Year") function year():Int;
	@:go.name("Month") function month():Int;
	@:go.name("Day") function day():Int;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("QueryRow")
extern class NativeQueryRow {
	@:go.name("Item") function item():NativeIssueListItem;
	@:go.name("Pinned") function pinned():Bool;
	@:go.name("Ephemeral") function ephemeral():Bool;
	@:go.name("Template") function template():Bool;
	@:go.name("Created") function created():NativeQueryInstant;
	@:go.name("Updated") function updated():NativeQueryInstant;
	@:go.name("HasStarted") function hasStarted():Bool;
	@:go.name("Started") function started():NativeQueryInstant;
	@:go.name("HasClosed") function hasClosed():Bool;
	@:go.name("Closed") function closed():NativeQueryInstant;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("QueryRowsOutcome")
extern class NativeQueryRowsOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("Count") function count():Int;
	@:go.name("SourceHasMore") function sourceHasMore():Bool;
	@:go.name("Complete") function complete():Bool;
	@:go.name("Row") function row(index:Int):NativeQueryRow;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListFormatOutcome")
extern class NativeIssueListFormatOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("RowLimitExceeded") function rowLimitExceeded():Bool;
	@:go.name("Found") function found():Int;
	@:go.name("Source") function source():String;
	@:go.name("Cap") function cap():Int;
	@:go.name("Value") function value():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueListOptions")
extern class NativeIssueListOptions {
	@:go.name("NewIssueListOptions") static function create():NativeIssueListOptions;
	@:go.name("SetStatus") function setStatus(value:String):Void;
	@:go.name("SetIssueType") function setIssueType(value:String):Void;
	@:go.name("SetAssignee") function setAssignee(value:String):Void;
	@:go.name("SetTitleSearch") function setTitleSearch(value:String):Void;
	@:go.name("SetSpecPrefix") function setSpecPrefix(value:String):Void;
	@:go.name("SetIDFilter") function setIDFilter(value:String):Void;
	@:go.name("AddLabel") function addLabel(value:String):Void;
	@:go.name("AddLabelAny") function addLabelAny(value:String):Void;
	@:go.name("AddExcludeLabel") function addExcludeLabel(value:String):Void;
	@:go.name("SetLabelPattern") function setLabelPattern(value:String):Void;
	@:go.name("SetLabelRegex") function setLabelRegex(value:String):Void;
	@:go.name("SetTitleContains") function setTitleContains(value:String):Void;
	@:go.name("SetDescriptionContains") function setDescriptionContains(value:String):Void;
	@:go.name("SetNotesContains") function setNotesContains(value:String):Void;
	@:go.name("SetExternalContains") function setExternalContains(value:String):Void;
	@:go.name("SetExternalRef") function setExternalRef(value:String):Void;
	@:go.name("SetCreatedAfter") function setCreatedAfter(value:String):Void;
	@:go.name("SetCreatedBefore") function setCreatedBefore(value:String):Void;
	@:go.name("SetUpdatedAfter") function setUpdatedAfter(value:String):Void;
	@:go.name("SetUpdatedBefore") function setUpdatedBefore(value:String):Void;
	@:go.name("SetClosedAfter") function setClosedAfter(value:String):Void;
	@:go.name("SetClosedBefore") function setClosedBefore(value:String):Void;
	@:go.name("SetDeferAfter") function setDeferAfter(value:String):Void;
	@:go.name("SetDeferBefore") function setDeferBefore(value:String):Void;
	@:go.name("SetDueAfter") function setDueAfter(value:String):Void;
	@:go.name("SetDueBefore") function setDueBefore(value:String):Void;
	@:go.name("SetPriority") function setPriority(value:Int):Void;
	@:go.name("SetPriorityMin") function setPriorityMin(value:Int):Void;
	@:go.name("SetPriorityMax") function setPriorityMax(value:Int):Void;
	@:go.name("EnableAll") function enableAll():Void;
	@:go.name("EnableReady") function enableReady():Void;
	@:go.name("EnableNoAssignee") function enableNoAssignee():Void;
	@:go.name("EnableNoLabels") function enableNoLabels():Void;
	@:go.name("EnableEmptyDescription") function enableEmptyDescription():Void;
	@:go.name("EnableSkipLabels") function enableSkipLabels():Void;
	@:go.name("EnableBrief") function enableBrief():Void;
	@:go.name("EnablePinned") function enablePinned():Void;
	@:go.name("EnableNoPinned") function enableNoPinned():Void;
	@:go.name("EnableTemplates") function enableTemplates():Void;
	@:go.name("EnableGates") function enableGates():Void;
	@:go.name("EnableInfra") function enableInfra():Void;
	@:go.name("AddExcludeType") function addExcludeType(value:String):Void;
	@:go.name("SetParentID") function setParentID(value:String):Void;
	@:go.name("EnableNoParent") function enableNoParent():Void;
	@:go.name("SetMoleculeType") function setMoleculeType(value:String):Void;
	@:go.name("SetWispType") function setWispType(value:String):Void;
	@:go.name("EnableDeferred") function enableDeferred():Void;
	@:go.name("EnableOverdue") function enableOverdue():Void;
	@:go.name("AddMetadataField") function addMetadataField(key:String, value:String):Void;
	@:go.name("SetHasMetadataKey") function setHasMetadataKey(value:String):Void;
	@:go.name("SetSortBy") function setSortBy(value:String):Void;
	@:go.name("EnableReverse") function enableReverse():Void;
	@:go.name("SetLimit") function setLimit(value:Int):Void;
	@:go.name("SetOffset") function setOffset(value:Int):Void;
	@:go.name("SetMaxRows") function setMaxRows(value:Int, source:String):Void;
	@:go.name("EnableSkipCounts") function enableSkipCounts():Void;
	@:go.name("EnableBlockingAnnotations") function enableBlockingAnnotations():Void;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueRecord")
extern class NativeIssueRecord {
	@:go.name("ID") function id():String;
	@:go.name("Title") function title():String;
	@:go.name("Description") function description():String;
	@:go.name("Design") function design():String;
	@:go.name("AcceptanceCriteria") function acceptanceCriteria():String;
	@:go.name("Notes") function notes():String;
	@:go.name("SpecID") function specId():String;
	@:go.name("Status") function status():String;
	@:go.name("Priority") function priority():Int;
	@:go.name("IssueType") function issueType():String;
	@:go.name("IsBlocked") function isBlocked():Bool;
	@:go.name("Assignee") function assignee():String;
	@:go.name("Owner") function owner():String;
	@:go.name("HasEstimatedMinutes") function hasEstimatedMinutes():Bool;
	@:go.name("EstimatedMinutes") function estimatedMinutes():Int;
	@:go.name("CreatedAt") function createdAt():String;
	@:go.name("CreatedBy") function createdBy():String;
	@:go.name("UpdatedAt") function updatedAt():String;
	@:go.name("UpdatedAtMillis") function updatedAtMillis():Float;
	@:go.name("StartedAt") function startedAt():String;
	@:go.name("ClosedAt") function closedAt():String;
	@:go.name("CloseReason") function closeReason():String;
	@:go.name("ClosedBySession") function closedBySession():String;
	@:go.name("LeaseExpiresAt") function leaseExpiresAt():String;
	@:go.name("HeartbeatAt") function heartbeatAt():String;
	@:go.name("LeaseGrantedNode") function leaseGrantedNode():String;
	@:go.name("DueAt") function dueAt():String;
	@:go.name("DeferUntil") function deferUntil():String;
	@:go.name("ExternalRef") function externalRef():String;
	@:go.name("SourceSystem") function sourceSystem():String;
	@:go.name("Metadata") function metadata():String;
	@:go.name("WispType") function wispType():String;
	@:go.name("MoleculeType") function moleculeType():String;
	@:go.name("CompactionLevel") function compactionLevel():Int;
	@:go.name("CompactedAt") function compactedAt():String;
	@:go.name("CompactedAtCommit") function compactedAtCommit():String;
	@:go.name("OriginalSize") function originalSize():Int;
	@:go.name("Sender") function sender():String;
	@:go.name("Ephemeral") function ephemeral():Bool;
	@:go.name("NoHistory") function noHistory():Bool;
	@:go.name("StorageClass") function storageClass():String;
	@:go.name("Pinned") function pinned():Bool;
	@:go.name("Template") function template():Bool;
	@:go.name("BondedFromCount") function bondedFromCount():Int;
	@:go.name("BondedFrom") function bondedFrom(index:Int):NativeIssueBondReference;
	@:go.name("AwaitType") function awaitType():String;
	@:go.name("AwaitID") function awaitId():String;
	@:go.name("Timeout") function timeout():String;
	@:go.name("TimeoutNanos") function timeoutNanos():String;
	@:go.name("WaiterCount") function waiterCount():Int;
	@:go.name("Waiter") function waiter(index:Int):String;
	@:go.name("SourceFormula") function sourceFormula():String;
	@:go.name("SourceLocation") function sourceLocation():String;
	@:go.name("WorkType") function workType():String;
	@:go.name("EventKind") function eventKind():String;
	@:go.name("Actor") function actor():String;
	@:go.name("Target") function target():String;
	@:go.name("Payload") function payload():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueBondReference")
extern class NativeIssueBondReference {
	@:go.name("SourceID") function sourceId():String;
	@:go.name("BondType") function bondType():String;
	@:go.name("BondPoint") function bondPoint():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueDependency")
extern class NativeIssueDependency extends NativeIssueRecord {
	@:go.name("DependencyType") function dependencyType():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueDependencyRows")
extern class NativeIssueDependencyRows {
	@:go.name("Count") function count():Int;
	@:go.name("Item") function item(index:Int):NativeIssueDependency;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueComment")
extern class NativeIssueComment {
	@:go.name("ID") function id():String;
	@:go.name("IssueID") function issueId():String;
	@:go.name("Author") function author():String;
	@:go.name("Text") function text():String;
	@:go.name("CreatedAt") function createdAt():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueDetails")
extern class NativeIssueDetails extends NativeIssueRecord {
	@:go.name("Record") function record():NativeIssueRecord;
	@:go.name("LabelCount") function labelCount():Int;
	@:go.name("Label") function label(index:Int):String;
	@:go.name("DependencyRowCount") function dependencyRowCount():Int;
	@:go.name("Dependency") function dependency(index:Int):NativeIssueDependency;
	@:go.name("DependentRowCount") function dependentRowCount():Int;
	@:go.name("Dependent") function dependent(index:Int):NativeIssueDependency;
	@:go.name("CommentRowCount") function commentRowCount():Int;
	@:go.name("Comment") function comment(index:Int):NativeIssueComment;
	@:go.name("Parent") function parent():String;
	@:go.name("DependentCount") function dependentCount():Int;
	@:go.name("DependencyCount") function dependencyCount():Int;
	@:go.name("CommentCount") function commentCount():Int;
	@:go.name("CommentsOmitted") function commentsOmitted():Bool;
	@:go.name("HasEpicProgress") function hasEpicProgress():Bool;
	@:go.name("EpicTotalChildren") function epicTotalChildren():Int;
	@:go.name("EpicClosedChildren") function epicClosedChildren():Int;
	@:go.name("EpicCloseable") function epicCloseable():Bool;
	@:go.name("Revision") function revision():String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueDetailsLookup")
extern class NativeIssueDetailsLookup {
	@:go.name("Found") function found():Bool;
	@:go.name("Details") function details():NativeIssueDetails;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueDetailsOptions")
extern class NativeIssueDetailsOptions {
	@:go.name("NewIssueDetailsOptions") static function create():NativeIssueDetailsOptions;
	@:go.name("EnableDependents") function enableDependents():Void;
	@:go.name("EnableComments") function enableComments():Void;
	@:go.name("EnableBriefDeps") function enableBriefDeps():Void;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("IssueIDs")
extern class NativeIssueIDs {
	@:go.name("Count") function count():Int;
	@:go.name("ID") function id(index:Int):String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("CountOptions")
extern class NativeCountOptions {
	@:go.name("NewCountOptions") static function create():NativeCountOptions;
	@:go.name("SetStatus") function setStatus(value:String):Void;
	@:go.name("SetIssueType") function setIssueType(value:String):Void;
	@:go.name("SetAssignee") function setAssignee(value:String):Void;
	@:go.name("SetTitleSearch") function setTitleSearch(value:String):Void;
	@:go.name("SetIDFilter") function setIDFilter(value:String):Void;
	@:go.name("SetTitleContains") function setTitleContains(value:String):Void;
	@:go.name("SetDescContains") function setDescContains(value:String):Void;
	@:go.name("SetNotesContains") function setNotesContains(value:String):Void;
	@:go.name("AddLabel") function addLabel(value:String):Void;
	@:go.name("AddLabelAny") function addLabelAny(value:String):Void;
	@:go.name("SetPriority") function setPriority(value:Int):Void;
	@:go.name("SetPriorityMin") function setPriorityMin(value:Int):Void;
	@:go.name("SetPriorityMax") function setPriorityMax(value:Int):Void;
	@:go.name("SetCreatedAfter") function setCreatedAfter(value:String):Void;
	@:go.name("SetCreatedBefore") function setCreatedBefore(value:String):Void;
	@:go.name("SetUpdatedAfter") function setUpdatedAfter(value:String):Void;
	@:go.name("SetUpdatedBefore") function setUpdatedBefore(value:String):Void;
	@:go.name("SetClosedAfter") function setClosedAfter(value:String):Void;
	@:go.name("SetClosedBefore") function setClosedBefore(value:String):Void;
	@:go.name("SetEmptyDescription") function setEmptyDescription():Void;
	@:go.name("SetNoAssignee") function setNoAssignee():Void;
	@:go.name("SetNoLabels") function setNoLabels():Void;
	@:go.name("SetIncludeInfra") function setIncludeInfra():Void;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("CountOutcome")
extern class NativeCountOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("Total") function total():String;
	@:go.name("GroupCount") function groupCount():Int;
	@:go.name("Group") function group(index:Int):String;
	@:go.name("Count") function count(index:Int):String;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("ReadyOptions")
extern class NativeReadyOptions {
	@:go.name("NewReadyOptions") static function create():NativeReadyOptions;
	@:go.name("SetIssueType") function setIssueType(value:String):Void;
	@:go.name("SetAssignee") function setAssignee(value:String):Void;
	@:go.name("EnableUnassigned") function enableUnassigned():Void;
	@:go.name("AddLabel") function addLabel(value:String):Void;
	@:go.name("AddLabelAny") function addLabelAny(value:String):Void;
	@:go.name("AddExcludeLabel") function addExcludeLabel(value:String):Void;
	@:go.name("SetLabelPattern") function setLabelPattern(value:String):Void;
	@:go.name("SetLabelRegex") function setLabelRegex(value:String):Void;
	@:go.name("SetPriority") function setPriority(value:Int):Void;
	@:go.name("SetParentID") function setParentID(value:String):Void;
	@:go.name("SetMoleculeType") function setMoleculeType(value:String):Void;
	@:go.name("EnableDeferred") function enableDeferred():Void;
	@:go.name("EnableEphemeral") function enableEphemeral():Void;
	@:go.name("AddExcludeType") function addExcludeType(value:String):Void;
	@:go.name("AddMetadataField") function addMetadataField(key:String, value:String):Void;
	@:go.name("SetHasMetadataKey") function setHasMetadataKey(value:String):Void;
	@:go.name("SetSort") function setSort(value:String):Void;
	@:go.name("SetLimit") function setLimit(value:Int):Void;
	@:go.name("SetOffset") function setOffset(value:Int):Void;
	@:go.name("EnableBrief") function enableBrief():Void;
	@:go.name("SetMaxRows") function setMaxRows(value:Int, source:String):Void;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("ReadyOutcome")
extern class NativeReadyOutcome {
	@:go.name("Failed") function failed():Bool;
	@:go.name("Message") function message():String;
	@:go.name("RowLimitExceeded") function rowLimitExceeded():Bool;
	@:go.name("Found") function found():Int;
	@:go.name("Source") function source():String;
	@:go.name("Cap") function cap():Int;
	@:go.name("Total") function total():String;
	@:go.name("Truncated") function truncated():Bool;
	@:go.name("HasOpenIssues") function hasOpenIssues():Bool;
	@:go.name("Page") function page():NativeIssueListPage;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
@:go.name("QuerySession")
extern class NativeQuerySession {
	@:go.name("Route") function route():String;
	@:go.name("Reader")
	@:go.valueError
	function reader():Result<Reader>;
	@:go.name("EdgeReader")
	@:go.valueError
	function edgeReader():Result<EdgeReader>;
	@:go.name("ReadCountOutcome") function readCountOutcome(options:NativeCountOptions, group:String):NativeCountOutcome;
	@:go.name("ReadReadyOutcome") function readReadyOutcome(options:NativeReadyOptions):NativeReadyOutcome;
	@:go.name("ReadSearchOutcome") function readSearchOutcome(query:String, options:NativeIssueListOptions):NativeIssueListOutcome;
	@:go.name("ReadStaleOutcome") function readStaleOutcome(days:Int, status:String, limit:Int):NativeIssueListOutcome;
	@:go.name("ReadOrphanCandidates")
	@:go.valueError
	function readOrphanCandidates(options:NativeIssueListOptions):Result<NativeOrphanCandidates>;
	@:go.name("ReadIssueListOutcome") function readIssueListOutcome(options:NativeIssueListOptions):NativeIssueListOutcome;
	@:go.name("ReadIssueListFormatOutcome") function readIssueListFormatOutcome(options:NativeIssueListOptions, format:String):NativeIssueListFormatOutcome;
	@:go.name("ReadIssueSummary")
	@:go.valueError
	function readIssueSummary(id:String):Result<NativeIssueLookup>;
	@:go.name("ReadIssueDetails")
	@:go.valueError
	function readIssueDetails(id:String, options:NativeIssueDetailsOptions):Result<NativeIssueDetailsLookup>;
	@:go.name("ReadIssueDependents")
	@:go.valueError
	function readIssueDependents(id:String):Result<NativeIssueDependencyRows>;
	@:go.name("FindAssignedIssue")
	@:go.valueError
	function findAssignedIssue(actor:String, status:String):Result<String>;
	@:go.name("SearchIssueIDs")
	@:go.valueError
	function searchIssueIds(query:String):Result<NativeIssueIDs>;
	@:go.name("CloseResult")
	@:go.valueError
	function closeResult():Result<Bool>;
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/readonlyfacade")
extern class NativeReadonlyFacade {
	@:go.name("OpenDirectQuerySession")
	@:go.valueError
	static function openDirectQuerySession(beadsDir:String, global:Bool):Result<NativeQuerySession>;
	@:go.name("OpenProxiedQuerySession")
	@:go.valueError
	static function openProxiedQuerySession(beadsDir:String, databaseName:String):Result<NativeQuerySession>;

	/** Adapts the pointer-backed Haxe carrier to this Go value parameter. */
	@:go.valueArgs("0")
	@:go.name("ProjectQueryPage") static function projectQueryPage(page:IssuePage):NativeQueryRowsOutcome;

	@:go.name("ReadCountOutcome") static function readCountOutcome(beadsDir:String, options:NativeCountOptions, group:String, global:Bool):NativeCountOutcome;
	@:go.name("ReadReadyOutcome") static function readReadyOutcome(beadsDir:String, options:NativeReadyOptions, global:Bool):NativeReadyOutcome;
	@:go.name("ReadSearchOutcome") static function readSearchOutcome(beadsDir:String, query:String, options:NativeIssueListOptions,
		global:Bool):NativeIssueListOutcome;
	@:go.name("ReadStaleOutcome") static function readStaleOutcome(beadsDir:String, days:Int, status:String, limit:Int, global:Bool):NativeIssueListOutcome;
	@:go.name("ReadOrphanCandidates")
	@:go.valueError
	static function readOrphanCandidates(beadsDir:String, options:NativeIssueListOptions, global:Bool):Result<NativeOrphanCandidates>;

	@:go.name("ValidateOpen")
	@:go.valueError
	static function validateOpen(beadsDir:String, global:Bool):Result<Bool>;

	@:go.name("ReadInfo")
	@:go.valueError
	static function readInfo(beadsDir:String, includeSchema:Bool, global:Bool):Result<NativeInfo>;

	@:go.name("CheckPing")
	@:go.valueError
	static function checkPing(beadsDir:String, global:Bool):Result<NativePing>;

	@:go.name("ReadStatus")
	@:go.valueError
	static function readStatus(beadsDir:String, skipBlocked:Bool, assignee:String, global:Bool):Result<NativeStatus>;

	@:go.name("ReadIssueListOutcome")
	static function readIssueListOutcome(beadsDir:String, options:NativeIssueListOptions, global:Bool):NativeIssueListOutcome;

	@:go.name("ReadIssueListFormatOutcome")
	static function readIssueListFormatOutcome(beadsDir:String, options:NativeIssueListOptions, global:Bool, format:String):NativeIssueListFormatOutcome;

	@:go.name("ReadIssueSummary")
	@:go.valueError
	static function readIssueSummary(beadsDir:String, id:String, global:Bool):Result<NativeIssueLookup>;

	@:go.name("ReadIssueDetails")
	@:go.valueError
	static function readIssueDetails(beadsDir:String, id:String, options:NativeIssueDetailsOptions, global:Bool):Result<NativeIssueDetailsLookup>;

	@:go.name("ReadIssueDependents")
	@:go.valueError
	static function readIssueDependents(beadsDir:String, id:String, global:Bool):Result<NativeIssueDependencyRows>;

	@:go.name("FindAssignedIssue")
	@:go.valueError
	static function findAssignedIssue(beadsDir:String, actor:String, status:String, global:Bool):Result<String>;

	@:go.name("SearchIssueIDs")
	@:go.valueError
	static function searchIssueIds(beadsDir:String, query:String, global:Bool):Result<NativeIssueIDs>;
}
