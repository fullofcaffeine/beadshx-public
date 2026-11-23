#!/usr/bin/env bash
# Acceptance tests a-i of the read-only snapshot artifact (BHX-M08-09, spec v1)
# for `bdhx snapshot`, on workspaces that the pinned upstream oracle fills in a
# fresh disposable directory. Every candidate run gets an empty TMPDIR that it
# must leave empty.
#
# Usage: test-snapshot.sh [BDHX]
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=export-fixture.sh
source "$repository_root/scripts/beadshx/export-fixture.sh"
oracle="$repository_root/build/bin/bd-upstream"
candidate="${1:-$repository_root/build/bin/bdhx}"
if [[ ! -x "$candidate" ]]; then
	printf 'bdhx candidate is missing: %s\n' "$candidate" >&2
	exit 1
fi
candidate="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-snapshot.XXXXXX")"
cleanup() {
	local status=$?
	if [[ "$status" -ne 0 ]]; then
		printf 'snapshot test failed (exit %s); disposable evidence retained: %s\n' "$status" "$fixture_root" >&2
		return "$status"
	fi
	find "$fixture_root" -mindepth 1 -delete
	rmdir "$fixture_root"
}
trap cleanup EXIT
cd "$repository_root"
identity="$("$oracle" version)"
[[ "$identity" == *'1.2.1'* && "$identity" == *'634cbbc4b'* ]] || {
	echo 'unexpected upstream oracle identity' >&2
	exit 1
}
export GOTOOLCHAIN="$(jq -er '.common.go' engdocs/beadshx/program/toolchain-locks.json)"
fixture_sql="$fixture_root/bin/fixture-sql"
go build -tags gms_pure_go -o "$fixture_sql" ./scripts/beadshx/fixture-sql

fail() {
	printf 'snapshot: FAIL: %s\n' "$*" >&2
	exit 1
}

pass() {
	printf 'snapshot %s: PASS\n' "$1"
}

mkdir -p "$fixture_root/home" "$fixture_root/config" "$fixture_root/oracle-tmp"
base_env=(env -i PATH="$PATH" HOME="$fixture_root/home" XDG_CONFIG_HOME="$fixture_root/config" TZ=UTC
	BEADS_ACTOR=fixture BEADS_TELEMETRY_DISABLED=1 BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1
	BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1)
oracle_command=("${base_env[@]}" TMPDIR="$fixture_root/oracle-tmp" "$oracle")

# Usage: oracle_in DIRECTORY ARGUMENT...
oracle_in() {
	local directory="$1"
	shift
	(cd "$directory" && "${oracle_command[@]}" "$@")
}

# Usage: run_snapshot OUTPUT DIRECTORY VAR=VALUE... -- ARGUMENT...
# Runs `bdhx snapshot ARGUMENT...` in DIRECTORY with the variables added, and
# writes stdout to OUTPUT and stderr to OUTPUT.stderr. Returns its exit code.
run_snapshot() {
	local output="$1" directory="$2" status=0 temporary
	shift 2
	local -a assignments=(BEADSHX_SNAPSHOT_TEST=1)
	while [[ "$1" != "--" ]]; do
		assignments+=("$1")
		shift
	done
	shift
	temporary="$(mktemp -d "$fixture_root/candidate-tmp.XXXXXX")"
	(cd "$directory" && "${base_env[@]}" TMPDIR="$temporary" "${assignments[@]}" "$candidate" snapshot "$@") \
		>"$output" 2>"$output.stderr" || status=$?
	if [[ -n "$(find "$temporary" -mindepth 1 -print -quit)" ]]; then
		fail "snapshot wrote temporary files in $directory"
	fi
	rmdir "$temporary"
	return "$status"
}

# Usage: snapshot_ok OUTPUT DIRECTORY VAR=VALUE... -- ARGUMENT...
snapshot_ok() {
	local output="$1"
	if ! run_snapshot "$@"; then
		cat "$output.stderr" >&2
		fail "snapshot exited with an error in $2"
	fi
	if [[ -s "$output.stderr" ]]; then
		cat "$output.stderr" >&2
		fail "snapshot wrote to stderr in $2"
	fi
}

# The same exclusions as fingerprint_task_state_tree in test-parity-smoke.sh: an
# embedded Dolt reader rewrites its derived journal index and transient
# manifest files, which hold no task, revision or configuration state.
fingerprint_task_state_tree() {
	(
		cd "$1"
		find . -mindepth 1 ! -path '*/.dolt/noms/journal.idx' ! -path '*/.beads.gate.lock' \
			! -path '*/.beads/dolt.gate.lock' ! -path '*/.beads/.local_version' ! -name 'nbs_manifest_*' -print |
			LC_ALL=C sort
		find . -type f ! -path '*/.dolt/noms/journal.idx' ! -path '*/.beads.gate.lock' \
			! -path '*/.beads/dolt.gate.lock' ! -path '*/.beads/.local_version' ! -name 'nbs_manifest_*' \
			-exec shasum -a 256 {} + | LC_ALL=C sort
	) | shasum -a 256 | awk '{print $1}'
}

# Embedded Dolt can replace a derived file shortly after the oracle command that
# wrote it exits; wait for one second without a change.
wait_for_stable_tree() {
	local previous current
	previous="$(fingerprint_task_state_tree "$1")"
	for _ in {1..20}; do
		sleep 1
		current="$(fingerprint_task_state_tree "$1")"
		if [[ "$current" == "$previous" ]]; then
			return 0
		fi
		previous="$current"
	done
	fail "workspace did not reach a stable fingerprint: $1"
}

copy_tree() {
	if [[ "$(uname -s)" == Darwin ]]; then
		cp -cR "$1" "$2"
	else
		cp -R "$1" "$2"
	fi
}

# Checks of the artifact format and of the change between two artifacts.
snapshot_check() {
	python3 -I -c '
import json
import sys

KEYS = ["_dolt_branch", "_dolt_commit", "_dolt_state", "_project_id", "_records", "_schema", "_scope", "_sort"]


def fail(message):
    sys.stderr.write("snapshot: FAIL: " + message + "\n")
    sys.exit(1)


def read(path):
    with open(path, "rb") as source:
        data = source.read()
    if data.startswith(b"\xef\xbb\xbf"):
        fail(path + " starts with a byte order mark")
    if not data.endswith(b"\n"):
        fail(path + " does not end with a line feed")
    if b"\r" in data:
        fail(path + " holds a carriage return")
    lines = data[:-1].split(b"\n")
    if any(not line for line in lines):
        fail(path + " holds a blank line")
    data.decode("utf-8")
    return lines


def header(path, project=True):
    lines = read(path)
    head = json.loads(lines[0], object_pairs_hook=lambda pairs: pairs)
    keys = [key for key, _ in head]
    if keys != [key for key in KEYS if project or key != "_project_id"]:
        fail("header keys are " + ",".join(keys))
    values = dict(head)
    if lines[0] != json.dumps(values, separators=(",", ":")).encode("ascii"):
        fail("header is not compact JSON: " + lines[0].decode("utf-8"))
    expected = {"_schema": "beadshx-task-snapshot/1", "_scope": "all-issues", "_sort": "id-bytewise"}
    for key, value in expected.items():
        if values[key] != value:
            fail("header " + key + " is " + repr(values[key]))
    for key in ["_dolt_branch", "_dolt_commit", "_dolt_state", "_project_id"][: 4 if project else 3]:
        if not isinstance(values[key], str) or not values[key]:
            fail("header " + key + " is not a non-empty string")
    if type(values["_records"]) is not int or values["_records"] != len(lines) - 1:
        fail("header _records is %r for %d body lines" % (values["_records"], len(lines) - 1))
    ids = []
    for line in lines[1:]:
        record = json.loads(line)
        if record.get("_type") != "issue":
            fail("body holds a record that is not an issue: " + line.decode("utf-8"))
        ids.append(record["id"].encode("utf-8"))
    if ids != sorted(ids) or len(set(ids)) != len(ids):
        fail("body is not sorted by issue ID in byte order")
    print("\t".join(values.get(key, "NULL") for key in KEYS[:4]))


def changes(old_path, new_path):
    old, new = read(old_path), read(new_path)
    old_head, new_head = json.loads(old[0]), json.loads(new[0])
    keys = sorted(key for key in KEYS if old_head.get(key) != new_head.get(key))
    old_body = {json.loads(line)["id"]: line for line in old[1:]}
    new_body = {json.loads(line)["id"]: line for line in new[1:]}
    ids = sorted(key for key in set(old_body) | set(new_body) if old_body.get(key) != new_body.get(key))
    print("header:" + ",".join(keys) + " body:" + ",".join(ids))


def body(path):
    sys.stdout.buffer.write(b"".join(line + b"\n" for line in read(path)[1:]))


command = sys.argv[1]
if command == "header":
    header(sys.argv[2])
elif command == "header-without-project":
    header(sys.argv[2], project=False)
elif command == "changes":
    changes(sys.argv[2], sys.argv[3])
elif command == "body":
    body(sys.argv[2])
else:
    fail("unknown check " + command)
' "$@"
}

# Requires `bdhx snapshot`'s body to equal upstream export --all without memory lines, sorted by ID.
require_body_matches_oracle() {
	local artifact="$1" directory="$2" name="$3"
	oracle_in "$directory" export --all >"$fixture_root/$name.oracle.jsonl"
	sorted_issue_lines "$fixture_root/$name.oracle.jsonl" >"$fixture_root/$name.expected.jsonl"
	snapshot_check body "$artifact" >"$fixture_root/$name.body.jsonl"
	if ! cmp -s "$fixture_root/$name.expected.jsonl" "$fixture_root/$name.body.jsonl"; then
		diff -u "$fixture_root/$name.expected.jsonl" "$fixture_root/$name.body.jsonl" >&2 || true
		fail "$name: body differs from upstream export --all"
	fi
}

workspace="$fixture_root/work"
mkdir -p "$workspace"
touch "$workspace/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$workspace" >/dev/null
build_export_fixture "$workspace" "$fixture_sql" "${oracle_command[@]}"
# A remote URL, a config key and a memory hold canaries (test f).
oracle_in "$workspace" dolt remote add canary "file://$fixture_root/CANARY-remote" >/dev/null
oracle_in "$workspace" export --all >"$fixture_root/fixture.oracle.jsonl"
require_export_coverage "$fixture_root/fixture.oracle.jsonl"
wait_for_stable_tree "$workspace"

# d. Zero writes: the task-state tree is unchanged.
before="$(fingerprint_task_state_tree "$workspace")"
snapshot_ok "$fixture_root/artifact.jsonl" "$workspace" --
after="$(fingerprint_task_state_tree "$workspace")"
[[ "$before" == "$after" ]] || fail "snapshot changed the task-state tree"
pass "d (zero writes)"

# i. Header: exact keys and order, and _records equals the body line count.
revision="$(snapshot_check header "$fixture_root/artifact.jsonl")"
# A database without a _project_id row leaves the key out.
copy_tree "$workspace" "$fixture_root/i-no-project"
printf '%s\n' "DELETE FROM metadata WHERE \`key\` = '_project_id'" | TZ=UTC "$fixture_sql" "$fixture_root/i-no-project" >/dev/null
snapshot_ok "$fixture_root/i-no-project.jsonl" "$fixture_root/i-no-project" --
snapshot_check header-without-project "$fixture_root/i-no-project.jsonl" >/dev/null
pass "i (header)"

# b. The header revision equals what SQL reads from the same workspace.
sql_revision="$(printf '%s\n' "SELECT active_branch(), DOLT_HASHOF('HEAD'), DOLT_HASHOF_DB(), (SELECT value FROM metadata WHERE \`key\` = '_project_id')" |
	"$fixture_sql" --query "$workspace")"
[[ "$revision" == "$sql_revision" ]] || fail "header revision [$revision] differs from SQL [$sql_revision]"
pass "b (header revision equals SQL)"

# c. Identical bytes across directory, selection, time zone and locale, and after delete and regenerate.
mkdir -p "$fixture_root/elsewhere"
snapshot_ok "$fixture_root/c-directory.jsonl" "$fixture_root/elsewhere" -- -C "$workspace"
snapshot_ok "$fixture_root/c-beads-dir.jsonl" "$fixture_root/elsewhere" BEADS_DIR="$workspace/.beads" --
snapshot_ok "$fixture_root/c-subdirectory.jsonl" "$workspace/.beads" --
snapshot_ok "$fixture_root/c-locale.jsonl" "$workspace" TZ=Asia/Tokyo LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 --
snapshot_ok "$fixture_root/c-west.jsonl" "$workspace" TZ=America/Los_Angeles LANG=C LC_ALL=C --
# JSON output settings change nothing: the artifact is JSON Lines in every mode.
snapshot_ok "$fixture_root/c-json.jsonl" "$workspace" BD_JSON=1 -- --json
for variant in directory beads-dir subdirectory locale west json; do
	cmp -s "$fixture_root/artifact.jsonl" "$fixture_root/c-$variant.jsonl" || fail "c: the $variant run gave other bytes"
done
cp -f "$fixture_root/artifact.jsonl" "$fixture_root/kept.jsonl"
rm -f "$fixture_root/artifact.jsonl"
snapshot_ok "$fixture_root/artifact.jsonl" "$workspace" --
cmp -s "$fixture_root/kept.jsonl" "$fixture_root/artifact.jsonl" || fail "c: a regenerated artifact gave other bytes"
pass "c (deterministic)"

# f. Canaries in a config key, a memory, a remote URL, the actor and a password variable never appear.
grep -Fq CANARY-memory-value "$fixture_root/fixture.oracle.jsonl" || fail "f: the memory canary is missing"
snapshot_ok "$fixture_root/f.jsonl" "$workspace" BEADS_DOLT_PASSWORD=CANARY-password-value \
	DOLT_REMOTE_PASSWORD=CANARY-remote-password BEADS_ACTOR=CANARY-actor --
cmp -s "$fixture_root/artifact.jsonl" "$fixture_root/f.jsonl" || fail "f: the environment changed the artifact"
if grep -Fq CANARY "$fixture_root/f.jsonl"; then
	fail "f: the artifact holds a canary"
fi
for path in "$fixture_root" "$(cd "$fixture_root" && pwd -P)" "$repository_root"; do
	if grep -Fq "$path" "$fixture_root/f.jsonl"; then
		fail "f: the artifact holds a filesystem path"
	fi
done
if grep -Fq "$(hostname)" "$fixture_root/f.jsonl"; then
	fail "f: the artifact holds the host name"
fi
oracle_in "$workspace" config get custom.canary | grep -Fq CANARY-config-value || fail "f: the config canary is missing"
pass "f (no secret, path, actor or host)"

# a. Body equals upstream export --all without memory lines, sorted by ID.
require_body_matches_oracle "$fixture_root/artifact.jsonl" "$workspace" a
pass "a (body equals upstream export --all, $(($(wc -l <"$fixture_root/artifact.jsonl") - 1)) issues)"

# h. Refusals print nothing on stdout, exit 1, and change nothing.
# Usage: expect_refusal NAME DIRECTORY EXPECTED_STDERR VAR=VALUE... -- ARGUMENT...
expect_refusal() {
	local name="$1" directory="$2" expected="$3" status=0 tree_before tree_after
	shift 3
	tree_before="$(fingerprint_task_state_tree "$directory")"
	run_snapshot "$fixture_root/h-$name.out" "$directory" "$@" || status=$?
	tree_after="$(fingerprint_task_state_tree "$directory")"
	[[ "$status" -eq 1 ]] || fail "h: $name exited $status"
	[[ ! -s "$fixture_root/h-$name.out" ]] || fail "h: $name wrote to stdout"
	[[ "$tree_before" == "$tree_after" ]] || fail "h: $name changed its directory"
	if [[ "$(cat "$fixture_root/h-$name.out.stderr")" != "$expected" ]]; then
		cat "$fixture_root/h-$name.out.stderr" >&2
		fail "h: $name printed other words on stderr"
	fi
}
route_refusal='Error: snapshot is not available yet for server-mode or proxied workspaces in this build'
no_database="Error: no beads database found
Hint: run 'bd where' to inspect the resolved workspace, or 'bd init' to create a new database
      or set BEADS_DIR to point to your .beads directory"
for mode in server proxied-server; do
	copy_tree "$workspace" "$fixture_root/h-$mode"
	jq --arg mode "$mode" '.dolt_mode = $mode' "$workspace/.beads/metadata.json" >"$fixture_root/h-$mode/.beads/metadata.json"
	expect_refusal "$mode" "$fixture_root/h-$mode" "$route_refusal" --
done
copy_tree "$workspace" "$fixture_root/h-shared"
printf 'dolt:\n  shared-server: true\n' >>"$fixture_root/h-shared/.beads/config.yaml"
expect_refusal shared-server "$fixture_root/h-shared" 'Notice: shared-server mode is enabled (BEADS_DOLT_SHARED_SERVER or dolt.shared-server in config.yaml) but .beads/metadata.json pins dolt_mode="embedded". Using the shared server for this run.
  To persist server mode: set dolt_mode to "server" in .beads/metadata.json and commit it.
  To stay embedded: unset BEADS_DOLT_SHARED_SERVER (or remove dolt.shared-server from config.yaml).
Error: snapshot is not available yet in shared-server mode in this build' --
expect_refusal global "$workspace" "$route_refusal" -- --global
expect_refusal global-json "$workspace" "$route_refusal" -- --global --json
mkdir -p "$fixture_root/h-empty"
expect_refusal no-workspace "$fixture_root/h-empty" "$no_database" --
expect_refusal no-workspace-json "$fixture_root/h-empty" "$no_database" -- --json
copy_tree "$workspace" "$fixture_root/h-missing"
find "$fixture_root/h-missing/.beads/embeddeddolt" -mindepth 1 -delete
rmdir "$fixture_root/h-missing/.beads/embeddeddolt"
expect_refusal missing-database "$fixture_root/h-missing" "$no_database" --
expect_refusal argument "$workspace" 'Error: unknown command "extra" for "bd snapshot"' -- extra
pass "h (refusals)"

# e. A write changes _dolt_state and the line of the changed issue, and nothing else.
# Usage: expect_change NAME EXPECTED_CHANGES ORACLE_ARGUMENT...
expect_change() {
	local name="$1" expected="$2" changes
	shift 2
	cp -f "$fixture_root/artifact.jsonl" "$fixture_root/e-$name.before.jsonl"
	oracle_in "$workspace" "$@" >/dev/null
	wait_for_stable_tree "$workspace"
	snapshot_ok "$fixture_root/artifact.jsonl" "$workspace" --
	snapshot_check header "$fixture_root/artifact.jsonl" >/dev/null
	require_body_matches_oracle "$fixture_root/artifact.jsonl" "$workspace" "e-$name"
	changes="$(snapshot_check changes "$fixture_root/e-$name.before.jsonl" "$fixture_root/artifact.jsonl")"
	[[ "$changes" == "$expected" ]] || fail "e: $name changed [$changes], expected [$expected]"
}
expect_change committed 'header:_dolt_commit,_dolt_state body:snap-b' update snap-b --title 'Beta renamed'
# Dolt ignores the wisp tables, so this change never reaches a commit; the state hash still moves.
expect_change wisp-only 'header:_dolt_state body:snap-w1' update snap-w1 --title 'Wisp renamed'
# Last: a later oracle write would commit this change.
expect_change uncommitted 'header:_dolt_state body:snap-g' --dolt-auto-commit off update snap-g --title 'Gate renamed'
pass "e (one change, one line)"

# g. Upstream import of the artifact into a fresh workspace, then export --all,
# gives the body, except for what upstream import defines (see below).
restore="$fixture_root/restore"
mkdir -p "$restore"
touch "$restore/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$restore" >/dev/null
(
	cd "$restore"
	git init -q
	git config user.name fixture
	git config user.email fixture@example.invalid
)
oracle_in "$restore" init --prefix snap --non-interactive --skip-agents --skip-hooks --quiet
oracle_in "$restore" import "$fixture_root/artifact.jsonl" >"$fixture_root/g-import.out" 2>&1 ||
	{
		cat "$fixture_root/g-import.out" >&2
		fail "g: upstream import refused the artifact"
	}
oracle_in "$restore" export --all >"$fixture_root/g-export.jsonl"
sorted_issue_lines "$fixture_root/g-export.jsonl" >"$fixture_root/g-restored.jsonl"
snapshot_check body "$fixture_root/artifact.jsonl" >"$fixture_root/g-body.jsonl"
python3 -I -c '
import json
import sys

# What upstream v1.2.1 import changes in a round trip:
# - Import writes durable and wisp rows in separate batches and skips a
#   dependency between the two planes ("cross-bucket dependency between
#   regular issue and wisp in the same batch"), so the edge and the blocks
#   counts that it gave are not restored.
# - Its insert stores storage_class through StorageClass.Normalize, which
#   turns "versioned" into none, so that field is left out.


def plane(record):
    return "wisp" if record.get("ephemeral") or record.get("no_history") else "durable"


def load(path):
    with open(path, "rb") as source:
        return [line for line in source.read().split(b"\n") if line]


body, restored = load(sys.argv[1]), load(sys.argv[2])
records = {json.loads(line)["id"]: json.loads(line) for line in body}
expected = {key: json.loads(json.dumps(value)) for key, value in records.items()}
for record in records.values():
    for dependency in record.get("dependencies", []):
        target = records.get(dependency["depends_on_id"])
        if target is None or plane(target) == plane(record):
            continue
        source = expected[record["id"]]
        source["dependencies"] = [edge for edge in source["dependencies"] if edge != dependency]
        if not source["dependencies"]:
            del source["dependencies"]
        if dependency["type"] == "blocks":
            source["dependency_count"] -= 1
            expected[target["id"]]["dependent_count"] -= 1
for record in expected.values():
    if record.get("storage_class") == "versioned":
        del record["storage_class"]
actual = {json.loads(line)["id"]: line for line in restored}
if sorted(actual) != sorted(records):
    sys.exit("snapshot: FAIL: g: the restored issues are " + ",".join(sorted(actual)))
changed = []
for line in body:
    key = json.loads(line)["id"]
    if actual[key] == line:
        continue
    if json.loads(actual[key]) != expected[key]:
        sys.exit("snapshot: FAIL: g: " + key + " differs beyond what import defines:\n" + line.decode() + "\n" + actual[key].decode())
    changed.append(key)
print(",".join(changed))
' "$fixture_root/g-body.jsonl" "$fixture_root/g-restored.jsonl" >"$fixture_root/g-changed.txt"
pass "g (import round trip; lines that import changes as defined: $(cat "$fixture_root/g-changed.txt"))"
