#!/usr/bin/env bash
# Sourced by the export and snapshot tests. Defines build_export_fixture, which
# fills a fresh disposable workspace through the pinned upstream oracle with
# data that reaches every field of an upstream `bd export --all` line:
# durable issues, wisps (ephemeral and no-history), a template, an event, a
# message, comments, every kind of dependency target, labels, metadata, gate,
# compaction and lease columns, text with <, >, &, U+2028 and other non-ASCII
# characters, a memory, and a config key.
#
# Usage: build_export_fixture WORKSPACE FIXTURE_SQL ORACLE_COMMAND...
# WORKSPACE must be an empty directory that holds the disposable marker.

build_export_fixture() {
	local workspace="$1" fixture_sql="$2"
	shift 2
	local -a oracle=("$@")
	local line_separator
	line_separator="$(printf '\342\200\250')"
	(
		cd "$workspace"
		git init -q
		git config user.name fixture
		git config user.email fixture@example.invalid
		"${oracle[@]}" init --prefix snap --non-interactive --skip-agents --skip-hooks --quiet
		"${oracle[@]}" create "Alpha <tag> & café 日本" --id snap-a \
			--description "Desc with <b>bold</b> & \"quotes\" — ünïcödé${line_separator}end" \
			--design 'Design <d>' --acceptance 'Accept & check' --notes 'Notes ✓' \
			--labels 'zeta,alpha,<lbl>,ünï' --metadata '{"k": "<v>&", "n": [1, 2], "o": {"z": true}}' \
			-e 30 --external-ref 'gh-<9>' --spec-id 'SPEC-<1>' --assignee 'ann' -p 0 \
			--due 2030-01-15 --defer 2031-02-01 --json >/dev/null
		"${oracle[@]}" create "Beta" --id snap-b -t bug --json >/dev/null
		"${oracle[@]}" create "Child of alpha" --parent snap-a --json >/dev/null
		"${oracle[@]}" create "Swarm" --id snap-sw --mol-type swarm --json >/dev/null
		"${oracle[@]}" create "Template" --id snap-t -t epic --json >/dev/null
		"${oracle[@]}" create "Gate" --id snap-g --json >/dev/null
		"${oracle[@]}" create "Event row" --id snap-ev -t event --event-category patrol.muted \
			--event-actor 'agent://x' --event-target snap-a --event-payload '{"x": 1}' --json >/dev/null
		"${oracle[@]}" create "Message row" --id snap-msg -t message --json >/dev/null
		"${oracle[@]}" create "Wisp one" --id snap-w1 --ephemeral --labels wl --json >/dev/null
		"${oracle[@]}" create "Heartbeat" --id snap-hb --ephemeral --wisp-type heartbeat --json >/dev/null
		"${oracle[@]}" create "No history" --id snap-nh --no-history --labels nl --json >/dev/null
		"${oracle[@]}" dep add snap-a snap-b >/dev/null
		"${oracle[@]}" dep add snap-sw snap-a --type related >/dev/null
		"${oracle[@]}" dep add snap-b external:proj:cap >/dev/null
		"${oracle[@]}" dep add snap-w1 snap-b >/dev/null
		"${oracle[@]}" dep add snap-a snap-nh >/dev/null
		"${oracle[@]}" comments add snap-a "First <comment> & más" >/dev/null
		"${oracle[@]}" comments add snap-a "Second comment" >/dev/null
		"${oracle[@]}" comments add snap-w1 "wisp comment" >/dev/null
		"${oracle[@]}" comments add snap-nh "no-history comment" >/dev/null
		"${oracle[@]}" close snap-ev --reason 'done <ok>' >/dev/null
		"${oracle[@]}" update snap-b --claim >/dev/null
		"${oracle[@]}" remember "CANARY-memory-value" --key canary-mem >/dev/null
		"${oracle[@]}" config set custom.canary CANARY-config-value >/dev/null
	)
	# Columns that no bd command sets in v1.2.1.
	printf '%s\n' \
		"UPDATE issues SET is_template = 1 WHERE id = 'snap-t'" \
		"UPDATE issues SET pinned = 1, source_system = 'jira', closed_by_session = 'session-1', sender = 'agent://s', work_type = 'open_competition', storage_class = 'versioned' WHERE id = 'snap-sw'" \
		"UPDATE issues SET await_type = 'gh:run', await_id = '123', timeout_ns = 3600000000000, waiters = '[\"a@x\", null]' WHERE id = 'snap-g'" \
		"UPDATE issues SET compaction_level = 1, compacted_at = '2026-01-02 03:04:05', compacted_at_commit = 'abc123', original_size = 2048 WHERE id = 'snap-sw'" \
		"UPDATE dependencies SET thread_id = 'thread-1' WHERE issue_id = 'snap-sw'" |
		"$fixture_sql" "$workspace" >/dev/null
}

# Prints the issue lines of a `bd export` file, without memory lines, sorted
# by issue ID in byte order. Each line keeps its exact bytes.
sorted_issue_lines() {
	python3 -I -c '
import json
import sys

with open(sys.argv[1], "rb") as source:
    lines = [line for line in source.read().split(b"\n") if line]
issues = [line for line in lines if json.loads(line).get("_type") == "issue"]
issues.sort(key=lambda line: json.loads(line)["id"].encode("utf-8"))
sys.stdout.buffer.write(b"".join(line + b"\n" for line in issues))
' "$1"
}

# Fails unless an upstream export of the fixture reaches the fields and
# encodings that the comparison must cover, so the fixture cannot lose them.
require_export_coverage() {
	local export_file="$1" needle u lt gt amp
	# Go writes these characters as JSON escapes: a backslash, "u" and four hex digits.
	u="$(printf '\134u')"
	lt="${u}003c" gt="${u}003e" amp="${u}0026"
	for needle in "$lt" "$amp" "${u}2028" 'café 日本' \
		"\"metadata\":{\"k\":\"${lt}v${gt}${amp}\",\"n\":[1,2],\"o\":{\"z\":true}}" \
		"\"labels\":[\"${lt}lbl${gt}\",\"alpha\",\"zeta\",\"ünï\"]" '"dependencies":[' '"comments":[' '"ephemeral":true' \
		'"no_history":true' '"wisp_plane":true' '"is_template":true' '"pinned":true' '"timeout":3600000000000' \
		'"waiters":["a@x",""]' '"compaction_level":1' '"compacted_at":"2026-01-02T03:04:05Z"' '"lease_expires_at":' \
		'"heartbeat_at":' '"started_at":' '"closed_at":' "\"close_reason\":\"done ${lt}ok${gt}\"" '"due_at":' \
		'"defer_until":' '"estimated_minutes":30' "\"external_ref\":\"gh-${lt}9${gt}\"" '"event_kind":"patrol.muted"' \
		'"payload":"{\"x\": 1}"' '"mol_type":"swarm"' '"wisp_type":"heartbeat"' '"work_type":"open_competition"' \
		'"storage_class":"versioned"' '"thread_id":"thread-1"' '"depends_on_id":"external:proj:cap"' \
		'"type":"related"' '"type":"parent-child"' '"_type":"memory"'; do
		if ! grep -Fq -- "$needle" "$export_file"; then
			printf 'export fixture lost coverage: %s\n' "$needle" >&2
			return 1
		fi
	done
}
