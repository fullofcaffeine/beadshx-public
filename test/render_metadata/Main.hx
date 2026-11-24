import beadshx.cli.Application;
import beadshx.store.StoredMetadata;
import beadshx.store.StoreResult;
import beadshx.store.JsonInteger;
import beadshx.store.IssueLongFields;
import beadshx.relation.RelatedIssue;
import beadshx.store.OptionalInt;

/** Generic issue JSON must preserve each JSON value accepted by upstream metadata. */
@:access(beadshx.cli.Application)
class Main {
	static function main():Void {
		for (testCase in [
			{raw: '[]', expected: '[]'},
			{raw: '[1,true,null]', expected: '[\n      1,\n      true,\n      null\n    ]'},
			{raw: '"text"', expected: '"text"'},
			{raw: '42', expected: '42'},
			{raw: 'false', expected: 'false'},
			{raw: 'null', expected: 'null'},
			{raw: ' {} ', expected: '{}'},
			{raw: '{"key":1}', expected: '{\n      "key": 1\n    }'}
		]) {
			final metadata = StoredMetadata.fromSql(testCase.raw);
			for (fields in [
				fieldsOf(Application.renderRawIssueFields(issue(metadata))),
				fieldsOf(Application.renderIssueRecordFields(issue(metadata), issue(metadata).longFields, "    "))
			])
				if (fields.indexOf('"metadata": ' + testCase.expected) < 0) {
					Sys.println('metadata mismatch for ${testCase.raw}: ${fields.join("\n")}');
					throw "issue JSON dropped or changed metadata";
				}
		}
		for (raw in [null, "", "{}"]) {
			final absent = issue(StoredMetadata.fromSql(raw));
			for (fields in [
				fieldsOf(Application.renderRawIssueFields(absent)),
				fieldsOf(Application.renderIssueRecordFields(absent, absent.longFields, "    "))
			])
				if (fields.join("\n").indexOf('"metadata": ') >= 0)
					throw "absent metadata must remain omitted";
		}
		Sys.println("generic metadata rendering contracts: PASS");
	}

	static function fieldsOf(result:StoreResult<Array<String>>):Array<String> {
		return switch result {
			case Success(fields): fields;
			case Failure(message): throw message;
		};
	}

	static function issue(metadata:StoredMetadata):RelatedIssue {
		final zero = switch JsonInteger.parse("0") {
			case Success(value): value;
			case Failure(message): throw message;
		};
		final longFields:IssueLongFields = {
			isBlocked: false,
			leaseExpiresAt: "",
			heartbeatAt: "",
			leaseGrantedNode: "",
			compactionLevel: 0,
			compactedAt: "",
			compactedAtCommit: null,
			originalSize: 0,
			sender: "",
			ephemeral: false,
			noHistory: false,
			storageClass: "",
			pinned: false,
			template: false,
			bondedFrom: [],
			awaitType: "",
			awaitId: "",
			timeout: "",
			timeoutNanos: zero,
			waiters: [],
			sourceFormula: "",
			sourceLocation: "",
			workType: "",
			eventKind: "",
			actor: "",
			target: "",
			payload: ""
		};
		return {
			id: "",
			title: "",
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: "",
			priority: 0,
			issueType: "",
			assignee: "",
			owner: "",
			estimatedMinutes: beadshx.store.OptionalIssueInteger.IntegerAbsent,
			createdAt: "",
			createdBy: "",
			updatedAt: "",
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: null,
			sourceSystem: "",
			metadata: metadata,
			wispType: "",
			moleculeType: "",
			longFields: longFields,
			labels: [],
			dependencyType: "blocks"
		};
	}
}
