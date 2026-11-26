#!/usr/bin/env bash
# Acceptance tests of the logical database state comparison (BHX-M06-07).
#
# Each case builds two disposable workspaces whose upstream output looks the
# same, and requires scripts/beadshx/logical-state to report how their state
# differs: an event sequence in another order, a missing event, an extra or
# renamed Dolt commit, another working-set dirtiness, another updated_at, and
# a hidden column. Controls require equal states to compare equal, a read to
# leave the state unchanged, and the same upstream writes made at other moments
# to compare equal under the declared write rules (and unequal when the writes
# differ). One case shows that the comparison sees a write that an upstream
# read makes and its output does not show.
#
# Usage: test-logical-state.sh
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
oracle="$repository_root/build/bin/bd-upstream"
if [[ ! -x "$oracle" ]]; then
	printf 'upstream oracle is missing: %s\n' "$oracle" >&2
	exit 1
fi
identity="$("$oracle" version)"
[[ "$identity" == *'1.2.1'* && "$identity" == *'634cbbc4b'* ]] || {
	printf 'unexpected upstream oracle identity: %s\n' "$identity" >&2
	exit 1
}
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-logical-state.XXXXXX")"
cleanup() {
	local status=$?
	if [[ "$status" -ne 0 ]]; then
		printf 'logical state test failed (exit %s); disposable evidence retained: %s\n' "$status" "$fixture_root" >&2
		return "$status"
	fi
	find "$fixture_root" -mindepth 1 -delete
	rmdir "$fixture_root"
}
trap cleanup EXIT
cd "$repository_root"
GOTOOLCHAIN="$(jq -er '.common.go' engdocs/beadshx/program/toolchain-locks.json)"
export GOTOOLCHAIN
go test -mod=readonly -tags gms_pure_go ./scripts/beadshx/logical-state ./scripts/beadshx/fixture-sql
go build -mod=readonly -tags gms_pure_go -o "$fixture_root/bin/" ./scripts/beadshx/fixture-sql ./scripts/beadshx/logical-state
fixture_sql="$fixture_root/bin/fixture-sql"
logical_state="$fixture_root/bin/logical-state"

fail() {
	printf 'logical state: FAIL: %s\n' "$*" >&2
	exit 1
}

pass() {
	printf 'logical state %s: PASS\n' "$1"
}

mkdir -p "$fixture_root/home" "$fixture_root/config"
oracle_command=(env -i PATH="$PATH" HOME="$fixture_root/home" XDG_CONFIG_HOME="$fixture_root/config" TZ=UTC
	BEADS_ACTOR=fixture BEADS_TELEMETRY_DISABLED=1 BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1
	BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1 "$oracle")

# Usage: oracle_in DIRECTORY ARGUMENT...
oracle_in() {
	local directory="$1"
	shift
	(cd "$directory" && "${oracle_command[@]}" "$@")
}

copy_tree() {
	if [[ "$(uname -s)" == Darwin ]]; then
		cp -cR "$1" "$2"
	else
		cp -R "$1" "$2"
	fi
}

# Usage: apply_sql WORKSPACE [FIXTURE-SQL-OPTION...] <<<STATEMENTS
apply_sql() {
	local workspace="$1"
	shift
	TZ=UTC "$fixture_sql" "$@" "$workspace" >/dev/null
}

# The run window of the write rules holds whole seconds (see logical-state).
utc_now() {
	date -u +%Y-%m-%dT%H:%M:%SZ
}

# The base workspace: two issues with fixed IDs, a comment, a label, a
# dependency and the custom type gate, all written by upstream.
base="$fixture_root/base"
mkdir -p "$base"
touch "$base/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$base" >/dev/null
(
	cd "$base"
	git init -q
	git config user.name fixture
	git config user.email fixture@example.invalid
)
oracle_in "$base" init --prefix test --non-interactive --skip-agents --skip-hooks --quiet
oracle_in "$base" create "First issue" --id test-aaa --priority 1 --description "Body" --json >/dev/null
oracle_in "$base" create "Second issue" --id test-bbb --priority 2 --json >/dev/null
oracle_in "$base" comments add test-aaa "A comment" --json >/dev/null
oracle_in "$base" label add test-aaa smoke --json >/dev/null
oracle_in "$base" dep add test-bbb test-aaa >/dev/null
oracle_in "$base" config set types.custom gate >/dev/null
"$logical_state" export "$base" >"$fixture_root/base.state.json"
pass "base fixture"

# Usage: variant NAME
# Copies the base workspace to NAME under the fixture root and prints its path.
variant() {
	local destination="$fixture_root/$1"
	copy_tree "$base" "$destination"
	printf '%s\n' "$destination"
}

# Usage: expect_same_output LEFT RIGHT ARGUMENT...
# Upstream prints the same stdout and stderr, and exits the same way, in both workspaces.
expect_same_output() {
	local left="$1" right="$2" left_status=0 right_status=0
	shift 2
	oracle_in "$left" "$@" >"$left.stdout" 2>"$left.stderr" || left_status=$?
	oracle_in "$right" "$@" >"$right.stdout" 2>"$right.stderr" || right_status=$?
	if [[ "$left_status" -ne "$right_status" ]] || ! cmp -s "$left.stdout" "$right.stdout" ||
		! cmp -s "$left.stderr" "$right.stderr"; then
		diff -u "$left.stdout" "$right.stdout" >&2 || true
		fail "upstream output differs for: $*"
	fi
}

# Usage: compare_states LEFT RIGHT REPORT [COMPARE-OPTION...]
# Exports both workspaces and compares them; returns the comparison's exit code.
compare_states() {
	local left="$1" right="$2" report="$3" status=0
	shift 3
	"$logical_state" export "$left" >"$left.state.json"
	"$logical_state" export "$right" >"$right.state.json"
	"$logical_state" compare "$@" "$left.state.json" "$right.state.json" >"$report" 2>&1 || status=$?
	return "$status"
}

# Usage: expect_reported NAME LEFT RIGHT EXPECTED [COMPARE-OPTION...]
expect_reported() {
	local name="$1" left="$2" right="$3" expected="$4" status=0
	shift 4
	compare_states "$left" "$right" "$fixture_root/$name.report" "$@" || status=$?
	if [[ "$status" -ne 1 ]]; then
		cat "$fixture_root/$name.report" >&2
		fail "$name: compare exited $status, want 1 (states differ)"
	fi
	if ! grep -Fq -- "$expected" "$fixture_root/$name.report"; then
		cat "$fixture_root/$name.report" >&2
		fail "$name: the report does not say: $expected"
	fi
}

# Usage: expect_equal NAME LEFT RIGHT [COMPARE-OPTION...]
expect_equal() {
	local name="$1" left="$2" right="$3" status=0
	shift 3
	compare_states "$left" "$right" "$fixture_root/$name.report" "$@" || status=$?
	if [[ "$status" -ne 0 ]]; then
		cat "$fixture_root/$name.report" >&2
		fail "$name: compare exited $status, want 0 (states equal)"
	fi
}

# Controls: two copies, and a copy before and after a read, are equal row for
# row and commit for commit, with no rule.
left="$(variant equal-left)"
right="$(variant equal-right)"
expect_equal equal-copies "$left" "$right"
pass "equal copies compare equal exactly"
read_workspace="$(variant read-only)"
oracle_in "$read_workspace" list --json >/dev/null
oracle_in "$read_workspace" show test-aaa --json >/dev/null
expect_equal read-unchanged "$base" "$read_workspace"
pass "a read leaves the state unchanged"

# 1. The same journal entries in another sequence. Upstream output never shows
# the journal; the entries match as a set, but their sequence numbers differ.
left="$(variant order-left)"
right="$(variant order-right)"
apply_sql "$left" --no-commit <<<"INSERT INTO bd_events_journal (seq, ts, op, issue_id) VALUES (1, '2026-08-20 10:00:00', 'create', 'test-aaa'), (2, '2026-08-20 10:00:00', 'update', 'test-aaa')"
apply_sql "$right" --no-commit <<<"INSERT INTO bd_events_journal (seq, ts, op, issue_id) VALUES (1, '2026-08-20 10:00:00', 'update', 'test-aaa'), (2, '2026-08-20 10:00:00', 'create', 'test-aaa')"
expect_same_output "$left" "$right" show test-aaa --json
expect_same_output "$left" "$right" list --json
expect_reported event-sequence "$left" "$right" 'table bd_events_journal: row seq=1: column op: left "create", right "update"'
# The same two audit events with their times swapped: the event order differs.
left="$(variant event-order-left)"
right="$(variant event-order-right)"
apply_sql "$left" --no-commit <<<"INSERT INTO events (id, issue_id, event_type, actor, created_at) VALUES ('00000000-0000-5000-8000-000000000001', 'test-bbb', 'status_changed', 'fixture', '2026-08-20 10:00:00'), ('00000000-0000-5000-8000-000000000002', 'test-bbb', 'closed', 'fixture', '2026-08-20 10:00:01')"
apply_sql "$right" --no-commit <<<"INSERT INTO events (id, issue_id, event_type, actor, created_at) VALUES ('00000000-0000-5000-8000-000000000001', 'test-bbb', 'status_changed', 'fixture', '2026-08-20 10:00:01'), ('00000000-0000-5000-8000-000000000002', 'test-bbb', 'closed', 'fixture', '2026-08-20 10:00:00')"
expect_same_output "$left" "$right" show test-bbb --json
expect_reported event-order "$left" "$right" 'table events: row id=00000000-0000-5000-8000-000000000001: column created_at: left "2026-08-20 10:00:00", right "2026-08-20 10:00:01"'
pass "1. an event sequence in another order is reported"

# 2. A missing audit event.
left="$(variant missing-event-left)"
right="$(variant missing-event-right)"
apply_sql "$right" --no-commit <<<"DELETE FROM events WHERE issue_id = 'test-bbb' AND event_type = 'created'"
expect_same_output "$left" "$right" show test-bbb --json
expect_same_output "$left" "$right" list --json
expect_reported missing-event "$left" "$right" 'only in left: issue_id="test-bbb" event_type="created"'
pass "2. a missing event is reported"

# A raw SQL update stamps issues.updated_at with the current time (ON UPDATE
# CURRENT_TIMESTAMP), so the statements below keep it.

# 3. The same rows with an extra Dolt commit, and with another commit message.
# The commits are made at other moments, so the comparison uses the declared
# commit-hash and run-time rules over the window of the writes.
write_rules=(--rules commit-hash,run-time)
since="$(utc_now)"
left="$(variant extra-commit-left)"
right="$(variant extra-commit-right)"
apply_sql "$left" <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'
UPDATE issues SET notes = 'second', updated_at = updated_at WHERE id = 'test-bbb'"
apply_sql "$right" <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'"
apply_sql "$right" <<<"UPDATE issues SET notes = 'second', updated_at = updated_at WHERE id = 'test-bbb'"
expect_same_output "$left" "$right" list --json
expect_same_output "$left" "$right" show test-aaa test-bbb --json
window=(--since "$since" --until "$(utc_now)")
expect_reported extra-commit "$left" "$right" 'revision: commits: count: left ' "${write_rules[@]}" "${window[@]}"
expect_equal extra-commit-control "$left" "$left" "${write_rules[@]}" "${window[@]}"
since="$(utc_now)"
left="$(variant message-left)"
right="$(variant message-right)"
apply_sql "$left" --message 'bd: update issue' <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'"
apply_sql "$right" --message 'bd: close issue' <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'"
expect_same_output "$left" "$right" show test-aaa --json
window=(--since "$since" --until "$(utc_now)")
expect_reported commit-message "$left" "$right" 'message: left "bd: update issue", right "bd: close issue"' "${write_rules[@]}" "${window[@]}"
pass "3. an extra Dolt commit and another commit message are reported"

# 4. The same rows and the same commit graph, but one working set is dirty.
since="$(utc_now)"
left="$(variant dirty-left)"
right="$(variant dirty-right)"
apply_sql "$left" --message 'bd: update issue' <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'
UPDATE issues SET notes = 'second', updated_at = updated_at WHERE id = 'test-bbb'"
apply_sql "$right" --message 'bd: update issue' <<<"UPDATE issues SET notes = 'first', updated_at = updated_at WHERE id = 'test-aaa'"
apply_sql "$right" --no-commit <<<"UPDATE issues SET notes = 'second', updated_at = updated_at WHERE id = 'test-bbb'"
expect_same_output "$left" "$right" list --json
expect_same_output "$left" "$right" show test-aaa test-bbb --json
window=(--since "$since" --until "$(utc_now)")
expect_reported dirty "$left" "$right" 'revision: working set: dirty: left false, right true' "${write_rules[@]}" "${window[@]}"
grep -Fq 'logical state differs: 2 differences' "$fixture_root/dirty.report" || {
	cat "$fixture_root/dirty.report" >&2
	fail "dirty: the report lists more than the working set"
}
pass "4. another working-set dirtiness is reported"

# 5. The same visible issue with another updated_at in the same day (the human
# view prints the date only), and with another hidden column.
left="$(variant updated-at-left)"
right="$(variant updated-at-right)"
apply_sql "$left" --no-commit <<<"UPDATE issues SET updated_at = '2026-08-20 10:00:00' WHERE id = 'test-aaa'"
apply_sql "$right" --no-commit <<<"UPDATE issues SET updated_at = '2026-08-20 10:00:01' WHERE id = 'test-aaa'"
expect_same_output "$left" "$right" show test-aaa
expect_same_output "$left" "$right" list
expect_reported updated-at "$left" "$right" 'table issues: row id=test-aaa: column updated_at: left "2026-08-20 10:00:00", right "2026-08-20 10:00:01"'
left="$(variant hidden-column-left)"
right="$(variant hidden-column-right)"
apply_sql "$left" --no-commit <<<"UPDATE issues SET content_hash = 'one-content-hash', updated_at = updated_at WHERE id = 'test-bbb'"
apply_sql "$right" --no-commit <<<"UPDATE issues SET content_hash = 'another-content-hash', updated_at = updated_at WHERE id = 'test-bbb'"
expect_same_output "$left" "$right" show test-bbb --json
expect_same_output "$left" "$right" list --json
expect_reported hidden-column "$left" "$right" 'table issues: row id=test-bbb: column content_hash: left "one-content-hash", right "another-content-hash"'
grep -Fq 'logical state differs: 1 difference' "$fixture_root/hidden-column.report" || {
	cat "$fixture_root/hidden-column.report" >&2
	fail "hidden-column: the report lists more than the column"
}
pass "5. another updated_at and another hidden column are reported"

# Controls for the write rules: the same upstream writes made at other moments
# are equal under the declared rules and differ exactly; other writes differ.
upstream_writes() {
	local workspace="$1" title="$2"
	oracle_in "$workspace" update test-aaa --title "$title" --json >/dev/null
	oracle_in "$workspace" comments add test-bbb "Second comment" --json >/dev/null
	oracle_in "$workspace" label add test-bbb later --json >/dev/null
	oracle_in "$workspace" close test-aaa --reason done --json >/dev/null
	oracle_in "$workspace" create "Third issue" --id test-ccc --priority 3 --json >/dev/null
}
all_rules=(--rules commit-hash,run-time,derived-row-id,random-token --baseline "$fixture_root/base.state.json")
since="$(utc_now)"
left="$(variant writes-left)"
right="$(variant writes-right)"
upstream_writes "$left" "Renamed issue"
sleep 1
upstream_writes "$right" "Renamed issue"
writes_window=(--since "$since" --until "$(utc_now)")
expect_reported writes-exact "$left" "$right" 'logical state differs'
expect_equal writes-normalized "$left" "$right" "${all_rules[@]}" "${writes_window[@]}"
pass "the same upstream writes at other moments compare equal under the write rules"
since="$(utc_now)"
left="$(variant other-writes-left)"
right="$(variant other-writes-right)"
upstream_writes "$left" "Renamed issue"
upstream_writes "$right" "Renamed otherwise"
window=(--since "$since" --until "$(utc_now)")
expect_reported other-writes "$left" "$right" 'table issues: row id=test-aaa: column title: left "Renamed issue", right "Renamed otherwise"' "${all_rules[@]}" "${window[@]}"
pass "other upstream writes differ under the write rules"

# An upstream read that writes: `types` fills an empty custom_types table from
# types.custom and commits. Its output does not show the write.
emptied="$(variant emptied-types)"
apply_sql "$emptied" <<<"DELETE FROM custom_types"
read_workspace="$fixture_root/emptied-types-read"
copy_tree "$emptied" "$read_workspace"
oracle_in "$read_workspace" types --json >/dev/null
expect_reported read-that-writes "$emptied" "$read_workspace" 'table custom_types: row name=gate: only in right'
pass "a write that an upstream read makes is reported"

# The comparison takes about a second per side or less.
start="$EPOCHREALTIME"
"$logical_state" export "$base" >/dev/null
export_seconds="$(python3 -I -c 'import sys; print(f"{float(sys.argv[2]) - float(sys.argv[1]):.2f}")' "$start" "$EPOCHREALTIME")"
start="$EPOCHREALTIME"
"$logical_state" compare "${all_rules[@]}" "${writes_window[@]}" "$fixture_root/writes-left.state.json" "$fixture_root/writes-right.state.json" >/dev/null
compare_seconds="$(python3 -I -c 'import sys; print(f"{float(sys.argv[2]) - float(sys.argv[1]):.2f}")' "$start" "$EPOCHREALTIME")"
printf 'logical state timing: export %ss per workspace, normalized compare %ss\n' "$export_seconds" "$compare_seconds"
printf 'logical state comparison: PASS\n'
