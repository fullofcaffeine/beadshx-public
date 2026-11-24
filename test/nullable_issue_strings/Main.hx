import beadshx.cli.Application;
import beadshx.cli.EnvironmentPort;
import beadshx.cli.JsonSettingPort;
import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.DatabaseVariableSelection;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.cli.OutputPort;
import beadshx.cli.Parser;
import beadshx.cli.WatchPort;
import beadshx.git.GoGitHistory;
import beadshx.identity.SystemActor;
import beadshx.profile.GoProfiler;
import beadshx.relation.RelatedIssue.relatedIssue;
import beadshx.store.EpicProgress;
import beadshx.store.GoReadonlyStore;
import beadshx.store.IssueDetails;
import beadshx.store.JsonInteger;
import beadshx.store.OptionalInt;
import beadshx.store.StoredMetadata;
import beadshx.store.StoreResult;
import beadshx.workspace.GoWorkspace;

private typedef PresenceCase = {
	final name:String;
	final value:Null<String>;
	final externalJson:Null<String>;
	final commitJson:Null<String>;
	final externalHuman:Null<String>;
	final commitHuman:Null<String>;
}

/** Pinned pointer-string JSON and human output have distinct empty-value rules. */
@:access(beadshx.cli.Application)
@:goNative
class Main {
	static final failures = new Array<String>();

	static function main():Void {
		final cases:Array<PresenceCase> = [
			{
				name: "NULL",
				value: null,
				externalJson: null,
				commitJson: null,
				externalHuman: null,
				commitHuman: null
			},
			{
				name: "present empty",
				value: "",
				externalJson: '"external_ref": ""',
				commitJson: '"compacted_at_commit": ""',
				externalHuman: null,
				commitHuman: "  Compacted at commit: "
			},
			{
				name: "present text",
				value: "ref-17",
				externalJson: '"external_ref": "ref-17"',
				commitJson: '"compacted_at_commit": "ref-17"',
				externalHuman: "External: ref-17",
				commitHuman: "  Compacted at commit: ref-17"
			}
		];
		#if (go || go_output)
		final application = new Application(new Parser(new EmptyEnvironment(), new UnsetJsonSetting()), new NoEffectOutput(), new SystemActor(),
			new GoGitHistory(), new GoWorkspace(), new GoReadonlyStore(), new GoProfiler(), new UnusedWatch());
		#end
		for (testCase in cases) {
			final issue = details(testCase.value);
			final shared = fieldsOf(Application.renderIssueRecordFields(issue, "    "));
			final raw = fieldsOf(Application.renderRawIssueFields(issue));
			final related = relatedIssue(issue, [], issue.longFields, "blocks");
			final nested = fieldsOf(Application.renderRawIssueFields(related));
			checkField(shared, "external_ref", testCase.externalJson, testCase.name + " shared JSON");
			checkField(raw, "external_ref", testCase.externalJson, testCase.name + " raw JSON");
			checkField(raw, "compacted_at_commit", testCase.commitJson, testCase.name + " raw JSON");
			checkField(nested, "external_ref", testCase.externalJson, testCase.name + " related JSON");
			checkField(nested, "compacted_at_commit", testCase.commitJson, testCase.name + " related JSON");
			#if (go || go_output)
			checkLine(humanOf(application.renderIssueHuman(issue, false, true)), "External:", testCase.externalHuman, testCase.name + " human reference");
			#end
			checkLine(Application.renderIssueLongExtras(issue), "  Compacted at commit:", testCase.commitHuman, testCase.name + " human commit");
		}
		#if (go || go_output)
		// A synthetically invalid domain value must fail before any output side effect.
		final outsideNative = switch JsonInteger.parse("9223372036854775808") {
			case Success(value): value;
			case Failure(message): throw message;
		};
		switch application.renderIssueHuman(details(null, 1, outsideNative), false, true) {
			case Failure(message):
				check(message != "", "out-of-native-range rendering must explain failure");
			case Success(_):
				failures.push("out-of-native-range compaction must fail rendering");
		}
		#end

		for (decimal in ["0", "9007199254740993", "9223372036854775807", "-9223372036854775808"]) {
			final count = switch JsonInteger.parse(decimal) {
				case Success(value): value;
				case Failure(message): throw message;
			};
			final rendered = humanOf(Application.renderShowJson([details(null, 0, null, count)]));
			check(rendered.indexOf('"comment_count": $decimal') >= 0, "detail count retains exact numeric token " + decimal);
			check(rendered.indexOf('"comment_count": "$decimal"') < 0, "detail count is not a JSON string " + decimal);
		}

		final withoutCompaction = details("", 0);
		check(Application.renderIssueLongExtras(withoutCompaction).indexOf("COMPACTION") < 0, "zero compaction level must hide the entire section");
		#if (go || go_output)
		SqlPresence.check(failures);
		NativePresence.check(failures);
		#end
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("nullable issue string contracts: PASS");
	}

	static function humanOf(result:StoreResult<String>):String {
		return switch result {
			case Success(value): value;
			case Failure(message): throw message;
		};
	}

	static function fieldsOf(result:StoreResult<Array<String>>):Array<String> {
		return switch result {
			case Success(fields): fields;
			case Failure(message): throw message;
		};
	}

	static function checkField(fields:Array<String>, key:String, expected:Null<String>, label:String):Void {
		final prefix = '"$key":';
		final actual = [for (field in fields) if (StringTools.startsWith(field, prefix)) field];
		check(expected == null ? actual.length == 0 : actual.length == 1 && actual[0] == expected, label + " " + key);
	}

	static function checkLine(text:String, prefix:String, expected:Null<String>, label:String):Void {
		final actual = [for (line in text.split("\n")) if (StringTools.startsWith(line, prefix)) line];
		check(expected == null ? actual.length == 0 : actual.length == 1 && actual[0] == expected, label);
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			failures.push(message);
	}

	static function details(value:Null<String>, compactionLevel:Int = 1, originalSize:Null<JsonInteger> = null,
			commentCount:Null<JsonInteger> = null):IssueDetails {
		final zero = switch JsonInteger.parse("0") {
			case Success(parsed): parsed;
			case Failure(message): throw message;
		};
		return {
			id: "issue-1",
			title: "Presence",
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: "open",
			priority: 1,
			issueType: "task",
			assignee: "",
			owner: "",
			estimatedMinutes: beadshx.store.OptionalIssueInteger.IntegerAbsent,
			createdAt: "2026-01-01T00:00:00Z",
			createdBy: "",
			updatedAt: "2026-01-01T00:00:00Z",
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: value,
			sourceSystem: "",
			metadata: StoredMetadata.fromSql(null),
			wispType: "",
			moleculeType: "",
			labels: [],
			dependencies: [],
			dependents: [],
			comments: [],
			parent: "",
			dependentCount: 0,
			dependencyCount: 0,
			commentCount: commentCount == null ? zero : commentCount,
			commentsOmitted: false,
			epicProgress: NoEpicProgress,
			revision: zero,
			longFields: {
				isBlocked: false,
				leaseExpiresAt: "",
				heartbeatAt: "",
				leaseGrantedNode: "",
				compactionLevel: compactionLevel,
				compactedAt: "",
				compactedAtCommit: value,
				originalSize: originalSize == null ? JsonInteger.fromInt(0) : originalSize,
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
			}
		};
	}
}

private final class EmptyEnvironment implements EnvironmentPort {
	public function new() {}

	public function value(name:String):String
		return "";

	public function selectWorkspace(selection:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection {
		return NoVariable;
	}
}

/** This contract renders directly and parses no arguments. */
private final class UnsetJsonSetting implements JsonSettingPort {
	public function new() {}

	public function enabled(selection:WorkspaceSelection):Bool
		return false;
}

private final class NoEffectOutput implements OutputPort {
	public function new() {}

	public function writeStdout(value:String):Void
		throw "unexpected output";

	public function writeStderr(value:String):Void
		throw "unexpected error output";

	public function renderMarkdown(value:String):String
		return value;

	public function usesJsonEnvelope():Bool
		return false;

	public function shouldEmitJsonDeprecation():Bool
		return false;

	public function isStdoutTerminal():Bool
		return false;

	public function isStderrTerminal():Bool
		return false;

	public function stdoutColumns():Int
		return 0;

	public function displayWidth(value:String):Int
		return value.length;
}

private final class UnusedWatch implements WatchPort {
	public function new() {}

	public function start():Void
		throw "unexpected watch start";

	public function waitForStop():Bool
		throw "unexpected watch wait";

	public function close():Void
		throw "unexpected watch close";
}
