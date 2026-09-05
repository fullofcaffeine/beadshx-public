#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
oracle="${1:-$repository_root/build/bin/bd-upstream}"
candidate="${2:-$repository_root/build/bin/bdhx}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-parity-smoke.XXXXXX")"
cleanup() {
	while IFS= read -r pid_file; do
		watch_pid="$(cat "$pid_file")"
		kill -TERM "$watch_pid" 2>/dev/null || true
	done < <(find "$test_root" -name '*.watch.pid' -type f)
	find "$test_root" -mindepth 1 -delete
	rmdir "$test_root"
}
trap cleanup EXIT

if [[ ! -x "$oracle" ]]; then
	printf 'upstream oracle is missing: %s\n' "$oracle" >&2
	exit 1
fi
if [[ ! -x "$candidate" ]]; then
	printf 'bdhx candidate is missing: %s\n' "$candidate" >&2
	exit 1
fi
if ! command -v script >/dev/null 2>&1; then
	printf 'pseudo-terminal runner is missing: script\n' >&2
	exit 1
fi

oracle_identity="$("$oracle" version)"
candidate_identity="$("$candidate" version)"

if [[ "$oracle_identity" != *'1.2.1'* || "$oracle_identity" != *'634cbbc4b'* ]]; then
	printf 'unexpected upstream identity: %s\n' "$oracle_identity" >&2
	exit 1
fi
expected_candidate="$(jq -er '.binaries.developmentIdentity' \
	"$repository_root/release/identity-policy.json")"
if [[ "$candidate_identity" != "$expected_candidate" ]]; then
	printf 'unexpected candidate identity: %s\n' "$candidate_identity" >&2
	exit 1
fi

compare_no_workspace() {
	local name="$1"
	shift
	local case_root="$test_root/$name"
	local oracle_root="$case_root/oracle"
	local candidate_root="$case_root/candidate"
	local oracle_exit
	local candidate_exit

	mkdir -p "$oracle_root/home" "$oracle_root/config" "$oracle_root/work"
	mkdir -p "$candidate_root/home" "$candidate_root/config" "$candidate_root/work"

	set +e
	(
		cd "$oracle_root/work"
		env HOME="$oracle_root/home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			BEADS_TELEMETRY_DISABLED=1 \
			BEADS_NO_AUTO_FLUSH=1 \
			BD_DISABLE_METRICS=1 \
			BD_DISABLE_EVENT_FLUSH=1 \
			BD_JSON_ENVELOPE="${BEADSHX_TEST_JSON_ENVELOPE:-0}" \
			NO_COLOR=1 \
			"$oracle" "$@"
	) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr"
	oracle_exit=$?
	(
		cd "$candidate_root/work"
		env HOME="$candidate_root/home" \
			XDG_CONFIG_HOME="$candidate_root/config" \
			BEADS_TELEMETRY_DISABLED=1 \
			BEADS_NO_AUTO_FLUSH=1 \
			BD_DISABLE_METRICS=1 \
			BD_DISABLE_EVENT_FLUSH=1 \
			BD_JSON_ENVELOPE="${BEADSHX_TEST_JSON_ENVELOPE:-0}" \
			NO_COLOR=1 \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	set -e

	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s exit mismatch: upstream=%s candidate=%s\n' \
			"$name" "$oracle_exit" "$candidate_exit" >&2
		return 1
	fi
	if ! cmp -s "$case_root/oracle.stdout" "$case_root/candidate.stdout"; then
		printf '%s stdout differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stdout" "$case_root/candidate.stdout" >&2 || true
		return 1
	fi
	if ! cmp -s "$case_root/oracle.stderr" "$case_root/candidate.stderr"; then
		printf '%s stderr differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stderr" "$case_root/candidate.stderr" >&2 || true
		return 1
	fi
	if [[ -n "$(find "$oracle_root" -mindepth 2 -print -quit)" ]]; then
		printf '%s upstream command persisted files in an empty workspace\n' "$name" >&2
		return 1
	fi
	if [[ -n "$(find "$candidate_root" -mindepth 2 -print -quit)" ]]; then
		printf '%s candidate command persisted files in an empty workspace\n' "$name" >&2
		return 1
	fi
}

compare_no_workspace where where
compare_no_workspace where_json where --json
compare_no_workspace info info
compare_no_workspace info_json info --json
compare_no_workspace info_whats_new_json info --whats-new --json
compare_no_workspace ping ping
compare_no_workspace ping_json ping --json
compare_no_workspace status status
compare_no_workspace status_json status --json
compare_no_workspace stats stats
compare_no_workspace stats_json stats --json
compare_no_workspace where_extra where extra
compare_no_workspace info_extra info extra
compare_no_workspace ping_extra ping extra
compare_no_workspace status_extra status extra
compare_no_workspace stats_extra stats extra
compare_no_workspace version_unknown_long version --frobnicate
compare_no_workspace version_unknown_attached version --frobnicate=value
compare_no_workspace version_unknown_short version -xyz
compare_no_workspace unknown_command frobnicate
compare_no_workspace unknown_command_help frobnicate --help
compare_no_workspace list_help list --help
compare_no_workspace help_list help list
compare_no_workspace show_help show --help
compare_no_workspace help_show help show
compare_no_workspace count count
compare_no_workspace count_json count --json
compare_no_workspace count_help count --help
compare_no_workspace ready ready
compare_no_workspace ready_json ready --json
compare_no_workspace ready_help ready --help
compare_no_workspace search search
compare_no_workspace search_json search --json
compare_no_workspace search_help search --help
compare_no_workspace stale stale
compare_no_workspace stale_json stale --json
compare_no_workspace stale_help stale --help
compare_no_workspace orphans orphans
compare_no_workspace orphans_json orphans --json
compare_no_workspace orphans_help orphans --help
compare_no_workspace children_help children --help
compare_no_workspace children_missing_argument children
compare_no_workspace children_extra_argument children test-parent extra
compare_no_workspace children_no_workspace children test-parent
compare_no_workspace query query
compare_no_workspace query_json query --json
compare_no_workspace query_help query --help
compare_no_workspace query_parse_only query status=open --parse-only
BEADSHX_TEST_JSON_ENVELOPE=1 compare_no_workspace where_json_envelope where --json

fingerprint_tree() {
	local root="$1"
	(
		cd "$root"
		find . -mindepth 1 -print | LC_ALL=C sort
		find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
	) | shasum -a 256 | awk '{print $1}'
}

fingerprint_task_state_tree() {
	local root="$1"
	(
		cd "$root"
		# An open embedded-Dolt reader rewrites its derived journal index and
		# transient nbs_manifest files while it polls. They are not task,
		# revision, configuration, or application state, and cannot reach a
		# stable byte snapshot until the reader closes.
		find . -mindepth 1 \
			! -path '*/.dolt/noms/journal.idx' \
			! -name 'nbs_manifest_*' -print | LC_ALL=C sort
		find . -type f \
			! -path '*/.dolt/noms/journal.idx' \
			! -name 'nbs_manifest_*' \
			-exec shasum -a 256 {} \; | LC_ALL=C sort
	) | shasum -a 256 | awk '{print $1}'
}

wait_for_stable_tree() {
	local root="$1"
	local previous current
	previous="$(fingerprint_tree "$root" 2>/dev/null)"
	# Require one full second without a byte change. Embedded Dolt can replace a
	# derived journal manifest shortly after the command that triggered it exits.
	for _ in {1..20}; do
		sleep 1
		current="$(fingerprint_tree "$root" 2>/dev/null)"
		if [[ "$current" == "$previous" ]]; then
			printf '%s\n' "$current"
			return 0
		fi
		previous="$current"
	done
	printf 'workspace did not reach a stable filesystem fingerprint: %s\n' "$root" >&2
	return 1
}

copy_fixture_tree() {
	local source="$1"
	local destination="$2"
	if [[ "$(uname -s)" == Darwin ]]; then
		cp -cR "$source" "$destination"
	else
		cp -R "$source" "$destination"
	fi
}

compare_store_failure() {
	local scenario="$1"
	local case_name="$2"
	shift 2
	local case_root="$test_root/$scenario-$case_name"
	local oracle_root="$case_root/oracle"
	local candidate_root="$case_root/candidate"
	local oracle_before oracle_after candidate_before candidate_after
	local oracle_exit candidate_exit
	local metadata config_yaml
	case "$scenario" in
	missing-embedded)
		metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"beads"}'
		config_yaml='issue-prefix: test'
		;;
	unavailable-server)
		metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads"}'
		config_yaml=$'issue-prefix: test\ndolt:\n  mode: server\n  auto-start: false'
		;;
	*)
		printf 'unknown store-failure scenario: %s\n' "$scenario" >&2
		return 2
		;;
	esac

	for command_root in "$oracle_root" "$candidate_root"; do
		mkdir -p "$command_root/home" "$command_root/config" "$command_root/work/.beads"
		chmod 700 "$command_root/work/.beads"
		printf '%s\n' "$metadata" >"$command_root/work/.beads/metadata.json"
		printf '%s\n' "$config_yaml" >"$command_root/work/.beads/config.yaml"
	done
	oracle_before="$(fingerprint_tree "$oracle_root")"
	candidate_before="$(fingerprint_tree "$candidate_root")"

	set +e
	(
		cd "$oracle_root/work"
		env HOME="$oracle_root/home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			BEADS_DOLT_AUTO_START=0 \
			BEADS_DOLT_PORT=1 \
			BEADS_TELEMETRY_DISABLED=1 \
			BEADS_NO_AUTO_FLUSH=1 \
			BD_DISABLE_METRICS=1 \
			BD_DISABLE_EVENT_FLUSH=1 \
			NO_COLOR=1 \
			"$oracle" "$@"
	) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr"
	oracle_exit=$?
	(
		cd "$candidate_root/work"
		env HOME="$candidate_root/home" \
			XDG_CONFIG_HOME="$candidate_root/config" \
			BEADS_DOLT_AUTO_START=0 \
			BEADS_DOLT_PORT=1 \
			BEADS_TELEMETRY_DISABLED=1 \
			BEADS_NO_AUTO_FLUSH=1 \
			BD_DISABLE_METRICS=1 \
			BD_DISABLE_EVENT_FLUSH=1 \
			NO_COLOR=1 \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	set -e

	[[ "$oracle_exit" -eq "$candidate_exit" ]]
	cmp -s "$case_root/oracle.stdout" "$case_root/candidate.stdout"
	cmp -s "$case_root/oracle.stderr" "$case_root/candidate.stderr"
	oracle_after="$(fingerprint_tree "$oracle_root")"
	candidate_after="$(fingerprint_tree "$candidate_root")"
	[[ "$oracle_before" == "$oracle_after" ]]
	[[ "$candidate_before" == "$candidate_after" ]]
}

for command in info ping status; do
	compare_store_failure missing-embedded "$command" "$command"
done
compare_store_failure missing-embedded info-whats-new info --whats-new
compare_store_failure missing-embedded info-whats-new-json info --whats-new --json
compare_store_failure missing-embedded info-whats-new-global info --whats-new --global
compare_store_failure unavailable-server info info

real_database_seed="$test_root/real-database-seed"
mkdir -p "$real_database_seed/home" "$real_database_seed/config" "$real_database_seed/work"
touch "$real_database_seed/work/.beadshx-disposable-fixture"
real_database_env=(
	BEADS_ACTOR=fixture
	BEADS_TELEMETRY_DISABLED=1
	BEADS_NO_AUTO_FLUSH=1
	BD_DISABLE_METRICS=1
	BD_DISABLE_EVENT_FLUSH=1
	NO_COLOR=1
)
(
	cd "$real_database_seed/work"
	git init -q
	git config user.name fixture
	git config user.email fixture@example.invalid
	seed_command=(env HOME="$real_database_seed/home" \
		XDG_CONFIG_HOME="$real_database_seed/config" \
		"${real_database_env[@]}" "$oracle")
	"${seed_command[@]}" init --prefix test --non-interactive --skip-agents --skip-hooks --quiet
	"${seed_command[@]}" create "Open parity issue" --priority 1 --assignee fixture \
		--description "Description body" --design "Design body" --notes "Notes body" \
		--acceptance "Acceptance body" --json >"$real_database_seed/issue.json"
	"${seed_command[@]}" create "Bug parity issue" --priority 0 --type bug --json >"$real_database_seed/bug.json"
	"${seed_command[@]}" create "Content parity issue" --priority 1 \
		--description $'# Heading\n\nSome **bold** text and `code`.' \
		--design $'## Design\n\n- typed\n- exact' --notes "Plain notes" \
		--acceptance "Rendered output matches" --json >"$real_database_seed/content.json"
	"${seed_command[@]}" create "Epic parity issue" --priority 2 --type epic --json >"$real_database_seed/epic.json"
	"${seed_command[@]}" create "Child parity issue" --priority 2 --parent "$(jq -er '.id' "$real_database_seed/epic.json")" --json \
		>"$real_database_seed/child.json"
	"${seed_command[@]}" create "Grandchild parity issue" --priority 2 --parent "$(jq -er '.id' "$real_database_seed/child.json")" --json \
		>"$real_database_seed/grandchild.json"
	"${seed_command[@]}" create "Progress parity issue" --priority 1 --status in_progress --assignee fixture --json \
		>"$real_database_seed/progress.json"
	"${seed_command[@]}" create "Pinned parity issue" --priority 2 --status pinned --json >"$real_database_seed/pinned.json"
	"${seed_command[@]}" create "Molecule parity issue" --priority 2 --type molecule --mol-type swarm --json >"$real_database_seed/molecule.json"
	"${seed_command[@]}" create "Molecule first step" --priority 1 --parent "$(jq -er '.id' "$real_database_seed/molecule.json")" --json \
		>"$real_database_seed/molecule-step-one.json"
	"${seed_command[@]}" create "Molecule blocked step" --priority 2 --parent "$(jq -er '.id' "$real_database_seed/molecule.json")" \
		--deps "depends-on:$(jq -er '.id' "$real_database_seed/molecule-step-one.json")" --json \
		>"$real_database_seed/molecule-step-two.json"
	"${seed_command[@]}" create "Molecule unrelated parent" --priority 2 --json >"$real_database_seed/molecule-other-parent.json"
	"${seed_command[@]}" create "Molecule hierarchical fallback step" \
		--id "$(jq -er '.id' "$real_database_seed/molecule.json").99" --priority 3 --json \
		>"$real_database_seed/molecule-fallback-step.json"
	"${seed_command[@]}" create "Molecule reparented hierarchical lookalike" \
		--id "$(jq -er '.id' "$real_database_seed/molecule.json").100" --priority 3 --json \
		>"$real_database_seed/molecule-reparented-step.json"
	"${seed_command[@]}" dep add \
		"$(jq -er '.id' "$real_database_seed/molecule-reparented-step.json")" \
		"$(jq -er '.id' "$real_database_seed/molecule-other-parent.json")" \
		--type parent-child >/dev/null
	"${seed_command[@]}" config set types.custom gate >/dev/null
	"${seed_command[@]}" create "Gated parity molecule" --priority 2 --type epic --json >"$real_database_seed/gated-molecule.json"
	"${seed_command[@]}" create "Closed parity gate" --priority 2 --type gate \
		--parent "$(jq -er '.id' "$real_database_seed/gated-molecule.json")" --json >"$real_database_seed/gated-gate.json"
	"${seed_command[@]}" create "Ready after parity gate" --priority 2 \
		--parent "$(jq -er '.id' "$real_database_seed/gated-molecule.json")" --json >"$real_database_seed/gated-step.json"
	"${seed_command[@]}" dep add "$(jq -er '.id' "$real_database_seed/gated-step.json")" \
		"$(jq -er '.id' "$real_database_seed/gated-gate.json")" >/dev/null
	"${seed_command[@]}" close "$(jq -er '.id' "$real_database_seed/gated-gate.json")" --reason satisfied --json >/dev/null
	"${seed_command[@]}" create "Wisp classification issue" --priority 2 --wisp-type heartbeat --json >"$real_database_seed/wisp.json"
	"${seed_command[@]}" create "Closed parity issue" --priority 3 --json >"$real_database_seed/closed.json"
	"${seed_command[@]}" create "Unique abbreviation issue" --id test-abcd11 --json >"$real_database_seed/abbreviation-one.json"
	"${seed_command[@]}" create "Ambiguous abbreviation issue" --id test-abcd22 --json >"$real_database_seed/abbreviation-two.json"
	printf '%s\n' \
		'{"id":"test-msg-root","title":"Root message","description":"Root body","status":"open","priority":2,"issue_type":"message","assignee":"bob","sender":"alice","created_at":"2026-08-20T10:00:00Z","updated_at":"2026-08-20T10:00:00Z"}' \
		'{"id":"test-msg-reply","title":"Re: Root","description":"First line\nSecond line","status":"open","priority":2,"issue_type":"message","assignee":"alice","sender":"bob","created_at":"2026-08-20T11:00:00Z","updated_at":"2026-08-20T11:00:00Z"}' \
		'{"id":"test-msg-leaf","title":"Re: Re: Root","description":"Leaf body","status":"closed","priority":2,"issue_type":"message","assignee":"bob","sender":"alice","created_at":"2026-08-20T12:00:00Z","updated_at":"2026-08-20T12:00:00Z","closed_at":"2026-08-20T13:00:00Z"}' |
		"${seed_command[@]}" import - --json >/dev/null
	open_id="$(jq -er '.id' "$real_database_seed/issue.json")"
	"${seed_command[@]}" dep add "$(jq -er '.id' "$real_database_seed/abbreviation-one.json")" \
		"$(jq -er '.id' "$real_database_seed/epic.json")" --type relates-to >/dev/null
	"${seed_command[@]}" dep add "$(jq -er '.id' "$real_database_seed/abbreviation-one.json")" \
		"$(jq -er '.id' "$real_database_seed/abbreviation-two.json")" --type blocks >/dev/null
	"${seed_command[@]}" dep add test-msg-reply test-msg-root --type replies-to >/dev/null
	"${seed_command[@]}" dep add test-msg-leaf test-msg-reply --type replies-to >/dev/null
	"${seed_command[@]}" update "$open_id" --estimate 30 --due 2026-12-31 \
		--defer 2026-08-23 --external-ref gh-42 --spec-id spec-parity \
		--metadata '{"rank":2,"team":"port","whole":1.0,"scientific":1e3,"negative_zero":-0,"fraction":1.25,"enabled":true,"missing":null,"list":[3.0,{"z":2,"a":"x"}],"a\u0062":"decoded","nested":{"text":"a,}: [b]","flags":[true,false,null]}}' \
		--json >/dev/null
	"${seed_command[@]}" label add "$open_id" parity,smoke --json >/dev/null
	"${seed_command[@]}" label add "$(jq -er '.id' "$real_database_seed/content.json")" alpha,beta --json >/dev/null
	"${seed_command[@]}" comments add "$open_id" "Parity comment" --json >/dev/null
	closed_id="$(jq -er '.id' "$real_database_seed/closed.json")"
	"${seed_command[@]}" close "$closed_id" --reason done --json >/dev/null
	git commit -q --allow-empty -m "baseline"
	git commit -q --allow-empty -m "feat: implement ($open_id)"
)
real_database_issue_id="$(jq -er '.id' "$real_database_seed/issue.json")"
real_database_bug_id="$(jq -er '.id' "$real_database_seed/bug.json")"
real_database_content_id="$(jq -er '.id' "$real_database_seed/content.json")"
real_database_epic_id="$(jq -er '.id' "$real_database_seed/epic.json")"
real_database_molecule_id="$(jq -er '.id' "$real_database_seed/molecule.json")"
real_database_gated_molecule_id="$(jq -er '.id' "$real_database_seed/gated-molecule.json")"
real_database_gated_step_id="$(jq -er '.id' "$real_database_seed/gated-step.json")"
real_database_child_id="$(jq -er '.id' "$real_database_seed/child.json")"
real_database_progress_id="$(jq -er '.id' "$real_database_seed/progress.json")"
real_database_closed_id="$(jq -er '.id' "$real_database_seed/closed.json")"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config=""
real_database_extra_import=""
real_database_case_count=0

compare_real_database() {
	local name="$1"
	local comparison="$2"
	shift 2
	real_database_case_count=$((real_database_case_count + 1))
	local case_root="$test_root/real-database-$name"
	local oracle_root="$case_root/oracle-state"
	local candidate_root="$case_root/candidate-state"
	local oracle_exit candidate_exit candidate_before candidate_after
	for state_root in "$oracle_root" "$candidate_root"; do
		mkdir -p "$state_root/user-home/.dolt" "$state_root/config"
		printf '{}\n' >"$state_root/user-home/.dolt/config_global.json"
		copy_fixture_tree "$real_database_seed/work" "$state_root/work"
		chmod 700 "$state_root/work/.beads"
		if [[ -n "$real_database_extra_config" ]]; then
			printf '%s\n' "$real_database_extra_config" >>"$state_root/work/.beads/config.yaml"
		fi
		if [[ -n "$real_database_extra_import" ]]; then
			(
				cd "$state_root/work"
				printf '%s\n' "$real_database_extra_import" |
					env HOME="$state_root/user-home" \
						XDG_CONFIG_HOME="$state_root/config" \
						"${real_database_env[@]}" \
						"$oracle" import - --json >/dev/null 2>&1
			)
		fi
	done
	candidate_before="$(fingerprint_tree "$candidate_root")"

	set +e
	(
		cd "$oracle_root/work"
		env HOME="$oracle_root/user-home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			"${real_database_env[@]}" \
			"${real_database_extra_env[@]}" \
			"$oracle" "$@"
	) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr"
	oracle_exit=$?
	(
		cd "$candidate_root/work"
		env HOME="$candidate_root/user-home" \
			XDG_CONFIG_HOME="$candidate_root/config" \
			"${real_database_env[@]}" \
			"${real_database_extra_env[@]}" \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	candidate_after="$(fingerprint_tree "$candidate_root")"
	set -e

	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s exit mismatch: upstream=%s candidate=%s\n' \
			"$name" "$oracle_exit" "$candidate_exit" >&2
		return 1
	fi
	if ! cmp -s "$case_root/oracle.stderr" "$case_root/candidate.stderr"; then
		printf '%s stderr differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stderr" "$case_root/candidate.stderr" >&2 || true
		return 1
	fi
	if [[ "$candidate_before" != "$candidate_after" ]]; then
		printf '%s candidate command changed the read-only fixture\n' "$name" >&2
		return 1
	fi
	case "$comparison" in
	exact)
		local oracle_work candidate_work
		oracle_work="$(cd "$oracle_root/work" && pwd -P)"
		candidate_work="$(cd "$candidate_root/work" && pwd -P)"
		sed "s|$oracle_work|<work>|g" "$case_root/oracle.stdout" >"$case_root/oracle.normalized"
		sed "s|$candidate_work|<work>|g" "$case_root/candidate.stdout" >"$case_root/candidate.normalized"
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	show-grouped-multi)
		# Pinned direct mode ranges over a Go map of parent IDs, so only the
		# block order is unstable. Compare the exact rendered line multiset.
		LC_ALL=C sort "$case_root/oracle.stdout" >"$case_root/oracle.normalized"
		LC_ALL=C sort "$case_root/candidate.stdout" >"$case_root/candidate.normalized"
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout content differs from upstream\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	ping-human)
		sed -E 's/[0-9]+ms/<duration>/' "$case_root/oracle.stdout" >"$case_root/oracle.normalized"
		sed -E 's/[0-9]+ms/<duration>/' "$case_root/candidate.stdout" >"$case_root/candidate.normalized"
		cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"
		;;
	ping-json)
		for side in oracle candidate; do
			jq -e '
				all(.query_ms, .resolve_ms, .store_ms, .total_ms; type == "number" and . >= 0) and
				.total_ms == (.query_ms + .resolve_ms + .store_ms)
			' "$case_root/$side.stdout" >/dev/null
			jq -S 'del(.query_ms, .resolve_ms, .store_ms, .total_ms)' \
				"$case_root/$side.stdout" >"$case_root/$side.normalized"
		done
		cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"
		;;
	molecule-ready-json)
		for side in oracle candidate; do
			jq -S '
				(.parallel_groups[]? |= sort) |
				(.steps[]?.parallel_info.blocked_by |= sort) |
				(.steps[]?.parallel_info.blocks |= sort) |
				(.steps[]?.parallel_info.can_parallel |= sort)
			' "$case_root/$side.stdout" >"$case_root/$side.normalized"
		done
		cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"
		;;
	*)
		printf 'unknown real-database comparison: %s\n' "$comparison" >&2
		return 2
		;;
	esac
}

compare_real_database_config() {
	local name="$1"
	local comparison="$2"
	local config="$3"
	shift 3
	real_database_extra_config="$config"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_config=""
}

compare_real_database_env() {
	local name="$1"
	local comparison="$2"
	local environment="$3"
	shift 3
	real_database_extra_env=("$environment")
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
}

compare_real_database_import() {
	local name="$1"
	local comparison="$2"
	local import_record="$3"
	shift 3
	real_database_extra_import="$import_record"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_import=""
}

compare_real_database info-schema-json exact info --schema --json
compare_real_database status-json exact status --json
compare_real_database ping-human ping-human ping
compare_real_database ping-json ping-json ping --json
compare_real_database count-human exact count
compare_real_database count-json exact count --json
compare_real_database count-status-json exact count --status open --json
compare_real_database count-by-status-json exact count --by-status --json
compare_real_database count-by-label-human exact count --by-label
compare_real_database ready-human exact ready
compare_real_database ready-plain exact ready --plain
compare_real_database ready-json exact ready --json
compare_real_database ready-limit-human exact ready --limit 2
compare_real_database ready-limit-json exact ready --limit 2 --json
compare_real_database ready-molecule-human exact ready --mol "$real_database_molecule_id"
compare_real_database ready-molecule-json molecule-ready-json ready --mol "$real_database_molecule_id" --json
compare_real_database ready-explain-human exact ready --explain
compare_real_database ready-explain-json exact ready --explain --json
compare_real_database ready-gated-human exact ready --gated
compare_real_database ready-gated-json exact ready --gated --json
compare_real_database search-human exact search parity
compare_real_database search-long exact search parity --long
compare_real_database search-json exact search parity --json
compare_real_database search-missing exact search
compare_real_database search-missing-json exact search --json
compare_real_database search-query-flag exact search --query parity
compare_real_database query-help exact query --help
compare_real_database query-parse-simple exact query status=open --parse-only
compare_real_database query-parse-and exact query 'status=open AND priority>1' --parse-only
compare_real_database query-parse-group exact query '(status=open OR status=blocked) AND priority<2' --parse-only
compare_real_database query-parse-not exact query 'NOT (status=closed OR status=deferred)' --parse-only
compare_real_database query-parse-metadata exact query 'metadata.Jira/Sprint=42' --parse-only
compare_real_database query-parse-string exact query 'title="hello world"' --parse-only
compare_real_database query-parse-digit exact query assignee=1-alpha --parse-only
compare_real_database query-parse-unicode-unquoted exact query 'title=é' --parse-only
compare_real_database query-parse-unicode-quoted exact query 'title="é"' --parse-only
compare_real_database query-parse-missing-value exact query status= --parse-only
compare_real_database query-parse-unclosed-parenthesis exact query '(status=open' --parse-only
compare_real_database query-parse-invalid-character exact query status@open --parse-only
compare_real_database query-parse-empty exact query '' --parse-only
compare_real_database query-parse-negative-offset exact query status=open --parse-only --offset -1
compare_real_database query-parse-negative-offset-attached exact query status=open --parse-only --offset=-1
compare_real_database query-parse-invalid-sort exact query status=open --parse-only --sort bogus
compare_real_database query-status-human exact query status=open
compare_real_database query-status-json exact query status=open --json
compare_real_database query-and-json exact query 'status=open AND priority=1' --json
compare_real_database query-title-human exact query title=parity
compare_real_database query-label-json exact query label=smoke --json
compare_real_database query-metadata-json exact query metadata.team=port --json
compare_real_database query-parent-json exact query "parent=$real_database_epic_id" --json
compare_real_database query-pinned-json exact query pinned=true --json
compare_real_database query-id-wildcard-json exact query 'id=test-abcd*' --json
compare_real_database query-default-closed-json exact query 'priority>=0' --json
compare_real_database query-all-json exact query 'priority>=0' --all --json
compare_real_database query-sort-limit-json exact query status=open --sort title --reverse --limit 2 --json
compare_real_database query-long exact query status=open --long --limit 1
compare_real_database query-no-match exact query title=absent-query-token
compare_real_database query-offset-direct exact query status=open --offset 1 --json
compare_real_database search-id-prefix exact search test-abcd
compare_real_database search-status exact search parity --status open
compare_real_database search-label exact search parity --label smoke
compare_real_database search-label-any exact search parity --label-any alpha,smoke
compare_real_database search-priority-range exact search parity --priority-min P0 --priority-max P1
compare_real_database search-description exact search issue --desc-contains 'Description body'
compare_real_database search-notes exact search issue --notes-contains 'Notes body'
compare_real_database search-external exact search issue --external-contains gh-42
compare_real_database search-metadata exact search issue --metadata-field team=port --has-metadata-key rank
compare_real_database search-sort-reverse exact search parity --sort title --reverse
compare_real_database search-no-match exact search absent-search-token
compare_real_database stale-default exact stale
compare_real_database stale-human exact stale --days 1
compare_real_database stale-json exact stale --days 1 --json
compare_real_database stale-status-open exact stale --days 1 --status open
compare_real_database stale-status-deferred exact stale --days 1 --status deferred
compare_real_database stale-limit exact stale --days 1 --limit 1
compare_real_database stale-short-flags exact stale -d 1 -s open -n 1
compare_real_database stale-invalid-days exact stale --days 0
compare_real_database stale-invalid-days-json exact stale --days 0 --json
compare_real_database stale-invalid-status-json exact stale --status closed --json
compare_real_database orphans-human exact orphans
compare_real_database orphans-details exact orphans --details
compare_real_database orphans-details-false exact orphans --details=false
compare_real_database orphans-fix-false-short exact orphans -f=false
compare_real_database orphans-json exact orphans --json
compare_real_database orphans-label exact orphans --label parity
compare_real_database orphans-label-short exact orphans -l parity
compare_real_database orphans-label-short-equals exact orphans -l=parity
compare_real_database orphans-label-any exact orphans --label-any alpha,parity
compare_real_database orphans-label-miss-json exact orphans --label absent-orphan-label --json
compare_real_database ready-priority-json exact ready --priority 1 --json
compare_real_database ready-priority-outside-json exact ready --priority 5 --json
compare_real_database ready-type-json exact ready --type task --json
compare_real_database ready-assignee-json exact ready --assignee fixture --json
compare_real_database ready-unassigned-json exact ready --unassigned --json
compare_real_database ready-label-json exact ready --label alpha --json
compare_real_database ready-label-any-json exact ready --label-any alpha,parity --json
compare_real_database ready-exclude-label-json exact ready --exclude-label alpha --json
compare_real_database ready-label-pattern-json exact ready --label-pattern 'par*' --json
compare_real_database ready-label-regex-json exact ready --label-regex '^(alpha|parity)$' --json
compare_real_database ready-exclude-type-json exact ready --exclude-type epic --json
compare_real_database ready-parent-json exact ready --parent "$real_database_epic_id" --json
compare_real_database ready-mol-type-json exact ready --mol-type swarm --json
compare_real_database ready-metadata-field-json exact ready --metadata-field team=port --json
compare_real_database ready-has-metadata-key-json exact ready --has-metadata-key rank --json
compare_real_database ready-sort-hybrid-json exact ready --sort hybrid --json
compare_real_database ready-sort-oldest-json exact ready -s oldest --json
compare_real_database ready-brief-json exact ready --brief --json
compare_real_database ready-include-deferred-json exact ready --include-deferred --json
compare_real_database ready-include-ephemeral-json exact ready --include-ephemeral --json
compare_real_database ready-invalid-sort-json exact ready --sort invalid --json
compare_real_database ready-invalid-mol-type-json exact ready --mol-type invalid --json
compare_real_database ready-invalid-metadata-json exact ready --metadata-field missing-equals --json
compare_real_database ready-offset-direct-json exact ready --offset 1 --json
compare_real_database ready-max-rows exact ready --max-rows 1 --limit 0 --json
compare_real_database ready-claim-readonly exact --readonly ready --claim
compare_real_database list-human exact list
compare_real_database list-json exact list --json
compare_real_database list-status-json exact list -s in_progress --json
compare_real_database list-type-json exact list -t bug --json
compare_real_database list-priority-json exact list -p P1 --json
compare_real_database list-assignee-json exact list -a fixture --json
compare_real_database list-title-json exact list --title Content --json
compare_real_database list-spec-json exact list --spec spec- --json
compare_real_database list-id-json exact list --id="$real_database_issue_id" --json
compare_real_database list-label-json exact list -l parity --json
compare_real_database list-label-any-json exact list --label-any alpha,parity --json
compare_real_database list-exclude-label-json exact list --exclude-label parity --json
compare_real_database list-all-json exact list --all --json
compare_real_database list-sort-reverse-json exact list --sort title --reverse --json
compare_real_database list-limit-human exact list -n 2
compare_real_database_config list-config-limit-json exact $'list:\n  limit: 2' list --json
compare_real_database list-ready-human exact list --ready
compare_real_database list-ready-json exact list --ready --json
compare_real_database list-priority-min-json exact list --priority-min P1 --json
compare_real_database list-priority-max-json exact list --priority-max 1 --json
compare_real_database list-no-assignee-json exact list --no-assignee --json
compare_real_database list-no-labels-json exact list --no-labels --json
compare_real_database list-brief-json exact list --brief --json
compare_real_database list-pinned-json exact list --pinned --json
compare_real_database list-all-no-pinned-json exact list --all --no-pinned --json
compare_real_database list-no-parent-json exact list --no-parent --json
compare_real_database list-parent-human exact list --parent "$real_database_epic_id"
compare_real_database children-human exact children "$real_database_gated_molecule_id"
compare_real_database children-json exact children "$real_database_gated_molecule_id" --json
compare_real_database children-pretty exact children "$real_database_gated_molecule_id" --pretty
compare_real_database children-nested-human exact children "$real_database_epic_id"
compare_real_database children-empty-human exact children "$real_database_bug_id"
compare_real_database children-empty-json exact children "$real_database_bug_id" --json
compare_real_database children-missing-human exact children test-missing
compare_real_database children-missing-json exact children test-missing --json
compare_real_database dep-list-single-human exact dep list "$real_database_gated_step_id"
compare_real_database dep-list-single-json exact dep list "$real_database_gated_step_id" --json
compare_real_database dep-list-single-filter-json exact dep list "$real_database_gated_step_id" --type blocks --json
compare_real_database dep-list-single-invalid-type-json exact dep list "$real_database_gated_step_id" --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
compare_real_database dep-list-batch-json exact dep list "$real_database_gated_step_id" "$real_database_issue_id" --json
compare_real_database dep-list-batch-filter-json exact dep list "$real_database_gated_step_id" "$real_database_issue_id" --type blocks --json
compare_real_database dep-list-batch-missing-json exact dep list "$real_database_gated_step_id" test-missing --json
compare_real_database dep-list-batch-invalid-type-json exact dep list "$real_database_gated_step_id" "$real_database_issue_id" --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
compare_real_database list-label-pattern-json exact list --label-pattern 'par*' --json
compare_real_database list-label-regex-json exact list --label-regex '^(alpha|parity)$' --json
compare_real_database list-title-contains-json exact list --title-contains parity --json
compare_real_database list-desc-contains-json exact list --desc-contains body --json
compare_real_database list-notes-contains-json exact list --notes-contains notes --json
compare_real_database list-external-contains-json exact list --external-contains gh- --json
compare_real_database list-external-ref-json exact list --external-ref gh-42 --json
compare_real_database list-empty-description-json exact list --empty-description --json
compare_real_database list-mol-type-json exact list --mol-type swarm --json
compare_real_database list-wisp-type-json exact list --wisp-type heartbeat --json
compare_real_database list-metadata-field-json exact list --metadata-field team=port --json
compare_real_database list-has-metadata-key-json exact list --has-metadata-key rank --json
compare_real_database list-ready-attached-false-json exact list --ready=false --json
compare_real_database list-invalid-mol-type exact list --mol-type invalid
compare_real_database list-invalid-wisp-type exact list --wisp-type invalid
compare_real_database list-invalid-metadata-syntax exact list --metadata-field missing-equals
compare_real_database list-invalid-metadata-key exact list --metadata-field 'bad$key=value'
compare_real_database list-invalid-has-metadata-key exact list --has-metadata-key 'bad$key'
compare_real_database list-invalid-attached-boolean exact list --ready=maybe
compare_real_database list-created-after-json exact list --created-after=2000-01-01 --json
compare_real_database list-created-after-relative-json exact list --created-after=-1d --json
compare_real_database list-created-before-json exact list --created-before 2100-01-01 --json
compare_real_database list-updated-after-json exact list --updated-after 2000-01-01 --json
compare_real_database list-updated-before-json exact list --updated-before 2100-01-01 --json
compare_real_database list-closed-after-json exact list --all --closed-after 2000-01-01 --json
compare_real_database list-closed-before-json exact list --all --closed-before 2100-01-01 --json
compare_real_database list-defer-after-json exact list --defer-after 2026-08-22 --json
compare_real_database list-defer-before-json exact list --defer-before 2026-08-24 --json
compare_real_database list-due-after-json exact list --due-after 2026-12-30 --json
compare_real_database list-due-before-json exact list --due-before 2027-01-01 --json
compare_real_database list-invalid-created-after exact list --created-after not-a-date
compare_real_database list-exclude-type-json exact list --exclude-type bug,epic --json
compare_real_database list-overdue-json exact list --overdue --json
compare_real_database list-deferred-json exact list --deferred --json
compare_real_database list-offset-json exact list --offset 1 --limit 2 --json
compare_real_database list-skip-labels-json exact list --skip-labels --json
compare_real_database list-skip-labels-human exact list --skip-labels
compare_real_database list-skip-labels-conflicts exact list --skip-labels --label parity --label-any alpha --label-pattern 'par*' --label-regex parity --exclude-label smoke --no-labels
compare_real_database list-skip-labels-conflict-json exact list --skip-labels --label parity --json
compare_real_database list-flat-human exact list --flat
compare_real_database list-flat-long-human exact list --flat --long
compare_real_database list-flat-long-brief-human exact list --flat --long --brief
compare_real_database list-long-tree-human exact list --long
compare_real_database list-tree-false-human exact list --tree=false
compare_real_database list-pretty-human exact list --pretty
compare_real_database list-flat-pretty-human exact list --flat --pretty
compare_real_database list-no-pager-human exact list --no-pager
compare_real_database list-deps-bare exact list --deps --limit 0
compare_real_database list-deps-all exact list --deps=all --limit 0
compare_real_database list-deps-outside exact list --id=test-abcd11 --deps=all --limit 0
compare_real_database list-deps-tree-false exact list --tree=false --deps --limit 0
compare_real_database list-deps-invalid exact list --deps=bogus
compare_real_database list-deps-json-conflict exact list --deps --json
compare_real_database list-deps-format-conflict exact list --deps --format=digraph
compare_real_database list-deps-flat-conflict exact list --deps --flat
compare_real_database list-format-digraph exact list --format=digraph --limit 0
compare_real_database list-format-digraph-separated exact list --format digraph --limit 0
compare_real_database list-format-dot exact list --format=dot --limit 0
compare_real_database list-format-template exact list '--format={{.IssueID}} -> {{.DependsOnID}} [{{.Type}}] {{.Issue.Title}}/{{.Dependency.Type}}' --limit 0
compare_real_database list-format-invalid-template exact list '--format={{.IssueID'
compare_real_database list-format-json-alias exact list --format=json --limit 2
compare_real_database list-format-json-precedence exact list --format=digraph --json --limit 2
compare_real_database list-max-rows-human exact list --limit 0 --max-rows 1
compare_real_database_env list-max-rows-env-human exact BEADS_MAX_ROWS=1 list --limit 0
compare_real_database_env list-max-rows-env-flag-zero exact BEADS_MAX_ROWS=1 list --limit 1 --max-rows 0
compare_real_database_env list-max-rows-env-malformed exact BEADS_MAX_ROWS=banana list --limit 1
compare_real_database list-max-rows-negative exact list --max-rows -1
compare_real_database list-watch-brief exact list --watch --brief
compare_real_database list-watch-deps exact list --watch --deps
compare_real_database list-watch-max-rows exact list --watch --limit 0 --max-rows 1
compare_real_database show-short exact show "$real_database_issue_id" --short
compare_real_database show-short-id exact show --id "$real_database_issue_id" --short
compare_real_database show-short-id-attached exact show --id="$real_database_issue_id" --short
compare_real_database show-short-id-repeated exact show --id="$real_database_issue_id" --id="$real_database_issue_id" --short
compare_real_database show-short-mixed-ids exact show "$real_database_issue_id" --id="$real_database_issue_id" --short
compare_real_database view-short exact view "$real_database_issue_id" --short
compare_real_database show-short-bug exact show "$real_database_bug_id" --short
compare_real_database show-human-bug exact show "$real_database_bug_id"
compare_real_database show-json-bug exact show "$real_database_bug_id" --json
compare_real_database show-human-content exact show "$real_database_content_id"
compare_real_database show-human-rich exact show "$real_database_issue_id"
compare_real_database show-short-epic exact show "$real_database_epic_id" --short
compare_real_database show-short-progress exact show "$real_database_progress_id" --short
compare_real_database show-short-closed exact show "$real_database_closed_id" --short
compare_real_database show-short-prefixless exact show "${real_database_issue_id#test-}" --short
compare_real_database show-short-child exact show "$real_database_child_id" --short
compare_real_database show-short-child-prefixless exact show "${real_database_child_id#test-}" --short
compare_real_database show-short-abbreviated exact show abcd1 --short
compare_real_database show-short-ambiguous exact show abcd --short
compare_real_database show-short-current-assigned exact show --current --short
compare_real_database show-short-current-last-touched exact --actor unmatched show --current --short
compare_real_database show-short-current-explicit exact show "$real_database_issue_id" --current --short
compare_real_database show-short-missing exact show test-missing --short
compare_real_database show-short-missing-json exact show test-missing --short --json
compare_real_database show-short-success-json exact show "$real_database_issue_id" --short --json
compare_real_database show-json exact show "$real_database_issue_id" --json
compare_real_database show-json-epic exact show "$real_database_epic_id" --json
compare_real_database show-json-progress exact show "$real_database_progress_id" --json
compare_real_database show-json-closed exact show "$real_database_closed_id" --json
compare_real_database show-json-child exact show "$real_database_child_id" --json
compare_real_database show-human-child exact show "$real_database_child_id"
compare_real_database show-human-epic exact show "$real_database_epic_id"
compare_real_database show-long-open exact show "$real_database_issue_id" --long
compare_real_database show-long-closed exact show "$real_database_closed_id" --long
compare_real_database show-long-pinned exact show "$(jq -er '.id' "$real_database_seed/pinned.json")" --long
compare_real_database show-long-molecule exact show "$(jq -er '.id' "$real_database_seed/molecule.json")" --long
rare_long_record='{"id":"test-rare","title":"Rare long","description":"tiny","status":"open","priority":2,"issue_type":"event","created_at":"2026-08-20T12:00:00Z","updated_at":"2026-08-21T13:00:00Z","compaction_level":1,"compacted_at":"2026-08-21T14:00:00Z","compacted_at_commit":"abc123","original_size":100,"sender":"agent-a","ephemeral":true,"wisp_type":"heartbeat","pinned":true,"is_template":true,"bonded_from":[{"source_id":"proto-a","bond_type":"parallel","bond_point":"root"}],"await_type":"human","await_id":"approval","timeout":60000000000,"waiters":["alpha","beta"],"source_formula":"release","source_location":"steps[0]","mol_type":"swarm","work_type":"open_competition","event_kind":"agent.started","actor":"agent://a","target":"bead://b","payload":"{\"k\":1}"}'
compare_real_database_import show-long-rare exact "$rare_long_record" show test-rare --long
compare_real_database_import show-thread-json-rare exact "$rare_long_record" show test-rare --thread --json
compare_real_database show-thread-human exact show test-msg-leaf --thread
compare_real_database show-thread-json exact show test-msg-leaf ignored-second --thread --json
compare_real_database show-thread-disabled exact show test-msg-root --thread=false
compare_real_database show-children-human exact show "$real_database_epic_id" --children
compare_real_database show-children-short exact show "$real_database_epic_id" --children --short
compare_real_database show-children-json exact show "$real_database_epic_id" --children --json
compare_real_database show-children-empty-human exact show "$real_database_bug_id" --children
compare_real_database show-children-empty-json exact show "$real_database_bug_id" --children --json
compare_real_database show-children-multiple show-grouped-multi show "$real_database_epic_id" "$real_database_bug_id" --children
compare_real_database show-children-disabled exact show "$real_database_bug_id" --children=false
compare_real_database_env show-children-json-envelope exact BD_JSON_ENVELOPE=1 show "$real_database_epic_id" --children --json
compare_real_database show-refs-human exact show "$real_database_epic_id" --refs
compare_real_database show-refs-short-ignored exact show "$real_database_epic_id" --refs --short
compare_real_database show-refs-json exact show "$real_database_epic_id" --refs --json
compare_real_database show-refs-empty-human exact show "$real_database_bug_id" --refs
compare_real_database show-refs-empty-json exact show "$real_database_bug_id" --refs --json
compare_real_database show-refs-multiple show-grouped-multi show "$real_database_epic_id" "$real_database_bug_id" --refs
compare_real_database show-refs-disabled exact show "$real_database_bug_id" --refs=false
compare_real_database_env show-refs-json-envelope exact BD_JSON_ENVELOPE=1 show "$real_database_epic_id" --refs --json
compare_real_database show-json-comments exact show "$real_database_issue_id" --json --include-comments
compare_real_database show-json-comments-attached exact show "$real_database_issue_id" --json --include-comments=true
compare_real_database show-json-comments-disabled exact show "$real_database_issue_id" --json --include-comments=false
compare_real_database show-json-dependents exact show "$real_database_epic_id" --json --include-dependents
compare_real_database show-json-brief-deps exact show "$real_database_child_id" --json --brief-deps

wait_for_watch_text() {
	local file="$1"
	local value="$2"
	for _ in {1..200}; do
		if grep -Fq "$value" "$file"; then
			return 0
		fi
		sleep 0.05
	done
	printf 'watch output did not contain %q\n' "$value" >&2
	return 1
}

watch_case_count=0

normalize_watch_stderr() {
	# Poll cadence is not observable command policy. A context cancellation can
	# race with the final interrupt and is shutdown noise, not a failed refresh.
	# Keep every other refresh failure, collapsing only immediate repeats.
	awk '
		$0 ~ /^Error refreshing issues: .*context canceled$/ { next }
		$0 ~ /^Error refreshing issues:/ && $0 == previous { next }
		{ print; previous = $0 }
	' "$1"
}

compare_watch_refresh() {
	local name="$1"
	local mutation="$2"
	shift 2
	watch_case_count=$((watch_case_count + 1))
	local case_root="$test_root/real-database-$name-watch-refresh"
	local oracle_exit=0
	local candidate_exit=0
	local side state_root binary watch_pid watch_exit before initial_after updated_before_stop after_stop
	local command=("$@")
	mkdir -p "$case_root"
	for side in oracle candidate; do
		state_root="$case_root/$side-state"
		mkdir -p "$state_root/user-home/.dolt" "$state_root/config"
		printf '{}\n' >"$state_root/user-home/.dolt/config_global.json"
		copy_fixture_tree "$real_database_seed/work" "$state_root/work"
		chmod 700 "$state_root/work/.beads"
		binary="$oracle"
		if [[ "$side" == candidate ]]; then
			binary="$candidate"
		fi
		wait_for_stable_tree "$state_root" >/dev/null
		before="$(fingerprint_task_state_tree "$state_root")"
		(
			cd "$state_root/work"
			exec env HOME="$state_root/user-home" \
				XDG_CONFIG_HOME="$state_root/config" \
				"${real_database_env[@]}" \
				"$binary" "${command[@]}"
		) >"$case_root/$side.stdout" 2>"$case_root/$side.stderr" &
		watch_pid=$!
		printf '%s\n' "$watch_pid" >"$case_root/$side.watch.pid"
		wait_for_watch_text "$case_root/$side.stderr" 'Watching for changes'
		initial_after="$(fingerprint_task_state_tree "$state_root")"
		if [[ "$side" == candidate && "$before" != "$initial_after" ]]; then
			printf '%s-watch candidate changed state during initial display\n' "$name" >&2
			return 1
		fi
		case "$mutation" in
		update)
			(
				cd "$state_root/work"
				env HOME="$state_root/user-home" \
					XDG_CONFIG_HOME="$state_root/config" \
					"${real_database_env[@]}" \
					"$oracle" update "$real_database_content_id" \
					--title 'Updated watch parity issue' --json >/dev/null
			)
			wait_for_watch_text "$case_root/$side.stdout" 'Updated watch parity issue'
			;;
		row-cap)
			(
				cd "$state_root/work"
				cap_id="$(env HOME="$state_root/user-home" \
					XDG_CONFIG_HOME="$state_root/config" \
					"${real_database_env[@]}" \
					"$oracle" create 'Second alpha watch issue' --json | jq -er '.id')"
				env HOME="$state_root/user-home" \
					XDG_CONFIG_HOME="$state_root/config" \
					"${real_database_env[@]}" \
					"$oracle" label add "$cap_id" alpha --json >/dev/null
			)
			wait_for_watch_text "$case_root/$side.stderr" 'Error refreshing issues: search returned 2 rows, exceeding --max-rows cap of 1'
			;;
		*)
			printf 'unknown watch mutation: %s\n' "$mutation" >&2
			return 2
			;;
		esac
		updated_before_stop="$(fingerprint_task_state_tree "$state_root")"
		kill -INT "$watch_pid"
		set +e
		wait "$watch_pid"
		watch_exit=$?
		if [[ "$side" == oracle ]]; then
			oracle_exit="$watch_exit"
		else
			candidate_exit="$watch_exit"
		fi
		set -e
		rm "$case_root/$side.watch.pid"
		wait_for_stable_tree "$state_root" >/dev/null
		after_stop="$(fingerprint_task_state_tree "$state_root")"
		if [[ "$side" == candidate && "$updated_before_stop" != "$after_stop" ]]; then
			printf '%s-watch candidate changed state while stopping\n' "$name" >&2
			return 1
		fi
	done
	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s-watch exit mismatch: upstream=%s candidate=%s\n' "$name" "$oracle_exit" "$candidate_exit" >&2
		return 1
	fi
	if [[ "$name" == list* ]]; then
		for implementation in oracle candidate; do
			sed -E 's/Beads - Open & In Progress \([0-9]{2}:[0-9]{2}:[0-9]{2}\)/Beads - Open \& In Progress (<time>)/' \
				"$case_root/$implementation.stdout" >"$case_root/$implementation.normalized"
		done
	else
		cp -f "$case_root/oracle.stdout" "$case_root/oracle.normalized"
		cp -f "$case_root/candidate.stdout" "$case_root/candidate.normalized"
	fi
	if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
		printf '%s-watch stdout differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
		return 1
	fi
	for implementation in oracle candidate; do
		normalize_watch_stderr "$case_root/$implementation.stderr" \
			>"$case_root/$implementation.stderr.normalized"
	done
	if ! cmp -s "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized"; then
		printf '%s-watch stderr differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized" >&2 || true
		return 1
	fi
}

compare_watch_refresh show update show "$real_database_content_id" --watch
compare_watch_refresh list update list --watch --limit 0
compare_watch_refresh list-cap row-cap list --watch --label alpha --limit 0 --max-rows 1

json_deprecation='NOTE: bd --json output format will change in v2.0. Set BD_JSON_ENVELOPE=1 to opt in early. See docs/reference/json-schema.md for migration details.'

run_json_stderr_terminal() {
	local name="$1"
	local binary="$2"
	local envelope="$3"
	local output="$test_root/$name.terminal"
	local stdout="$test_root/$name.stdout"
	local command_root="$test_root/$name-root"
	local invocation

	mkdir -p "$command_root/home" "$command_root/config" "$command_root/work"
	case "$(uname -s)" in
	Darwin)
		(
			cd "$command_root/work"
			env HOME="$command_root/home" \
				XDG_CONFIG_HOME="$command_root/config" \
				BD_DISABLE_METRICS=1 \
				BD_DISABLE_EVENT_FLUSH=1 \
				BD_JSON_ENVELOPE="$envelope" \
				NO_COLOR=1 \
				script -q /dev/null /bin/sh -c \
				'exec "$1" version --json >"$2"' _ "$binary" "$stdout" </dev/null
		) >"$output" 2>&1
		;;
	Linux)
		printf -v invocation '%q version --json >%q' "$binary" "$stdout"
		(
			cd "$command_root/work"
			env HOME="$command_root/home" \
				XDG_CONFIG_HOME="$command_root/config" \
				BD_DISABLE_METRICS=1 \
				BD_DISABLE_EVENT_FLUSH=1 \
				BD_JSON_ENVELOPE="$envelope" \
				NO_COLOR=1 \
				script -qec "$invocation" /dev/null </dev/null
		) >"$output" 2>&1
		;;
	*)
		printf 'unsupported pseudo-terminal host: %s\n' "$(uname -s)" >&2
		return 1
		;;
	esac

	if [[ -n "$(find "$command_root" -mindepth 2 -print -quit)" ]]; then
		printf '%s terminal command persisted files in an empty workspace\n' "$name" >&2
		return 1
	fi
	if [[ ! -s "$stdout" ]]; then
		printf '%s terminal command did not write JSON to its stdout pipe\n' "$name" >&2
		return 1
	fi
}

for implementation in oracle candidate; do
	case "$implementation" in
		oracle) binary="$oracle" ;;
		candidate) binary="$candidate" ;;
	esac
	run_json_stderr_terminal "$implementation-json-legacy" "$binary" 0
	jq -e '.schema_version == 1' \
		"$test_root/$implementation-json-legacy.stdout" >/dev/null
	note_count="$(tr -d '\r' <"$test_root/$implementation-json-legacy.terminal" | \
		grep -Foc "$json_deprecation" || true)"
	if [[ "$note_count" -ne 1 ]]; then
		printf '%s emitted %s JSON terminal notices, want 1\n' \
			"$implementation" "$note_count" >&2
		exit 1
	fi

	run_json_stderr_terminal "$implementation-json-envelope" "$binary" 1
	if tr -d '\r' <"$test_root/$implementation-json-envelope.terminal" | \
		grep -Fq "$json_deprecation"; then
		printf '%s emitted the legacy JSON notice with BD_JSON_ENVELOPE=1\n' \
			"$implementation" >&2
		exit 1
	fi
done

printf 'oracle: %s\n' "$oracle_identity"
printf 'candidate: %s\n' "$candidate_identity"
printf 'parity identity smoke: PASS\n'
printf 'no-workspace differential: PASS (42 command forms)\n'
printf 'store-failure differentials: PASS (7 cases)\n'
printf 'real-database differentials: PASS (%s cases; ping timings normalized)\n' "$real_database_case_count"
printf 'watch differentials: PASS (%s cases; poll change, refresh error, and signal lifecycle)\n' "$watch_case_count"
printf 'JSON terminal notice differential: PASS\n'
