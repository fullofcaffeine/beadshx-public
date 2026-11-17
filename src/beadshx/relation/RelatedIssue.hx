package beadshx.relation;

import beadshx.store.IssueRecord;
import beadshx.store.IssueLongFields;

/** Complete neighbor payload; relation reads preserve labels and extended issue fields. */
typedef RelatedIssue = {
	> IssueRecord,
	final labels:Array<String>;
	final longFields:IssueLongFields;
	final dependencyType:String;
}

/** Copy only the public issue payload, keeping storage and detail-view fields out of relations. */
function relatedIssue(issue:IssueRecord, labels:Array<String>, longFields:IssueLongFields, dependencyType:String):RelatedIssue {
	return {
		id: issue.id,
		title: issue.title,
		description: issue.description,
		design: issue.design,
		acceptanceCriteria: issue.acceptanceCriteria,
		notes: issue.notes,
		specId: issue.specId,
		status: issue.status,
		priority: issue.priority,
		issueType: issue.issueType,
		assignee: issue.assignee,
		owner: issue.owner,
		estimatedMinutes: issue.estimatedMinutes,
		createdAt: issue.createdAt,
		createdBy: issue.createdBy,
		updatedAt: issue.updatedAt,
		startedAt: issue.startedAt,
		closedAt: issue.closedAt,
		closeReason: issue.closeReason,
		closedBySession: issue.closedBySession,
		dueAt: issue.dueAt,
		deferUntil: issue.deferUntil,
		externalRef: issue.externalRef,
		sourceSystem: issue.sourceSystem,
		metadata: issue.metadata,
		wispType: issue.wispType,
		moleculeType: issue.moleculeType,
		labels: labels.copy(),
		// Upstream ScanIssueFrom does not hydrate the derived blocked annotation.
		longFields: {
			isBlocked: false,
			leaseExpiresAt: longFields.leaseExpiresAt,
			heartbeatAt: longFields.heartbeatAt,
			leaseGrantedNode: longFields.leaseGrantedNode,
			compactionLevel: longFields.compactionLevel,
			compactedAt: longFields.compactedAt,
			compactedAtCommit: longFields.compactedAtCommit,
			originalSize: longFields.originalSize,
			sender: longFields.sender,
			ephemeral: longFields.ephemeral,
			noHistory: longFields.noHistory,
			storageClass: longFields.storageClass,
			pinned: longFields.pinned,
			template: longFields.template,
			bondedFrom: longFields.bondedFrom,
			awaitType: longFields.awaitType,
			awaitId: longFields.awaitId,
			timeout: longFields.timeout,
			timeoutNanos: longFields.timeoutNanos,
			waiters: longFields.waiters,
			sourceFormula: longFields.sourceFormula,
			sourceLocation: longFields.sourceLocation,
			workType: longFields.workType,
			eventKind: longFields.eventKind,
			actor: longFields.actor,
			target: longFields.target,
			payload: longFields.payload
		},
		dependencyType: dependencyType
	};
}
