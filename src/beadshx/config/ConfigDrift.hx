package beadshx.config;

import beadshx.cli.CatalogViews.CatalogField;
import beadshx.cli.CatalogViews.field;
import beadshx.cli.CatalogViews.renderCatalogJson;
import beadshx.store.CustomConfig.goTrimSpace;
import haxe.io.Bytes;

/** Upstream driftStatus values. */
enum DriftStatus {
	DriftOk;
	DriftDetected;
	DriftInfo;
	DriftSkipped;
}

/** One upstream DriftItem; empty expected and actual values are left out of the JSON. */
typedef DriftItem = {
	final check:String;
	final status:DriftStatus;
	final message:String;
	final expected:String;
	final actual:String;
}

/** The bd hooks upstream CheckGitHooks reads, in its order. */
final GIT_HOOK_NAMES = ["pre-commit", "post-merge", "pre-push", "post-checkout", "prepare-commit-msg"];

/** What upstream getHookVersion finds in one hook file. */
typedef HookVersion = {
	final version:String;
	final isShim:Bool;
	final isBdHook:Bool;
}

/** One hook's upstream HookStatus. */
typedef HookStatus = {
	final name:String;
	final installed:Bool;
	final version:String;
	final outdated:Bool;
}

/** bufio.Scanner's default token limit; a longer line fails the read. */
private final MAX_SCAN_LINE_BYTES = 64 * 1024;

/**
	Upstream getHookVersion over a hook file's text: the first line that starts
	with a section marker, a shim marker or a legacy version marker decides;
	without one, the inline marker anywhere makes it an unversioned bd hook.
	Null when bufio.Scanner fails first, on a line of 64 KiB or more, which
	upstream counts as a missing hook.
**/
function hookVersion(content:String):Null<HookVersion> {
	final lines = content.split("\n");
	// A final newline ends the last line; Scanner yields no empty line after it.
	if (lines.length > 0 && lines[lines.length - 1] == "")
		lines.pop();
	for (raw in lines) {
		if (Bytes.ofString(raw).length >= MAX_SCAN_LINE_BYTES)
			return null;
		final line = StringTools.endsWith(raw, "\r") ? raw.substr(0, raw.length - 1) : raw;
		if (StringTools.startsWith(line, "# --- BEGIN BEADS INTEGRATION")) {
			var after = goTrimSpace(line.substr("# --- BEGIN BEADS INTEGRATION".length));
			if (StringTools.startsWith(after, "v"))
				after = after.substr(1);
			if (StringTools.endsWith(after, "---"))
				after = after.substr(0, after.length - 3);
			return {version: goTrimSpace(after), isShim: true, isBdHook: true};
		}
		if (StringTools.startsWith(line, "# bd-shim "))
			return {version: goTrimSpace(line.substr("# bd-shim ".length)), isShim: true, isBdHook: true};
		if (StringTools.startsWith(line, "# bd-hooks-version: "))
			return {version: goTrimSpace(line.substr("# bd-hooks-version: ".length)), isShim: false, isBdHook: true};
	}
	if (content.indexOf("# bd (beads)") >= 0)
		return {version: "", isShim: false, isBdHook: true};
	return {version: "", isShim: false, isBdHook: false};
}

/**
	Upstream CheckGitHooks for one hook: `content` is null when the file cannot
	be read. A thin shim is never outdated; any other bd hook is outdated unless
	its version is `currentVersion`.
**/
function hookStatus(name:String, content:Null<String>, currentVersion:String):HookStatus {
	final found = content == null ? null : hookVersion(content);
	if (found == null)
		return {
			name: name,
			installed: false,
			version: "",
			outdated: false
		};
	return {
		name: name,
		installed: true,
		version: found.version,
		outdated: !found.isShim && found.isBdHook && found.version != currentVersion};
}

/** Upstream checkHooksDrift once the hooks directory resolved. */
function hooksDriftItems(statuses:Array<HookStatus>, currentVersion:String):Array<DriftItem> {
	final missing = [for (status in statuses) if (!status.installed) status.name];
	final outdated = [
		for (status in statuses)
			if (status.installed && status.outdated) '${status.name} (have ${status.version}, want ${currentVersion})'
	];
	final items = new Array<DriftItem>();
	if (missing.length > 0)
		items.push({
			check: "hooks.missing",
			status: DriftDetected,
			message: 'Git hooks not installed: ${missing.join(", ")}',
			expected: "installed",
			actual: "missing"
		});
	if (outdated.length > 0)
		items.push({
			check: "hooks.outdated",
			status: DriftDetected,
			message: 'Git hooks outdated: ${outdated.join(", ")}',
			expected: 'v${currentVersion}',
			actual: "outdated"
		});
	if (items.length == 0)
		items.push(plainItem("hooks", DriftOk, "Git hooks installed and current"));
	return items;
}

/** A drift item without expected and actual values. */
function plainItem(check:String, status:DriftStatus, message:String):DriftItem {
	return {
		check: check,
		status: status,
		message: message,
		expected: "",
		actual: ""
	};
}

/** Upstream checkRemoteDrift when its Dolt store does not open. */
function remoteOpenFailureItem(message:String):DriftItem {
	return plainItem("remote", DriftSkipped, 'Cannot open Dolt store: ${message}');
}

/** Upstream checkServerDrift when dolt.shared-server is off. */
function serverDriftItem(serverRunning:Bool):DriftItem {
	return serverRunning ? plainItem("server", DriftInfo,
		"Dolt server is running but dolt.shared-server is not enabled in config") : plainItem("server", DriftOk, "No shared server configured or running");
}

/** Upstream's error when a server store's dial fails and auto-start is off, as it is for these read-only probes. */
function unreachableServerMessage(address:String, dialError:String, autoStartDisabled:Bool):String {
	final hint = autoStartDisabled ? "Dolt server auto-start is disabled (dolt.auto-start: false).\nStart the server manually:\n  bd dolt start" : "The Dolt server may not be running. Try:\n  bd dolt start";
	return 'Dolt server unreachable at ${address}: ${dialError}\n\n${hint}';
}

/** Upstream testDatabasePrefixes. */
private final TEST_DATABASE_PREFIXES = [
	"testdb_",
	"beads_test",
	"beads_pt",
	"beads_vr",
	"doctest_",
	"doctortest_",
	"benchdb_"
];

/**
	Upstream dolt.New's database-name firewall: a test-named database is not
	opened on any server unless BEADS_TEST_SERVER=1. Null when the open goes on.
**/
function testDatabaseRefusal(database:String, address:String, testServerAllowed:Bool, quote:String->String):Null<String> {
	if (testServerAllowed)
		return null;
	for (prefix in TEST_DATABASE_PREFIXES)
		if (StringTools.startsWith(database, prefix))
			return 'refusing to connect test database ${quote(database)} to server ${address}: '
				+ "set BEADS_TEST_SERVER=1 on a dedicated test server, or use test helpers in internal/storage/dolt/testserver";
	return null;
}

/** Upstream doltserver isFalsyBool: "off" in any case, or a value strconv.ParseBool reads as false, after trimming. */
function isFalsyBool(value:String):Bool {
	final trimmed = goTrimSpace(value);
	return trimmed.toLowerCase() == "off" || ["0", "f", "F", "false", "FALSE", "False"].contains(trimmed);
}

/** Whether any item reports drift, which makes upstream exit 1. */
function hasDrift(items:Array<DriftItem>):Bool {
	for (item in items)
		switch item.status {
			case DriftDetected:
				return true;
			case DriftOk | DriftInfo | DriftSkipped:
		}
	return false;
}

private function statusName(status:DriftStatus):String {
	return switch status {
		case DriftOk: "ok";
		case DriftDetected: "drift";
		case DriftInfo: "info";
		case DriftSkipped: "skipped";
	};
}

private function statusIcon(status:DriftStatus):String {
	return switch status {
		case DriftOk: "✓";
		case DriftDetected: "✗";
		case DriftInfo: "ℹ";
		case DriftSkipped: "–";
	};
}

/** Upstream printDriftItems. */
function renderDriftText(items:Array<DriftItem>):String {
	if (items.length == 0)
		return "No drift checks available\n";
	final rendered = new StringBuf();
	for (item in items) {
		rendered.add('  ${statusIcon(item.status)} ${item.check}: ${item.message}\n');
		if (item.expected != "" || item.actual != "")
			rendered.add('      expected: ${item.expected}\n      actual:   ${item.actual}\n');
	}
	return rendered.toString();
}

/** Upstream outputJSON of the items: DriftItem structs in field order, without schema_version. */
function renderDriftJson(items:Array<DriftItem>):String {
	if (items.length == 0)
		return "null\n";
	return renderCatalogJson(JsonList([
		for (item in items) {
			final fields:Array<CatalogField> = [
				field("check", JsonText(item.check)),
				field("status", JsonText(statusName(item.status))),
				field("message", JsonText(item.message))
			];
			if (item.expected != "") fields.push(field("expected", JsonText(item.expected)));
			if (item.actual != "") fields.push(field("actual", JsonText(item.actual)));
			JsonObject(fields);
		}
	]));
}
