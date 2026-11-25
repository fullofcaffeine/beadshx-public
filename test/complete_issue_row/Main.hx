import beadshx.nativeextern.database.sql.Rows;
import beadshx.store.SqlIssueRow;
import beadshx.store.SqlIssueRow.SqlIssueFields;

private typedef RenderedIssueInput = {
	> beadshx.store.IssueRecord,
	final longFields:beadshx.store.IssueLongFields;
}

/** Native observer supplies actual SQL driver values; authored Haxe owns decoding. */
class DecodedRow {
	public final fields:Null<SqlIssueFields>;
	public final error:String;

	public function new(fields:Null<SqlIssueFields>, error:String) {
		this.fields = fields;
		this.error = error;
	}
}

@:access(beadshx.cli.Application)
@:goNative
class Main {
	public static function decode(rows:Rows):DecodedRow {
		return switch SqlIssueRow.scanSqlIssueFields(rows, "row-contract", beadshx.store.SqlIssueRow.SqlIssueScanOrigin.ScalarDetail) {
			case Failure(message): new DecodedRow(null, message);
			case Success(fields): new DecodedRow(fields, "");
		};
	}

	/** Exercise the actual Application field encoder after native SQL decoding. */
	public static function renderDecoded(fields:SqlIssueFields):String {
		final rare:beadshx.store.IssueLongFields = {
			isBlocked: fields.isBlocked,
			leaseExpiresAt: fields.leaseExpiresAt,
			heartbeatAt: fields.heartbeatAt,
			leaseGrantedNode: fields.leaseGrantedNode,
			compactionLevel: fields.compactionLevel,
			compactedAt: fields.compactedAt,
			compactedAtCommit: fields.compactedAtCommit,
			originalSize: fields.originalSize,
			sender: fields.sender,
			ephemeral: fields.ephemeral,
			noHistory: fields.noHistory,
			storageClass: fields.storageClass,
			pinned: fields.pinned,
			template: fields.template,
			bondedFrom: [],
			awaitType: fields.awaitType,
			awaitId: fields.awaitId,
			timeout: fields.timeout,
			timeoutNanos: fields.timeoutNanos,
			waiters: fields.waiters,
			sourceFormula: "",
			sourceLocation: "",
			workType: fields.workType,
			eventKind: fields.eventKind,
			actor: fields.actor,
			target: fields.target,
			payload: fields.payload,
		};
		final issue:RenderedIssueInput = {
			id: fields.id,
			title: fields.title,
			description: fields.description,
			design: fields.design,
			acceptanceCriteria: fields.acceptanceCriteria,
			notes: fields.notes,
			specId: fields.specId,
			status: fields.status,
			priority: fields.priority,
			issueType: fields.issueType,
			assignee: fields.assignee,
			owner: fields.owner,
			estimatedMinutes: fields.estimatedMinutes,
			createdAt: fields.createdAt,
			createdBy: fields.createdBy,
			updatedAt: fields.updatedAt,
			startedAt: fields.startedAt,
			closedAt: fields.closedAt,
			closeReason: fields.closeReason,
			closedBySession: fields.closedBySession,
			dueAt: fields.dueAt,
			deferUntil: fields.deferUntil,
			externalRef: fields.externalRef,
			sourceSystem: fields.sourceSystem,
			metadata: fields.metadata,
			wispType: fields.wispType,
			moleculeType: fields.moleculeType,
			longFields: rare
		};
		return switch beadshx.cli.Application.renderIssueFields(issue) {
			case Failure(message): throw message;
			case Success(encoded): "{" + encoded.join(",") + "}";
		};
	}

	static function main():Void {
		// Native tests supply the real rows; retain this callable in target output.
		if (Sys.args().indexOf("--native-row-observer") >= 0)
			Sys.println(renderDecoded(decode(null).fields));
	}
}
