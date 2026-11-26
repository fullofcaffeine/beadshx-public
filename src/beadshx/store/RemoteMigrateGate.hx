package beadshx.store;

import beadshx.config.LayeredConfig.environmentValue;
import beadshx.store.SchemaSkew.BINARY_SCHEMA_VERSION;

/** Why upstream's smart gate fell back to the blunt stop (upstream `fallbackReason*`). */
enum RemoteGateFallback {
	/** `unreadable-remote-state`: no cached remote ref with content hashes, or the cached remote is behind this clone. */
	UnreadableRemoteState;

	/** `below-convergence-floor`: remote and local agree, but a non-deterministic migration is still pending. */
	BelowConvergenceFloor;

	/** `opted-out`: BD_SMART_GATE is a boolean false. */
	SmartGateOptedOut;

	/** `unparseable-env`: BD_SMART_GATE is set to `value`, which is no boolean. */
	UnparseableSmartGateEnv(value:String);
}

/** The decision that upstream's `RemoteMigrateGateError` carries. */
enum RemoteGateDecision {
	/** The default stop, with the reason why the smart gate could not do better. */
	BluntStop(fallback:RemoteGateFallback);

	/** `adopt`: the remote is already migrated. */
	AdoptStop;

	/** `adopt-ff`: the remote is already migrated, and this clone could fast-forward to it without a loss. */
	AdoptFastForwardStop;

	/** `fork-skew`: this clone and the remote applied different content for these migration versions. */
	ForkSkewStop(versions:Array<Int>);
}

/** Upstream `*schema.RemoteMigrateGateError`. */
typedef RemoteGateStop = {
	final currentVersion:Int;
	final latestVersion:Int;
	final pending:Int;

	/** A BD_ALLOW_REMOTE_MIGRATE value that is set but no boolean, or "". */
	final unrecognizedEnv:String;

	final decision:RemoteGateDecision;
}

/** A write that upstream's open makes where this build stops. */
enum RemoteGateWrite {
	/** BD_ALLOW_REMOTE_MIGRATE is a boolean true: upstream migrates. */
	EscapeHatchMigration;

	/** The cached remote is at the same version, at or above the convergence floor: upstream migrates. */
	FirstMoverMigration;

	/** This clone is a strict ancestor of the cached remote, which is at the binary's version: upstream fast-forwards. */
	FastForward;
}

/** What upstream's plain store open does with a database behind the binary. */
enum RemoteGateOutcome {
	/** There is nothing to fork (no remote, or no recorded version): upstream migrates without the gate. */
	MigratesWithoutGate;

	/** The gate refuses the migration. */
	GateStops(stop:RemoteGateStop);

	/** Upstream writes. */
	GateWrites(write:RemoteGateWrite);

	/** A read of the gate failed; upstream's open fails with this error. */
	GateReadFailed(error:String);
}

/** One read of the gate: its value, or the driver's error text. */
enum RemoteGateRead<T> {
	GateValue(value:T);
	GateError(error:String);
}

/** One `version, content_hash` row of schema_migrations with a hash. */
typedef MigrationContentHash = {
	final version:Int;
	final hash:String;
}

/**
	The reads that upstream's gate makes on the open store connection.

	Why: the gate decides from the remotes, the content hashes of this clone
	and of the cached remote-tracking ref, the commit ancestry and the working
	set. What: one method for each read, with upstream's queries. How: an
	embedded session implements it inside one read transaction, so the gate
	itself stays a pure decision over these answers.
**/
interface RemoteGateReads {
	/** `SELECT COUNT(*) FROM dolt_remotes`; a missing table counts as no remote. */
	function remoteCount():RemoteGateRead<Int>;

	/** `SELECT version, content_hash FROM schema_migrations`, without the rows whose hash is NULL or empty. */
	function contentHashes():RemoteGateRead<Array<MigrationContentHash>>;

	/** `SELECT active_branch()`, or null when the read fails. */
	function activeBranch():Null<String>;

	/** Whether `SHOW TABLES AS OF '<ref>' LIKE 'schema_migrations'` returns a row. */
	function hasMigrationTableAt(ref:String):RemoteGateRead<Bool>;

	/** Whether `SHOW COLUMNS FROM schema_migrations AS OF '<ref>' LIKE 'content_hash'` returns a row. */
	function hasContentHashColumnAt(ref:String):RemoteGateRead<Bool>;

	/** `SELECT version, content_hash FROM schema_migrations AS OF '<ref>'`, without the rows whose hash is NULL or empty. */
	function contentHashesAt(ref:String):RemoteGateRead<Array<MigrationContentHash>>;

	/** The commits of HEAD that `ref` lacks and the commits of `ref` that HEAD lacks (upstream LocalIsStrictAncestorOf). */
	function aheadBehind(ref:String):RemoteGateRead<{ahead:Int, behind:Int}>;

	/** The `table_name` of each row of `dolt_status`. */
	function changedTables():RemoteGateRead<Array<String>>;
}

/** Upstream `schema.AllowRemoteMigrateEnv`. */
private final ALLOW_REMOTE_MIGRATE_ENV = "BD_ALLOW_REMOTE_MIGRATE";

/** Upstream `schema.SmartGateEnv`. */
private final SMART_GATE_ENV = "BD_SMART_GATE";

/** Upstream `schema.LastNonDeterministicMigration`. */
private final LAST_NON_DETERMINISTIC_MIGRATION = 43;

/**
	Upstream's remote-migrate gate (internal/storage/schema/remote_migrate_gate.go
	and smart_remote_migrate_gate.go) for an embedded database at
	`currentVersion`, behind the binary.

	Why: upstream's plain store open runs this gate before it migrates. With a
	Dolt remote it refuses the migration, or migrates or fast-forwards when it
	can prove that safe. This build never writes, so a write is only reported.
	What: the outcome, from the reads in upstream's order. Upstream's embedded
	open wires the fast-forward callbacks and is never read-only there, so a
	fast-forward that lands at the binary's version is a write.
	How: the pending migrations are the main-lane versions above the current
	one, 1 to `BINARY_SCHEMA_VERSION`. Only the remote read can fail the open;
	every failed read of the smart gate makes its verdict undetermined.
**/
function evaluateRemoteGate(currentVersion:Int, reads:RemoteGateReads):RemoteGateOutcome {
	if (currentVersion == 0)
		return MigratesWithoutGate;
	var pending = 0;
	for (version in 1...BINARY_SCHEMA_VERSION + 1)
		if (version > currentVersion)
			pending++;
	if (pending == 0)
		return MigratesWithoutGate;
	switch reads.remoteCount() {
		case GateError(error):
			return GateReadFailed('remote-migrate gate: read remotes: ${error}');
		case GateValue(count) if (count <= 0):
			return MigratesWithoutGate;
		case GateValue(_):
	}
	var unrecognizedEnv = "";
	final allow = environmentValue(ALLOW_REMOTE_MIGRATE_ENV);
	if (allow != "") {
		final allowed = parseGoBool(allow);
		if (allowed == null)
			unrecognizedEnv = allow;
		else if (allowed)
			return GateWrites(EscapeHatchMigration);
	}
	function stop(decision:RemoteGateDecision):RemoteGateOutcome {
		return GateStops({
			currentVersion: currentVersion,
			latestVersion: BINARY_SCHEMA_VERSION,
			pending: pending,
			unrecognizedEnv: unrecognizedEnv,
			decision: decision
		});
	}
	final smartGate = environmentValue(SMART_GATE_ENV);
	final smartGateValue = smartGate == "" ? null : parseGoBool(smartGate);
	if (smartGate != "" && smartGateValue == false)
		return stop(BluntStop(SmartGateOptedOut));
	final fallback = switch routeSmartGate(currentVersion, reads) {
		case SmartAutoMigrate: return GateWrites(FirstMoverMigration);
		case SmartAdopt: return stop(AdoptStop);
		case SmartAdoptFastForward(true): return GateWrites(FastForward);
		case SmartAdoptFastForward(false): return stop(AdoptFastForwardStop);
		case SmartForkSkew(versions): return stop(ForkSkewStop(versions));
		case SmartBelowFloor: BelowConvergenceFloor;
		case SmartUndetermined: UnreadableRemoteState;
	};
	// An unparseable BD_SMART_GATE keeps the gate on, and upstream names it before the routing reason.
	return stop(BluntStop(smartGate != "" && smartGateValue == null ? UnparseableSmartGateEnv(smartGate) : fallback));
}

/** Upstream `smartGateDecision`; `SmartAdoptFastForward` carries `atLatest`. */
private enum SmartGateVerdict {
	SmartUndetermined;
	SmartAutoMigrate;
	SmartAdopt;
	SmartAdoptFastForward(atLatest:Bool);
	SmartForkSkew(versions:Array<Int>);
	SmartBelowFloor;
}

/** Upstream `routeSmartGate` with the remote `origin`, which reads only the cached remote-tracking ref. */
private function routeSmartGate(currentVersion:Int, reads:RemoteGateReads):SmartGateVerdict {
	final local = switch reads.contentHashes() {
		case GateValue(hashes) if (hashes.length > 0): hashes;
		case GateValue(_) | GateError(_): return SmartUndetermined;
	};
	final branch = reads.activeBranch();
	final ref = 'remotes/origin/${branch == null || branch == "" ? "main" : branch}';
	final remote = switch readHashesAt(reads, ref) {
		case null: return SmartUndetermined;
		case hashes: hashes;
	};
	final skew = contentHashSkew(local, remote);
	if (skew.length > 0)
		return SmartForkSkew(skew);
	var remoteMax = 0;
	for (row in remote)
		if (row.version > remoteMax)
			remoteMax = row.version;
	if (remoteMax > currentVersion)
		return canFastForward(reads, ref) ? SmartAdoptFastForward(remoteMax == BINARY_SCHEMA_VERSION) : SmartAdopt;
	if (remoteMax < currentVersion)
		return SmartUndetermined;
	return currentVersion >= LAST_NON_DETERMINISTIC_MIGRATION ? SmartAutoMigrate : SmartBelowFloor;
}

/** Upstream `ReadMigrationContentHashes` for a ref: null for an invalid ref, a failed read, a missing table or column, or no hash. */
private function readHashesAt(reads:RemoteGateReads, ref:String):Null<Array<MigrationContentHash>> {
	if (!isValidRef(ref))
		return null;
	switch reads.hasMigrationTableAt(ref) {
		case GateValue(true):
		case GateValue(false) | GateError(_):
			return null;
	}
	switch reads.hasContentHashColumnAt(ref) {
		case GateValue(true):
		case GateValue(false) | GateError(_):
			return null;
	}
	return switch reads.contentHashesAt(ref) {
		case GateValue(hashes) if (hashes.length > 0): hashes;
		case GateValue(_) | GateError(_): null;
	};
}

/** Upstream `routeAdoptFastForward`: HEAD is a strict ancestor of `ref` and the working set is clean but for wisp tables. */
private function canFastForward(reads:RemoteGateReads, ref:String):Bool {
	switch reads.aheadBehind(ref) {
		case GateValue(counts) if (counts.ahead == 0 && counts.behind >= 1):
		case GateValue(_) | GateError(_):
			return false;
	}
	switch reads.changedTables() {
		case GateValue(tables):
			for (table in tables)
				if (table != "wisps" && !StringTools.startsWith(table, "wisp_"))
					return false;
			return true;
		case GateError(_):
			return false;
	}
}

/** Upstream `ContentHashSkew`: the versions with a hash on both sides that differ, in ascending order. */
private function contentHashSkew(local:Array<MigrationContentHash>, remote:Array<MigrationContentHash>):Array<Int> {
	final skewed = new Array<Int>();
	for (row in local)
		for (other in remote)
			if (other.version == row.version && other.hash != row.hash)
				skewed.push(row.version);
	skewed.sort((left, right) -> left - right);
	return skewed;
}

/** Upstream `validMigrationRefPattern` and its length limit. */
private function isValidRef(ref:String):Bool {
	if (ref == "" || haxe.io.Bytes.ofString(ref).length > 128)
		return false;
	for (index in 0...ref.length) {
		final code = ref.charCodeAt(index);
		final allowed = (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code
			|| code == ".".code
			|| code == "/".code
			|| code == "-".code;
		if (!allowed)
			return false;
	}
	return true;
}

/** Go's `strconv.ParseBool`, or null for a value that it rejects. */
private function parseGoBool(value:String):Null<Bool> {
	return switch value {
		case "1" | "t" | "T" | "true" | "TRUE" | "True": true;
		case "0" | "f" | "F" | "false" | "FALSE" | "False": false;
		case _: null;
	};
}

/** Upstream `FormatMigrationVersions`: zero-padded four-digit versions joined by `, `. */
function formatMigrationVersions(versions:Array<Int>):String {
	return [for (version in versions) StringTools.lpad(Std.string(version), "0", 4)].join(", ");
}

/** Upstream `RemoteMigrateGateError.Error()`. */
function remoteGateError(stop:RemoteGateStop):String {
	final versions = '(v${stop.currentVersion} -> v${stop.latestVersion})';
	return switch stop.decision {
		case AdoptStop:
			'refusing to migrate a remote-backed database ${versions}: the remote is already migrated — adopt it instead of migrating here (#4259)';
		case AdoptFastForwardStop:
			'refusing to migrate a remote-backed database ${versions}: the remote is already migrated and this clone can fast-forward to it losslessly — adopt instead of migrating here (#4259)';
		case ForkSkewStop(skew):
			'refusing to migrate a remote-backed database ${versions}: this clone and the remote applied different content for migration(s) ${formatMigrationVersions(skew)} — the schema has already forked (#4259)';
		case BluntStop(_):
			final unit = stop.pending == 1 ? "migration" : "migrations";
			'refusing to auto-apply ${stop.pending} pending schema ${unit} to a remote-backed database ${versions}: migrating clones independently forks the schema (#4259)';
	};
}

/** Upstream `RemoteMigrateGateError.UserMessage()`, which the pre-run prints on stderr. */
function remoteGateUserMessage(stop:RemoteGateStop):String {
	var message = remoteGateError(stop) + "\n" + remoteGateBody(stop.decision);
	final why = switch stop.decision {
		case BluntStop(UnreadableRemoteState):
			"it could not read the remote's cached schema state (no cached ref, a stale/pre-content_hash one, or the cached remote is behind this clone)";
		case BluntStop(BelowConvergenceFloor):
			"this database is below the convergence floor — a legacy non-deterministic migration is still pending, so an unattended first-mover migrate is not safe to trust";
		case BluntStop(SmartGateOptedOut):
			'it is disabled (${SMART_GATE_ENV}=0)';
		case BluntStop(UnparseableSmartGateEnv(value)):
			'${SMART_GATE_ENV}=${value} is set but was not recognized (only boolean values enable/disable it), so it stayed enabled by default but still could not resolve this stop';
		case AdoptStop | AdoptFastForwardStop | ForkSkewStop(_):
			null;
	};
	if (why != null)
		message += '\n  Smart gate (#4516): ${why}.\n';
	if (stop.unrecognizedEnv != "")
		message += '\n  Note: ${ALLOW_REMOTE_MIGRATE_ENV}=${stop.unrecognizedEnv} is set but was not recognized —\n  use ${ALLOW_REMOTE_MIGRATE_ENV}=1 to unlock.\n';
	return message;
}

/** Upstream `userBody`. */
private function remoteGateBody(decision:RemoteGateDecision):String {
	return switch decision {
		case AdoptStop:
			"\n"
			+ "  The remote has already been migrated by another clone. Do NOT migrate here —\n"
			+ "  adopt the remote's migrated database instead:\n"
			+ "        bd bootstrap\n"
			+ "  Re-cloning replaces your local database: any local issues you have not pushed\n"
			+ "  are LOST. Push first (`bd dolt push`) or save a copy\n"
			+ "  (`bd export --all -o backup.jsonl`) before re-cloning.\n";
		case AdoptFastForwardStop:
			"\n"
			+ "  The remote has already been migrated by another clone, and this clone's local\n"
			+ "  history is a strict ancestor of the remote's with a clean working set — nothing\n"
			+ "  local would be lost by adopting it (unlike a typical adopt):\n"
			+ "        bd bootstrap\n"
			+ "  Unlike the usual re-clone, this clone has no unpushed commits and no\n"
			+ "  uncommitted local changes to discard.\n";
		case ForkSkewStop(skew):
			"\n"
			+ "  This clone and the remote already applied DIFFERENT content for migration(s) "
			+ formatMigrationVersions(skew)
			+ ".\n"
			+ "  The schema has forked (#4259); `bd dolt pull` can no longer merge. Migrating\n"
			+ "  cannot un-fork it. This is a data-loss decision, not an auto-fix:\n"
			+ "    • Pick ONE clone as canonical, then re-bootstrap every other clone from it —\n"
			+ "      unpushed work on the discarded clones is LOST. Export it first\n"
			+ "      (`bd export --all -o backup.jsonl`) if you need it.\n"
			+ "        bd bootstrap\n";
		case BluntStop(_):
			"\n"
			+ "  This database syncs with a remote. Applying schema migrations on more than\n"
			+ "  one clone independently forks the schema so `bd dolt pull` can no longer\n"
			+ "  merge — the break is silent and unrecoverable.\n"
			+ "\n"
			+ "  Choose one:\n"
			+ "    • You are the designated migrator (only ONE machine should be): migrate,\n"
			+ "      then publish the migrated database to the remote:\n"
			+ "        bd migrate --force\n"
			+ '        (or ${ALLOW_REMOTE_MIGRATE_ENV}=1 bd migrate in scripted/CI use)\n'
			+ "        bd dolt push\n"
			+ "    • Another machine has already migrated: adopt its database instead of\n"
			+ "      migrating here — re-clone from the remote so you receive the migrated\n"
			+ "      schema:\n"
			+ "        bd bootstrap\n"
			+ "      Re-cloning replaces your local database: any local issues you have not\n"
			+ "      pushed are LOST. Push first (`bd dolt push`) or save a copy\n"
			+ "      (`bd export --all -o backup.jsonl`) before re-cloning.\n"
			+ "\n"
			+ "  Several machines on one remote? Only ONE migrates. Get every other clone\n"
			+ "  fully in sync on its current binary, then after the migrator pushes run\n"
			+ "  `bd dolt pull` on each before upgrading it — its upgrade then has nothing\n"
			+ "  to migrate and needs no re-clone.\n";
	};
}

/**
	The warning that upstream's store open prints for a command in
	`readOnlyCommands` (embeddeddolt initSchema, openReadOnlyCommand), which
	then reads the database as it is.
**/
function remoteGateReadOnlyWarning(stop:RemoteGateStop):String {
	return 'Warning: ${remoteGateError(stop)}\n'
		+ '  Read-only command: continuing on schema v${stop.currentVersion} without migrating.\n'
		+ "  Writes are blocked until the schema is reconciled.  This is a\n"
		+ "  coordination decision, not an auto-fix - do NOT run a migration unless\n"
		+ "  you are the single designated migrator (only ONE clone may migrate a\n"
		+ "  shared remote, else the schema forks; #4259):\n"
		+ "    • designated migrator (only ONE machine): bd migrate --force && bd dolt push\n"
		+ "    • every other clone (another already migrated): bd bootstrap\n"
		+ "    • several machines: only ONE migrates; sync each other clone and run\n"
		+ "      bd dolt pull after the migrator pushes, before upgrading it\n";
}

/** Upstream `AgentDirective`, the `hint` of the JSON error. */
private function remoteGateDirective(decision:RemoteGateDecision):String {
	return switch decision {
		case AdoptStop:
			"Adopt, do NOT migrate: the remote is already migrated, so migrating here would fork it (#4259). " +
			"Adoption re-clones and replaces the local database (unpushed local work is lost), so it is a destructive " +
			"operator decision — surface remote_migrate_gate.options to the operator, do NOT auto-run bd bootstrap.";
		case AdoptFastForwardStop:
			"Adopt, do NOT migrate: the remote is already migrated, and this clone's local history is a strict "
			+ "ancestor of the remote's with a clean working set, so adopting is loss-free (no unpushed commits, no "
			+ "uncommitted changes discarded) — unlike a typical adopt. Still surface remote_migrate_gate.options to "
			+ "the operator rather than auto-running bd bootstrap; the current adopt mechanism is unchanged until an "
			+ "automatic fast-forward lands (#4259 follow-up).";
		case ForkSkewStop(skew):
			"Do NOT migrate: this clone and the remote already applied different content for migration(s) "
			+ formatMigrationVersions(skew)
			+ " — the schema has forked (#4259) and migrating cannot un-fork it. "
			+ "Resolving requires picking a canonical clone and re-bootstrapping the others, discarding their unpushed "
			+ "work — a data-loss decision. Surface remote_migrate_gate.options to the operator; do NOT auto-run anything.";
		case BluntStop(_):
			"Coordination decision required: only ONE clone may migrate a shared remote; " +
			"a second clone migrating independently forks the schema unrecoverably (#4259). " +
			"Do NOT auto-run a migration — surface remote_migrate_gate.options to the operator and let them choose.";
	};
}

/** Upstream `GateOption`. */
private typedef GateOption = {
	final id:String;
	final when:String;
	final commands:Array<String>;
	final risk:String;
}

/** Upstream `Options()`. */
private function remoteGateOptions(decision:RemoteGateDecision):Array<GateOption> {
	final adoptRisk = "re-clones and replaces the local database; push or export unpushed work first or it is lost";
	return switch decision {
		case AdoptStop:
			[
				{
					id: "adopt",
					when: "the remote is already migrated (confirmed by the gate) — adopt it",
					commands: ["bd bootstrap"],
					risk: adoptRisk
				}
			];
		case AdoptFastForwardStop:
			[
				{
					id: "adopt-fast-forward",
					when: "the remote is already migrated and this clone can fast-forward to it losslessly (no unpushed commits, clean working set)",
					commands: ["bd bootstrap"],
					risk: "none — this clone's local history is a strict ancestor of the remote's, so nothing local is discarded"
				}
			];
		case ForkSkewStop(skew):
			[
				{
					id: "reconcile-fork",
					when: 'the schema has already forked (different content for migration(s) ${formatMigrationVersions(skew)}); choose ONE clone as canonical',
					commands: ["bd export --all -o backup.jsonl", "bd bootstrap"],
					risk: "re-bootstrapping the non-canonical clones discards their unpushed work; export it first"
				}
			];
		case BluntStop(_):
			[
				{
					id: "migrate",
					when: "you are the single designated migrator (only ONE machine, confirmed with the operator) and no other clone has migrated yet",
					commands: ["bd migrate --force", "bd dolt push"],
					risk: "if another clone also migrates independently, the schema forks unrecoverably (#4259)"
				},
				{
					id: "adopt",
					when: "another machine has already migrated and pushed",
					commands: ["bd bootstrap"],
					risk: adoptRisk
				}
			];
	};
}

/**
	Upstream `handleRemoteMigrateGateJSON`: `buildJSONError` with the agent
	directive, plus `remote_migrate_gate` in the outer object, so it stays
	outside `data` under BD_JSON_ENVELOPE=1. Go's encoder prints map keys in
	byte order; the caller escapes `<`, `>` and `&` as Go's encoder does.
**/
function remoteGateJson(stop:RemoteGateStop, envelope:Bool):String {
	final quote = haxe.Json.stringify;
	final error = '"error": ${quote(remoteGateError(stop))}';
	final hint = '"hint": ${quote(remoteGateDirective(stop.decision))}';
	var observed = '${stop.pending} pending schema migration(s) and a configured remote';
	var expected = "exactly one designated clone migrates and publishes; every other clone adopts the result";
	var decision:Null<String> = null;
	var fallback:Null<String> = null;
	var skewVersions:Null<Array<Int>> = null;
	switch stop.decision {
		case AdoptStop:
			decision = "adopt";
			observed = "the remote is already migrated; migrating here would fork it";
			expected = "adopt the remote's migrated database (destructive re-clone — operator decision)";
		case ForkSkewStop(skew):
			decision = "fork-skew";
			observed = 'this clone and the remote applied different content for migration(s) ${formatMigrationVersions(skew)} — already forked';
			expected = "pick one canonical clone and re-bootstrap the others (data-loss decision)";
			skewVersions = skew;
		case BluntStop(reason):
			fallback = switch reason {
				case UnreadableRemoteState: "unreadable-remote-state";
				case BelowConvergenceFloor: "below-convergence-floor";
				case SmartGateOptedOut: "opted-out";
				case UnparseableSmartGateEnv(_): "unparseable-env";
			};
		case AdoptFastForwardStop:
	}
	final options = [
		for (option in remoteGateOptions(stop.decision))
			'      {\n        "commands": [\n${[for (command in option.commands) '          ${quote(command)}'].join(",\n")}\n        ],\n' +
			'        "id": ${quote(option.id)},\n        "risk": ${quote(option.risk)},\n        "when": ${quote(option.when)}\n      }'
	];
	final fields = ['    "current_version": ${stop.currentVersion}'];
	if (decision != null)
		fields.push('    "decision": ${quote(decision)}');
	fields.push('    "docs": "https://github.com/gastownhall/beads/blob/main/docs/getting-started/upgrading.md#remote-backed-databases-and-multiple-clones"');
	fields.push('    "expected": ${quote(expected)}');
	if (fallback != null)
		fields.push('    "fallback_reason": ${quote(fallback)}');
	fields.push('    "human_decision_required": true');
	fields.push('    "latest_version": ${stop.latestVersion}');
	fields.push('    "observed": ${quote(observed)}');
	fields.push('    "options": [\n${options.join(",\n")}\n    ]');
	fields.push('    "pending": ${stop.pending}');
	fields.push('    "severity": "blocking"');
	if (skewVersions != null)
		fields.push('    "skew_versions": [\n${[for (version in skewVersions) '      ${version}'].join(",\n")}\n    ]');
	final gate = '"remote_migrate_gate": {\n${fields.join(",\n")}\n  }';
	return
		envelope ? '{\n  "data": {\n    ${error},\n    ${hint}\n  },\n  ${gate},\n  "schema_version": 1\n}\n' : '{\n  ${error},\n  ${hint},\n  ${gate},\n  "schema_version": 1\n}\n';
}
