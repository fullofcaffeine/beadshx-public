package beadshx.store;

/** Typed request factories for internal Haxe application queries. */
final class IssueListRequests {
	/** Fetch copied rows from which Haxe reconstructs molecule membership. */
	public static function moleculeCandidates():IssueListRequest {
		return request("", "");
	}

	/** Fetch one exact full issue row without presentation filters. */
	public static function exact(id:String):IssueListRequest {
		return request("", id);
	}

	/** Fetch complete rows plus blocker annotations for `ready --explain`. */
	public static function readyExplainCandidates():IssueListRequest {
		return request("", "", true);
	}

	/** Preserve the caller's filters while selecting all direct children. */
	public static function descendants(source:IssueListRequest, parentId:String):IssueListRequest {
		return {
			status: source.status,
			issueType: source.issueType,
			assignee: source.assignee,
			titleSearch: source.titleSearch,
			specPrefix: source.specPrefix,
			idFilter: source.idFilter,
			labels: source.labels,
			labelsAny: source.labelsAny,
			excludeLabels: source.excludeLabels,
			labelPattern: source.labelPattern,
			labelRegex: source.labelRegex,
			titleContains: source.titleContains,
			descriptionContains: source.descriptionContains,
			notesContains: source.notesContains,
			externalContains: source.externalContains,
			externalRef: source.externalRef,
			timeFilters: source.timeFilters,
			priority: source.priority,
			priorityMin: source.priorityMin,
			priorityMax: source.priorityMax,
			all: source.all,
			ready: source.ready,
			noAssignee: source.noAssignee,
			noLabels: source.noLabels,
			emptyDescription: source.emptyDescription,
			skipLabels: source.skipLabels,
			brief: source.brief,
			pinned: source.pinned,
			noPinned: source.noPinned,
			includeTemplates: source.includeTemplates,
			includeGates: source.includeGates,
			includeInfra: source.includeInfra,
			excludeTypes: source.excludeTypes,
			parentId: parentId,
			noParent: source.noParent,
			moleculeType: source.moleculeType,
			wispType: source.wispType,
			deferred: source.deferred,
			overdue: source.overdue,
			metadataFields: source.metadataFields,
			hasMetadataKey: source.hasMetadataKey,
			format: source.format,
			sortBy: source.sortBy,
			reverse: source.reverse,
			limit: IntPresent(0),
			offset: IntPresent(0),
			maxRows: source.maxRows,
			maxRowsSource: source.maxRowsSource,
			skipCounts: source.skipCounts,
			blockingAnnotations: source.blockingAnnotations
		};
	}

	static function request(parentId:String, idFilter:String, blockingAnnotations:Bool = false):IssueListRequest {
		return {
			status: "",
			issueType: "",
			assignee: "",
			titleSearch: "",
			specPrefix: "",
			idFilter: idFilter,
			labels: [],
			labelsAny: [],
			excludeLabels: [],
			labelPattern: "",
			labelRegex: "",
			titleContains: "",
			descriptionContains: "",
			notesContains: "",
			externalContains: "",
			externalRef: "",
			timeFilters: [],
			priority: IntAbsent,
			priorityMin: IntAbsent,
			priorityMax: IntAbsent,
			all: true,
			ready: false,
			noAssignee: false,
			noLabels: false,
			emptyDescription: false,
			skipLabels: false,
			brief: false,
			pinned: false,
			noPinned: false,
			includeTemplates: true,
			includeGates: true,
			includeInfra: true,
			excludeTypes: [],
			parentId: parentId,
			noParent: false,
			moleculeType: "",
			wispType: "",
			deferred: false,
			overdue: false,
			metadataFields: [],
			hasMetadataKey: "",
			format: "",
			sortBy: "priority",
			reverse: false,
			limit: IntPresent(0),
			offset: IntAbsent,
			maxRows: IntAbsent,
			maxRowsSource: "",
			skipCounts: false,
			blockingAnnotations: blockingAnnotations
		};
	}
}
