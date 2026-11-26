package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.relation.DependencyRead.compareUtf8;
import beadshx.store.CustomConfig.CustomStatus;
import beadshx.store.CustomConfig.effectiveCustomStatuses;
import beadshx.store.CustomConfig.effectiveCustomTypes;
import beadshx.store.CustomConfig.goTrimSpace;

/** The config.yaml and BD_ lists (upstream getConfigList) that the list configuration reads beside the database. */
typedef IssueListConfigLayers = {
	/** `types.custom` (upstream config.GetCustomTypesFromYAML). */
	final customTypes:Array<String>;

	/** `status.custom` (upstream config.GetCustomStatusesFromYAML). */
	final customStatuses:Array<String>;

	/** `types.infra` (upstream config.GetInfraTypesFromYAML). */
	final infraTypes:Array<String>;
}

/** Upstream workapi.ListConfig: what BuildListFilter reads from the workspace. */
typedef IssueListConfig = {
	final customStatuses:Array<CustomStatus>;
	final customTypes:Array<String>;

	/** Never empty: upstream's resolution ends at the default infra types. */
	final infraTypes:Array<String>;
}

/** A pointer-to-bool filter field of upstream types.IssueFilter. */
enum IssueFilterFlag {
	FlagUnset;
	FlagTrue;
	FlagFalse;
}

/** One time predicate, its value formatted as upstream binds it (RFC3339). */
typedef IssueFilterTime = {
	final column:String;
	final op:String;
	final value:String;
}

/** One table family of the counts query (upstream sqlbuild.FilterTables). */
typedef IssueFilterTables = {
	final main:String;
	final labels:String;
	final dependencies:String;
	final comments:String;
}

/** WHERE fragments and their arguments, in placeholder order. */
typedef IssueFilterClauses = {
	final clauses:Array<String>;
	final arguments:Array<Dynamic>;
}

/** Upstream types.IssueFilter, as far as workapi.BuildListFilter fills it for a list request, and BuildCountFilter for a count. */
@:goNative
final class IssueSearchFilter {
	public var limit = 0;
	public var maxRows = 0;
	public var maxRowsSource = "";
	public var sortBy = "";
	public var sortDesc = false;
	public var status:Null<String> = null;
	public var statuses = new Array<String>();
	public var excludeStatus = new Array<String>();
	public var priority = OptionalInt.IntAbsent;
	public var priorityMin = OptionalInt.IntAbsent;
	public var priorityMax = OptionalInt.IntAbsent;
	public var assignee:Null<String> = null;
	public var issueType:Null<String> = null;
	public var labels = new Array<String>();
	public var labelsAny = new Array<String>();
	public var excludeLabels = new Array<String>();
	public var labelPattern = "";
	public var labelRegex = "";
	public var titleSearch = "";
	public var titleContains = "";
	public var descriptionContains = "";
	public var notesContains = "";
	public var externalRefContains = "";
	public var externalRef:Null<String> = null;
	public var ids = new Array<String>();
	public var specIdPrefix = "";
	public var times = new Array<IssueFilterTime>();
	public var emptyDescription = false;
	public var noAssignee = false;
	public var noLabels = false;
	public var skipLabels = false;
	public var skipCounts = false;
	public var lite = false;
	public var pinned = IssueFilterFlag.FlagUnset;
	public var isTemplate = IssueFilterFlag.FlagUnset;
	public var ephemeral = IssueFilterFlag.FlagUnset;
	public var excludeTypes = new Array<String>();
	public var skipWisps = false;
	public var parentId:Null<String> = null;
	public var noParent = false;
	public var molType:Null<String> = null;
	public var wispType:Null<String> = null;
	public var deferred = false;
	public var overdue = false;
	public var metadataFields = new Array<IssueListMetadataFilter>();
	public var hasMetadataKey = "";

	public function new() {}
}

/**
	Ports upstream's list filter: workapi.LoadStoreListConfig and
	BuildListFilter (internal/workapi/list.go), and sqlbuild.BuildIssueFilterClauses
	(internal/storage/sqlbuild/filter.go). The caller owns the transaction.
**/
@:goNative
final class SqlIssueFilter {
	public static final ISSUE_TABLES:IssueFilterTables = {
		main: "issues",
		labels: "labels",
		dependencies: "dependencies",
		comments: "comments"
	};
	public static final WISP_TABLES:IssueFilterTables = {
		main: "wisps",
		labels: "wisp_labels",
		dependencies: "wisp_dependencies",
		comments: "wisp_comments"
	};
	public static final DEPENDENCY_TARGET = "COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external)";

	static final DEFAULT_INFRA_TYPES = ["agent", "role", "message"];
	static final BUILT_IN_STATUSES = ["open", "in_progress", "blocked", "deferred", "closed", "pinned", "hooked"];
	static final BUILT_IN_TYPES = [
		"bug",
		"feature",
		"task",
		"epic",
		"chore",
		"decision",
		"message",
		"molecule",
		"gate",
		"spike",
		"story",
		"milestone",
		"event"
	];
	static final METADATA_KEY_PATTERN = "^[a-zA-Z_][a-zA-Z0-9_./]*$";

	/**
		Upstream LoadStoreListConfig on an embedded store: GetCustomStatusesDetailed,
		GetCustomTypes, and GetInfraTypes (ResolveInfraTypesInTx: the database's
		types.infra list, else the layered one, else the defaults).
	**/
	public static function loadListConfig(context:Context, transaction:Tx, layers:IssueListConfigLayers):IssueListConfig {
		final statuses = effectiveCustomStatuses(SqlCustomConfigReader.readCustomStatuses(context, transaction), layers.customStatuses);
		var customTypes = effectiveCustomTypes(SqlCustomConfigReader.readCustomTypes(context, transaction), layers.customTypes);
		if (customTypes.length == 0)
			customTypes = layers.customTypes;
		return {customStatuses: statuses, customTypes: customTypes, infraTypes: loadInfraTypes(context, transaction, layers)};
	}

	/** Upstream GetInfraTypes (ResolveInfraTypesInTx): the database's types.infra list, else the layered one, else the defaults. */
	public static function loadInfraTypes(context:Context, transaction:Tx, layers:IssueListConfigLayers):Array<String> {
		var infraTypes = new Array<String>();
		switch SqlCustomConfigReader.readSetting(context, transaction, "types.infra") {
			case Success(value):
				infraTypes = commaSeparated(value);
			case Failure(_):
		}
		return fallbackInfraTypes(infraTypes, layers);
	}

	/** The infra types after the database's list: the layered list when it is empty, else the defaults. */
	public static function fallbackInfraTypes(stored:Array<String>, layers:IssueListConfigLayers):Array<String> {
		if (stored.length > 0)
			return stored;
		return layers.infraTypes.length > 0 ? layers.infraTypes : DEFAULT_INFRA_TYPES;
	}

	/**
		Upstream BuildListFilter, with the limit that the list read runs under. A
		--watch or tree caller passes 0. A --ready request first passes upstream's
		ValidateReadyFlagScope, and then selects open issues, whatever the status
		flag says (see SqlReadyWorkReader.fromListFilter for what its query reads).
	**/
	public static function buildListFilter(request:IssueListRequest, limit:Int, config:IssueListConfig):StoreResult<IssueSearchFilter> {
		if (request.ready) {
			final refused = readyFlagScopeError(request);
			if (refused != null)
				return Failure(refused);
		}
		final filter = new IssueSearchFilter();
		// SQLLimit: --sort id fetches every row and trims after the natural order.
		filter.limit = request.sortBy == "id" ? 0 : limit;
		filter.sortBy = request.sortBy;
		filter.sortDesc = request.reverse;
		switch request.maxRows {
			case IntPresent(value):
				filter.maxRows = value;
				filter.maxRowsSource = request.maxRowsSource;
			case IntAbsent:
		}

		final statusParts = request.status == "" ? [] : [for (part in request.status.split(",")) goTrimSpace(part)];
		final statusAll = statusParts.length == 1 && statusParts[0] == "all";
		final customStatusNames = [for (status in config.customStatuses) status.name];
		if (request.ready)
			filter.status = "open";
		else if (statusParts.length > 0 && !statusAll) {
			final applied = applyStatusParts(filter, statusParts, customStatusNames);
			if (applied != null)
				return Failure(applied);
		}
		if (statusParts.length == 0 && !request.all && !request.ready && !request.pinned) {
			filter.excludeStatus = ["closed", "pinned"];
			for (status in config.customStatuses)
				if (status.category == "done" || status.category == "frozen")
					filter.excludeStatus.push(status.name);
		}

		filter.priority = request.priority;
		if (request.assignee != "")
			filter.assignee = request.assignee;
		if (request.issueType != "") {
			if (BUILT_IN_TYPES.indexOf(request.issueType) < 0 && config.customTypes.indexOf(request.issueType) < 0) {
				var validTypes = "bug, feature, task, epic, chore, decision";
				if (config.customTypes.length > 0)
					validTypes += ", " + config.customTypes.join(", ");
				return Failure('invalid issue type ${StrconvPkg.quote(request.issueType)} (valid: ${validTypes})');
			}
			filter.issueType = request.issueType;
		}

		filter.labels = request.labels;
		filter.labelsAny = request.labelsAny;
		filter.excludeLabels = request.excludeLabels;
		filter.labelPattern = request.labelPattern;
		filter.labelRegex = request.labelRegex;
		filter.titleSearch = request.titleSearch;
		if (request.idFilter != "")
			filter.ids = normalizedEntries(request.idFilter.split(","));
		filter.specIdPrefix = request.specPrefix;
		filter.titleContains = request.titleContains;
		filter.descriptionContains = request.descriptionContains;
		filter.notesContains = request.notesContains;
		filter.externalRefContains = request.externalContains;
		if (request.externalRef != "")
			filter.externalRef = request.externalRef;
		switch filterTimes(request.timeFilters) {
			case Failure(message):
				return Failure(message);
			case Success(times):
				filter.times = times;
		}
		filter.emptyDescription = request.emptyDescription;
		filter.noAssignee = request.noAssignee;
		filter.noLabels = request.noLabels;
		filter.skipLabels = request.skipLabels;
		filter.skipCounts = request.skipCounts;
		filter.lite = request.brief;
		filter.priorityMin = request.priorityMin;
		filter.priorityMax = request.priorityMax;

		if (request.pinned)
			filter.pinned = FlagTrue;
		else if (request.noPinned || (!statusSelectsPinned(statusParts, !request.ready) && !request.all))
			filter.pinned = FlagFalse;

		final infraRequested = config.infraTypes.indexOf(request.issueType) >= 0;
		// applyTypeSuppressions; this request has no IncludeAllTypes.
		if (!request.includeTemplates)
			filter.isTemplate = FlagFalse;
		if (!request.includeGates && request.issueType != "gate")
			filter.excludeTypes.push("gate");
		if (!request.includeInfra && !infraRequested)
			for (infraType in config.infraTypes)
				filter.excludeTypes.push(infraType);
		if (!request.includeInfra && (request.issueType == "" || !infraRequested))
			filter.skipWisps = true;

		for (raw in request.excludeTypes)
			for (part in raw.split(",")) {
				final excluded = goTrimSpace(part);
				if (excluded != "")
					filter.excludeTypes.push(normalizeIssueType(excluded));
			}
		if (infraRequested)
			filter.ephemeral = FlagTrue;
		if (request.parentId != "")
			filter.parentId = request.parentId;
		filter.noParent = request.noParent;
		if (request.moleculeType != "")
			filter.molType = request.moleculeType;
		if (request.wispType != "")
			filter.wispType = request.wispType;
		filter.deferred = request.deferred;
		filter.overdue = request.overdue;
		filter.metadataFields = request.metadataFields;
		filter.hasMetadataKey = request.hasMetadataKey;
		final metadataError = metadataFilterError(request.metadataFields, request.hasMetadataKey);
		if (metadataError != null)
			return Failure(metadataError);
		return Success(filter);
	}

	/** Upstream ValidateMetadataFilters: the key filter first, then the field keys in byte order; null when they are valid. */
	public static function metadataFilterError(fields:Array<IssueListMetadataFilter>, hasKey:String):Null<String> {
		if (hasKey != "" && !validMetadataKey(hasKey))
			return 'invalid metadata key filter: ${metadataKeyError(hasKey)}';
		for (field in sortedMetadataFields(fields))
			if (!validMetadataKey(field.key))
				return 'invalid metadata field key: ${metadataKeyError(field.key)}';
		return null;
	}

	/**
		Upstream issueops.ValidateReadyFlagScope: the list flags that the ready
		query cannot carry, named in upstream's order; null when none is set.
	**/
	static function readyFlagScopeError(request:IssueListRequest):Null<String> {
		final named = new Array<String>();
		function check(set:Bool, name:String, flag:String):Void {
			if (set)
				named.push('$name ($flag)');
		}
		function time(name:String, flag:String, matches:IssueListTimeFilter->Bool):Void {
			check(Lambda.exists(request.timeFilters, matches), name, flag);
		}
		check(request.idFilter != "", "IDFilter", "--id");
		check(request.titleSearch != "", "TitleSearch", "--title");
		check(request.specPrefix != "", "SpecPrefix", "--spec");
		check(request.titleContains != "", "TitleContains", "--title-contains");
		check(request.descriptionContains != "", "DescContains", "--desc-contains");
		check(request.notesContains != "", "NotesContains", "--notes-contains");
		check(request.externalContains != "", "ExternalContains", "--external-contains");
		check(request.externalRef != "", "ExternalRef", "--external-ref");
		time("CreatedAfter", "--created-after", filter -> filter.match(CreatedAfter(_)));
		time("CreatedBefore", "--created-before", filter -> filter.match(CreatedBefore(_)));
		time("UpdatedAfter", "--updated-after", filter -> filter.match(UpdatedAfter(_)));
		time("UpdatedBefore", "--updated-before", filter -> filter.match(UpdatedBefore(_)));
		time("ClosedAfter", "--closed-after", filter -> filter.match(ClosedAfter(_)));
		time("ClosedBefore", "--closed-before", filter -> filter.match(ClosedBefore(_)));
		time("DeferAfter", "--defer-after", filter -> filter.match(DeferAfter(_)));
		time("DeferBefore", "--defer-before", filter -> filter.match(DeferBefore(_)));
		time("DueAfter", "--due-after", filter -> filter.match(DueAfter(_)));
		time("DueBefore", "--due-before", filter -> filter.match(DueBefore(_)));
		check(request.deferred, "DeferredFlag", "--deferred");
		check(request.overdue, "OverdueFlag", "--overdue");
		check(request.emptyDescription, "EmptyDesc", "--empty-description");
		check(request.noLabels, "NoLabels", "--no-labels");
		check(request.noParent, "NoParent", "--no-parent");
		check(request.pinned, "PinnedFlag", "--pinned");
		check(request.priorityMin.match(IntPresent(_)), "PriorityMin", "--priority-min");
		check(request.priorityMax.match(IntPresent(_)), "PriorityMax", "--priority-max");
		if (named.length == 0)
			return null;
		return 'validation failed: --ready cannot filter on ${named.join(", ")}; the blocker-aware ready query carries only part of the list vocabulary, '
			+ "so answering would return every ready issue rather than the ones asked for — drop --ready, or drop what it cannot carry";
	}

	/** Upstream BuildIssueFilterClauses for a search without query text. */
	public static function buildFilterClauses(filter:IssueSearchFilter, tables:IssueFilterTables):IssueFilterClauses {
		final clauses = new Array<String>();
		final arguments = new Array<Dynamic>();
		function like(column:String, value:String):Void {
			if (value == "")
				return;
			clauses.push('LOWER($column) LIKE ?');
			arguments.push('%${value.toLowerCase()}%');
		}
		function placeholders(values:Array<String>):String {
			for (value in values)
				arguments.push(value);
			return [for (_ in values) "?"].join(",");
		}
		like("title", filter.titleSearch);
		like("title", filter.titleContains);
		like("description", filter.descriptionContains);
		like("notes", filter.notesContains);
		like("external_ref", filter.externalRefContains);
		if (filter.externalRef != null) {
			clauses.push("external_ref = ?");
			arguments.push(filter.externalRef);
		}
		if (filter.status != null) {
			clauses.push("status = ?");
			arguments.push(filter.status);
		}
		if (filter.statuses.length > 0)
			clauses.push('status IN (${placeholders(filter.statuses)})');
		if (filter.excludeStatus.length > 0)
			clauses.push('status NOT IN (${placeholders(filter.excludeStatus)})');
		if (filter.issueType != null) {
			clauses.push("issue_type = ?");
			arguments.push(filter.issueType);
		}
		if (filter.excludeTypes.length > 0)
			clauses.push('issue_type NOT IN (${placeholders(filter.excludeTypes)})');
		if (filter.assignee != null) {
			clauses.push("assignee = ?");
			arguments.push(filter.assignee);
		}
		for (bound in [
			{value: filter.priority, clause: "priority = ?"},
			{value: filter.priorityMin, clause: "priority >= ?"},
			{value: filter.priorityMax, clause: "priority <= ?"}
		])
			switch bound.value {
				case IntPresent(value):
					clauses.push(bound.clause);
					arguments.push(value);
				case IntAbsent:
			}
		if (filter.ids.length > 0) {
			for (id in filter.ids)
				arguments.push(id);
			clauses.push('id IN (${[for (_ in filter.ids) "?"].join(", ")})');
		}
		if (filter.specIdPrefix != "") {
			clauses.push("spec_id LIKE ?");
			arguments.push(filter.specIdPrefix + "%");
		}
		if (filter.parentId != null) {
			clauses.push('(id IN (SELECT issue_id FROM ${tables.dependencies} WHERE type = \'parent-child\' AND $DEPENDENCY_TARGET = ?)'
				+ ' OR (id LIKE CONCAT(?, \'.%\') AND id NOT IN (SELECT issue_id FROM ${tables.dependencies} WHERE type = \'parent-child\')))');
			arguments.push(filter.parentId);
			arguments.push(filter.parentId);
		}
		if (filter.noParent)
			clauses.push('id NOT IN (SELECT issue_id FROM ${tables.dependencies} WHERE type = \'parent-child\')');
		if (filter.molType != null) {
			clauses.push("mol_type = ?");
			arguments.push(filter.molType);
		}
		if (filter.wispType != null) {
			clauses.push("wisp_type = ?");
			arguments.push(filter.wispType);
		}
		for (label in filter.labels) {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label = ?)');
			arguments.push(label);
		}
		if (filter.labelsAny.length > 0) {
			for (label in filter.labelsAny)
				arguments.push(label);
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label IN (${[for (_ in filter.labelsAny) "?"].join(", ")}))');
		}
		if (filter.excludeLabels.length > 0) {
			for (label in filter.excludeLabels)
				arguments.push(label);
			clauses.push('id NOT IN (SELECT issue_id FROM ${tables.labels} WHERE label IN (${[for (_ in filter.excludeLabels) "?"].join(", ")}))');
		}
		if (filter.noLabels)
			clauses.push('id NOT IN (SELECT DISTINCT issue_id FROM ${tables.labels})');
		if (filter.labelPattern != "") {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label LIKE ? ESCAPE \'|\')');
			arguments.push(globToLikePattern(filter.labelPattern));
		}
		if (filter.labelRegex != "") {
			clauses.push('id IN (SELECT issue_id FROM ${tables.labels} WHERE label REGEXP ?)');
			arguments.push(filter.labelRegex);
		}
		switch filter.pinned {
			case FlagTrue:
				clauses.push("pinned = 1");
			case FlagFalse:
				clauses.push("(pinned = 0 OR pinned IS NULL)");
			case FlagUnset:
		}
		switch filter.ephemeral {
			case FlagTrue:
				clauses.push("ephemeral = 1");
			case FlagFalse:
				clauses.push("(ephemeral = 0 OR ephemeral IS NULL)");
			case FlagUnset:
		}
		switch filter.isTemplate {
			case FlagTrue:
				clauses.push("is_template = 1");
			case FlagFalse:
				clauses.push("(is_template = 0 OR is_template IS NULL)");
			case FlagUnset:
		}
		if (filter.emptyDescription)
			clauses.push("(description IS NULL OR description = '')");
		if (filter.noAssignee)
			clauses.push("(assignee IS NULL OR assignee = '')");
		for (time in filter.times) {
			clauses.push('${time.column} ${time.op} ?');
			arguments.push(time.value);
		}
		if (filter.deferred) {
			clauses.push("(defer_until IS NOT NULL OR status = ?)");
			arguments.push("deferred");
		}
		if (filter.overdue) {
			clauses.push("due_at IS NOT NULL AND due_at < ? AND status != ?");
			arguments.push(TimePkg.now().utc().format(GO_RFC3339));
			arguments.push("closed");
		}
		if (filter.hasMetadataKey != "") {
			clauses.push("JSON_EXTRACT(metadata, ?) IS NOT NULL");
			arguments.push(metadataPath(filter.hasMetadataKey));
		}
		for (field in sortedMetadataFields(filter.metadataFields)) {
			clauses.push("JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?");
			arguments.push(metadataPath(field.key));
			arguments.push(field.value);
		}
		return {clauses: clauses, arguments: arguments};
	}

	static final GO_RFC3339 = "2006-01-02T15:04:05Z07:00";
	static final GO_RFC3339_NANO = "2006-01-02T15:04:05.999999999Z07:00";

	/** Upstream applyStatusParts; null when the parts apply. */
	static function applyStatusParts(filter:IssueSearchFilter, parts:Array<String>, customNames:Array<String>):Null<String> {
		final valid = (status:String) -> BUILT_IN_STATUSES.indexOf(status) >= 0 || customNames.indexOf(status) >= 0;
		var validList = "open, in_progress, blocked, deferred, closed, pinned, hooked";
		if (customNames.length > 0)
			validList += ", " + customNames.join(", ");
		if (parts.length == 1) {
			if (!valid(parts[0]))
				return 'invalid status ${StrconvPkg.quote(parts[0])} (valid: ${validList})';
			filter.status = parts[0];
			return null;
		}
		for (part in parts) {
			if (!valid(part)) {
				if (part == "all")
					return 'status "all" cannot be combined with other statuses';
				return 'invalid status ${StrconvPkg.quote(part)} in multi-status filter (valid: ${validList})';
			}
			filter.statuses.push(part);
		}
		return null;
	}

	/** Upstream statusSelectsPinned: pinned or hooked, or all when the status flag applies (not under --ready). */
	static function statusSelectsPinned(parts:Array<String>, allApplies:Bool):Bool {
		for (part in parts)
			switch part {
				case "pinned" | "hooked":
					return true;
				case "all" if (allApplies):
					return true;
				case _:
			}
		return false;
	}

	/** The canonical RFC3339Nano bounds as upstream formats them for SQL: time.RFC3339 in their own offset. */
	public static function filterTimes(filters:Array<IssueListTimeFilter>):StoreResult<Array<IssueFilterTime>> {
		final bounds = new Map<String, String>();
		for (filter in filters) {
			final entry = switch filter {
				case CreatedAfter(value): {key: "created_at >", value: value};
				case CreatedBefore(value): {key: "created_at <", value: value};
				case UpdatedAfter(value): {key: "updated_at >", value: value};
				case UpdatedBefore(value): {key: "updated_at <", value: value};
				case ClosedAfter(value): {key: "closed_at >", value: value};
				case ClosedBefore(value): {key: "closed_at <", value: value};
				case DeferAfter(value): {key: "defer_until >", value: value};
				case DeferBefore(value): {key: "defer_until <", value: value};
				case DueAfter(value): {key: "due_at >", value: value};
				case DueBefore(value): {key: "due_at <", value: value};
			};
			final parsed = TimePkg.parse(GO_RFC3339_NANO, entry.value);
			if (parsed.value2 != null)
				return Failure('invalid canonical list timestamp: ${parsed.value2.text()}');
			bounds.set(entry.key, parsed.value1.format(GO_RFC3339));
		}
		final times = new Array<IssueFilterTime>();
		// Upstream's clause order: created, updated, closed, defer, then due; each after, then before.
		for (key in [
			"created_at >",
			"created_at <",
			"updated_at >",
			"updated_at <",
			"closed_at >",
			"closed_at <",
			"defer_until >",
			"defer_until <",
			"due_at >",
			"due_at <"
		]) {
			final value = bounds.get(key);
			if (value != null) {
				final separator = key.indexOf(" ");
				times.push({column: key.substr(0, separator), op: key.substr(separator + 1), value: value});
			}
		}
		return Success(times);
	}

	/** The metadata predicates of a Go map: each key once, the last value kept, in byte order. */
	public static function sortedMetadataFields(fields:Array<IssueListMetadataFilter>):Array<IssueListMetadataFilter> {
		final values = new Map<String, String>();
		final keys = new Array<String>();
		for (field in fields) {
			if (!values.exists(field.key))
				keys.push(field.key);
			values.set(field.key, field.value);
		}
		keys.sort(compareUtf8);
		return [for (key in keys) {key: key, value: values.get(key)}];
	}

	/** Upstream storage.ValidateMetadataKey's pattern `^[a-zA-Z_][a-zA-Z0-9_./]*$`. */
	static function validMetadataKey(key:String):Bool {
		if (key == "")
			return false;
		for (index in 0...key.length) {
			final code:Int = key.charCodeAt(index);
			final letter = (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || code == "_".code;
			final rest = (code >= "0".code && code <= "9".code) || code == ".".code || code == "/".code;
			if (!(letter || (index > 0 && rest)))
				return false;
		}
		return true;
	}

	static function metadataKeyError(key:String):String {
		return 'invalid metadata key ${StrconvPkg.quote(key)}: must match ${METADATA_KEY_PATTERN}';
	}

	/** Upstream storage.JSONMetadataPath: the key quoted, with `\` and `"` escaped. */
	public static function metadataPath(key:String):String {
		final escaped = StringTools.replace(StringTools.replace(key, "\\", "\\\\"), "\"", "\\\"");
		return "$.\"" + escaped + "\"";
	}

	/** Upstream globToLikePattern: `*` and `?` become `%` and `_`; `%`, `_` and `|` are escaped with `|`. */
	public static function globToLikePattern(pattern:String):String {
		final converted = new StringBuf();
		for (index in 0...pattern.length) {
			final character = pattern.charAt(index);
			switch character {
				case "%" | "_" | "|":
					converted.add("|" + character);
				case "*":
					converted.add("%");
				case "?":
					converted.add("_");
				case _:
					converted.add(character);
			}
		}
		return converted.toString();
	}

	/** Upstream utils.NormalizeLabels: trimmed, empty entries dropped, each kept at its first position. */
	public static function normalizedEntries(entries:Array<String>):Array<String> {
		final seen = new Map<String, Bool>();
		final normalized = new Array<String>();
		for (entry in entries) {
			final trimmed = goTrimSpace(entry);
			if (trimmed == "" || seen.exists(trimmed))
				continue;
			seen.set(trimmed, true);
			normalized.push(trimmed);
		}
		return normalized;
	}

	/** Upstream ParseCommaSeparatedList. */
	static function commaSeparated(value:String):Array<String> {
		return value == "" ? [] : [for (part in value.split(",")) if (goTrimSpace(part) != "") goTrimSpace(part)];
	}

	/** Upstream utils.NormalizeIssueType: a known alias, compared in lower case, becomes its type. */
	public static function normalizeIssueType(value:String):String {
		return switch value.toLowerCase() {
			case "mr": "merge-request";
			case "feat" | "enhancement": "feature";
			case "mol": "molecule";
			case "dec" | "adr": "decision";
			case _: value;
		};
	}
}
