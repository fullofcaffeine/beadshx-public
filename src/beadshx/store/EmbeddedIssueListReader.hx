package beadshx.store;

import beadshx.store.EmbeddedSession.EmbeddedReadWording;
import beadshx.store.SqlBlockingAnnotation.IssueBlocking;
import beadshx.store.SqlIssueFilter.IssueListConfigLayers;
import beadshx.store.SqlIssueListReader.readSqlIssueList;

/**
	Own the read transactions of one list page; the list semantics are authored Haxe.

	The page is one read. A request for blocking annotations, which the human
	list prints, adds a second read, as upstream's list asks its
	BlockingAnnotator after the page. Upstream renders the page undecorated
	when that read fails, so a failure of the second read, of its open or of
	its release leaves the page as it is.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedIssueListReader {
	static final WORDING = EmbeddedReadWording.forNoun("list", false);

	public static function read(beadsDir:String, databaseName:String, request:IssueListRequest, limit:Int, layers:IssueListConfigLayers):IssueListResult {
		final result:IssueListResult = switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> readSqlIssueList(context, transaction, request, limit, layers)) {
			case EmbeddedReadNotStarted(stage, error, _): ListFailure(WORDING.stageMessage(stage, error));
			case EmbeddedReadFinished(result, cleanup): cleanup.length == 0 ? result : ListFailure(WORDING.cleanupMessage(cleanup[0]));
		};
		if (!request.blockingAnnotations)
			return result;
		return switch result {
			case ListSuccess(page): ListSuccess(annotated(beadsDir, databaseName, page));
			case ListFailure(_) | ListRowLimitExceeded(_, _, _): result;
		};
	}

	static function annotated(beadsDir:String, databaseName:String, page:IssueListPage):IssueListPage {
		final ids = [for (item in page.items) item.id];
		final blocking = switch EmbeddedSession.withRead(beadsDir, databaseName,
			(context, transaction) -> SqlBlockingAnnotation.annotate(context, transaction, ids)) {
			case EmbeddedReadFinished(Success(value), cleanup) if (cleanup.length == 0): value;
			case EmbeddedReadFinished(_, _) | EmbeddedReadNotStarted(_, _, _): return page;
		};
		return {items: [for (item in page.items) withBlocking(item, blocking.get(item.id))], hasMore: page.hasMore, formatted: page.formatted};
	}

	static function withBlocking(item:IssueListItem, blocking:Null<IssueBlocking>):IssueListItem {
		if (blocking == null)
			return item;
		return {
			id: item.id,
			title: item.title,
			description: item.description,
			design: item.design,
			acceptanceCriteria: item.acceptanceCriteria,
			notes: item.notes,
			specId: item.specId,
			status: item.status,
			priority: item.priority,
			issueType: item.issueType,
			assignee: item.assignee,
			owner: item.owner,
			estimatedMinutes: item.estimatedMinutes,
			createdAt: item.createdAt,
			createdBy: item.createdBy,
			updatedAt: item.updatedAt,
			startedAt: item.startedAt,
			closedAt: item.closedAt,
			closeReason: item.closeReason,
			closedBySession: item.closedBySession,
			dueAt: item.dueAt,
			deferUntil: item.deferUntil,
			externalRef: item.externalRef,
			sourceSystem: item.sourceSystem,
			metadata: item.metadata,
			wispType: item.wispType,
			moleculeType: item.moleculeType,
			longFields: item.longFields,
			labels: item.labels,
			dependencies: item.dependencies,
			dependencyCount: item.dependencyCount,
			dependentCount: item.dependentCount,
			commentCount: item.commentCount,
			parent: item.parent,
			blockedBy: blocking.blockedBy,
			blocks: blocking.blocks,
			blockingParent: blocking.parent
		};
	}
}
