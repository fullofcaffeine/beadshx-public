#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
oracle="${1:-$repository_root/build/bin/bd-upstream}"
candidate="${2:-$repository_root/build/bin/bdhx}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-parity-smoke.XXXXXX")"
# Writes rows that bd refuses to create (such as dependency cycles) into marked fixtures.
fixture_sql="$test_root/bin/fixture-sql"
(cd "$repository_root" && go build -tags gms_pure_go -o "$fixture_sql" ./scripts/beadshx/fixture-sql)
cleanup() {
	local status=$?
	while IFS= read -r pid_file; do
		watch_pid="$(cat "$pid_file")"
		kill -TERM "$watch_pid" 2>/dev/null || true
	done < <(find "$test_root" -name '*.watch.pid' -type f)
	if [[ "$status" -ne 0 ]]; then
		printf 'parity failed (exit %s); disposable evidence retained: %s\n' "$status" "$test_root" >&2
		return "$status"
	fi
	find "$test_root" -mindepth 1 -delete
	rmdir "$test_root"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

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

no_workspace_case_count=0
# One more variable assignment for both sides of a no-workspace case.
no_workspace_extra_env=(BEADSHX_PARITY_EXTRA=1)
# When set, each side gets this user config.yaml under its HOME, which the run must leave unchanged.
no_workspace_user_config=""
# Names a function that prepares each side root (its argument) of a no-workspace case; the run must
# then leave that root unchanged instead of empty. Cases that use it come after fingerprint_tree.
no_workspace_setup=""

# Writes the case's user config.yaml under each HOME directory given.
write_no_workspace_user_config() {
	local user_home
	for user_home in "$@"; do
		mkdir -p "$user_home/.config/bd"
		printf '%s\n' "$no_workspace_user_config" >"$user_home/.config/bd/config.yaml"
	done
}

# Requires each HOME's user config.yaml to be unchanged, then removes it for the empty-workspace check.
remove_no_workspace_user_config() {
	local name="$1" user_home
	shift
	for user_home in "$@"; do
		if [[ "$(cat "$user_home/.config/bd/config.yaml")" != "$no_workspace_user_config" ]]; then
			printf '%s command changed its user config.yaml\n' "$name" >&2
			return 1
		fi
		rm -rf "$user_home/.config"
	done
}

compare_no_workspace() {
	local name="$1"
	no_workspace_case_count=$((no_workspace_case_count + 1))
	printf 'parity [%ss]: START no-workspace/%s\n' "$SECONDS" "$name"
	shift
	local case_root="$test_root/$name"
	local oracle_root="$case_root/oracle"
	local candidate_root="$case_root/candidate"
	local oracle_exit
	local candidate_exit

	mkdir -p "$oracle_root/home" "$oracle_root/config" "$oracle_root/work"
	mkdir -p "$candidate_root/home" "$candidate_root/config" "$candidate_root/work"
	if [[ -n "$no_workspace_user_config" ]]; then
		write_no_workspace_user_config "$oracle_root/home" "$candidate_root/home"
	fi
	local oracle_before="" candidate_before=""
	if [[ -n "$no_workspace_setup" ]]; then
		"$no_workspace_setup" "$oracle_root"
		"$no_workspace_setup" "$candidate_root"
		oracle_before="$(fingerprint_tree "$oracle_root")"
		candidate_before="$(fingerprint_tree "$candidate_root")"
	fi

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
			"${no_workspace_extra_env[@]}" \
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
			"${no_workspace_extra_env[@]}" \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	set -e
	if [[ -n "$no_workspace_user_config" ]]; then
		remove_no_workspace_user_config "$name" "$oracle_root/home" "$candidate_root/home"
	fi

	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s exit mismatch: upstream=%s candidate=%s\n' \
			"$name" "$oracle_exit" "$candidate_exit" >&2
		printf '%s upstream stdout:\n' "$name" >&2
		cat "$case_root/oracle.stdout" >&2
		printf '%s upstream stderr:\n' "$name" >&2
		cat "$case_root/oracle.stderr" >&2
		printf '%s candidate stdout:\n' "$name" >&2
		cat "$case_root/candidate.stdout" >&2
		printf '%s candidate stderr:\n' "$name" >&2
		cat "$case_root/candidate.stderr" >&2
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
	if [[ -n "$no_workspace_setup" ]]; then
		if [[ "$oracle_before" != "$(fingerprint_tree "$oracle_root")" ]]; then
			printf '%s upstream command changed its prepared files\n' "$name" >&2
			return 1
		fi
		if [[ "$candidate_before" != "$(fingerprint_tree "$candidate_root")" ]]; then
			printf '%s candidate command changed its prepared files\n' "$name" >&2
			return 1
		fi
	elif [[ -n "$(find "$oracle_root" -mindepth 2 -print -quit)" ]]; then
		printf '%s upstream command persisted files in an empty workspace\n' "$name" >&2
		return 1
	elif [[ -n "$(find "$candidate_root" -mindepth 2 -print -quit)" ]]; then
		printf '%s candidate command persisted files in an empty workspace\n' "$name" >&2
		return 1
	fi
	printf 'parity [%ss]: PASS no-workspace/%s\n' "$SECONDS" "$name"
}

compare_no_workspace_env() {
	local name="$1"
	local environment="$2"
	shift 2
	no_workspace_extra_env=("$environment")
	compare_no_workspace "$name" "$@"
	no_workspace_extra_env=(BEADSHX_PARITY_EXTRA=1)
}

compare_no_workspace_user_config() {
	local name="$1"
	local config="$2"
	shift 2
	no_workspace_user_config="$config"
	compare_no_workspace "$name" "$@"
	no_workspace_user_config=""
}

# `version` prints each binary's own identity, so these no-workspace cases compare only the output
# mode: both sides print a JSON object with schema_version 1 (json), or one line that is not JSON
# (text), with exit 0, an empty stderr and no file written. They take the same extra environment and
# user config.yaml as compare_no_workspace.
compare_version_mode() {
	local name="$1"
	local mode="$2"
	shift 2
	no_workspace_case_count=$((no_workspace_case_count + 1))
	printf 'parity [%ss]: START no-workspace/%s\n' "$SECONDS" "$name"
	local case_root="$test_root/$name"
	local side side_root binary side_exit
	for side in oracle candidate; do
		side_root="$case_root/$side"
		binary="$oracle"
		[[ "$side" == candidate ]] && binary="$candidate"
		mkdir -p "$side_root/home" "$side_root/config" "$side_root/work"
		if [[ -n "$no_workspace_user_config" ]]; then
			write_no_workspace_user_config "$side_root/home"
		fi
		set +e
		(
			cd "$side_root/work"
			env HOME="$side_root/home" \
				XDG_CONFIG_HOME="$side_root/config" \
				BD_DISABLE_METRICS=1 \
				BD_DISABLE_EVENT_FLUSH=1 \
				BD_JSON_ENVELOPE=0 \
				NO_COLOR=1 \
				"${no_workspace_extra_env[@]}" \
				"$binary" "$@"
		) >"$case_root/$side.stdout" 2>"$case_root/$side.stderr"
		side_exit=$?
		set -e
		if [[ -n "$no_workspace_user_config" ]]; then
			remove_no_workspace_user_config "$name" "$side_root/home"
		fi
		if [[ "$side_exit" -ne 0 || -s "$case_root/$side.stderr" ]]; then
			printf '%s %s exited %s with stderr:\n' "$name" "$side" "$side_exit" >&2
			cat "$case_root/$side.stderr" >&2
			return 1
		fi
		case "$mode" in
		json)
			if ! jq -e '.schema_version == 1' "$case_root/$side.stdout" >/dev/null 2>&1; then
				printf '%s %s did not print a JSON version document:\n' "$name" "$side" >&2
				cat "$case_root/$side.stdout" >&2
				return 1
			fi
			;;
		text)
			if [[ "$(wc -l <"$case_root/$side.stdout" | tr -d ' ')" != 1 ]] ||
				jq -e . "$case_root/$side.stdout" >/dev/null 2>&1; then
				printf '%s %s did not print one text version line:\n' "$name" "$side" >&2
				cat "$case_root/$side.stdout" >&2
				return 1
			fi
			;;
		*)
			printf 'unknown version mode: %s\n' "$mode" >&2
			return 2
			;;
		esac
		if [[ -n "$(find "$side_root" -mindepth 2 -print -quit)" ]]; then
			printf '%s %s command persisted files in an empty workspace\n' "$name" "$side" >&2
			return 1
		fi
	done
	printf 'parity [%ss]: PASS no-workspace/%s\n' "$SECONDS" "$name"
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
compare_no_workspace types types
compare_no_workspace types_sections_json types --sections --json
compare_no_workspace types_bad_sections types --sections=bogus
compare_no_workspace statuses_json statuses --json
compare_no_workspace statuses_sections statuses --sections
compare_no_workspace config_get_yaml config get export.auto
compare_no_workspace config_get_yaml_json config get dolt.auto-commit --json
compare_no_workspace config_get_database config get issue_prefix
compare_no_workspace config_list config list
compare_no_workspace config_help config --help
compare_no_workspace config_show config show
compare_no_workspace config_show_json config show --json
compare_no_workspace config_show_source_metadata config show --source metadata
compare_no_workspace config_show_help config show --help
compare_no_workspace config_validate config validate
compare_no_workspace config_validate_json config validate --json
compare_no_workspace config_validate_help config validate --help
compare_no_workspace config_drift config drift
compare_no_workspace config_drift_json config drift --json
compare_no_workspace config_drift_help config drift --help
BEADSHX_TEST_JSON_ENVELOPE=1 compare_no_workspace where_json_envelope where --json

fingerprint_tree() {
	local root="$1"
	(
		cd "$root"
		find . -mindepth 1 -print | LC_ALL=C sort
		# Batch file arguments while preserving the same sorted per-file digests.
		find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort
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
			! -path '*/.beads.gate.lock' \
			! -path '*/.beads/dolt.gate.lock' \
			! -path '*/.beads/.local_version' \
			! -name 'nbs_manifest_*' -print | LC_ALL=C sort
		find . -type f \
			! -path '*/.dolt/noms/journal.idx' \
			! -path '*/.beads.gate.lock' \
			! -path '*/.beads/dolt.gate.lock' \
			! -path '*/.beads/.local_version' \
			! -name 'nbs_manifest_*' \
			-exec shasum -a 256 {} + | LC_ALL=C sort
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

store_failure_case_count=0
compare_store_failure() {
	local scenario="$1"
	local case_name="$2"
	store_failure_case_count=$((store_failure_case_count + 1))
	printf 'parity [%ss]: START store-failure/%s/%s\n' "$SECONDS" "$scenario" "$case_name"
	shift 2
	local case_root="$test_root/$scenario-$case_name"
	local oracle_root="$case_root/oracle"
	local candidate_root="$case_root/candidate"
	local oracle_before oracle_after candidate_before candidate_after
	local oracle_exit candidate_exit
	local metadata config_yaml
	local oracle_tmpdir="${TMPDIR:-/tmp}"
	local candidate_tmpdir="${TMPDIR:-/tmp}"
	case "$scenario" in
	missing-embedded)
		metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"beads"}'
		config_yaml='issue-prefix: test'
		;;
	unavailable-server | deprecated-port-server)
		metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads"}'
		# metadata.json also names the server port, which upstream warns is deprecated.
		if [[ "$scenario" == deprecated-port-server ]]; then
			metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads","dolt_server_port":1}'
		fi
		config_yaml=$'issue-prefix: test\ndolt:\n  mode: server\n  auto-start: false'
		# Upstream counts each failed server connection in a circuit breaker file under
		# $TMPDIR/beads-circuit, which every process on the machine shares. Five failures in a
		# minute trip it: that process logs a "[circuit-breaker] ... closed → open" line, and later
		# opens fail fast with another error. A fresh TMPDIR outside the fingerprinted fixture
		# keeps each command independent of the other cases and of parity runs in other checkouts.
		oracle_tmpdir="$case_root/oracle-tmp"
		candidate_tmpdir="$case_root/candidate-tmp"
		mkdir -p "$oracle_tmpdir" "$candidate_tmpdir"
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
	oracle_before="$(fingerprint_task_state_tree "$oracle_root")"
	candidate_before="$(fingerprint_task_state_tree "$candidate_root")"

	set +e
	(
		cd "$oracle_root/work"
		env HOME="$oracle_root/home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			TMPDIR="$oracle_tmpdir" \
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
			TMPDIR="$candidate_tmpdir" \
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

	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s/%s exit mismatch: upstream=%s candidate=%s\n' \
			"$scenario" "$case_name" "$oracle_exit" "$candidate_exit" >&2
		return 1
	fi
	if ! cmp -s "$case_root/oracle.stdout" "$case_root/candidate.stdout"; then
		printf '%s/%s stdout differs from upstream\n' "$scenario" "$case_name" >&2
		diff -u "$case_root/oracle.stdout" "$case_root/candidate.stdout" >&2 || true
		return 1
	fi
	if ! cmp -s "$case_root/oracle.stderr" "$case_root/candidate.stderr"; then
		printf '%s/%s stderr differs from upstream\n' "$scenario" "$case_name" >&2
		diff -u "$case_root/oracle.stderr" "$case_root/candidate.stderr" >&2 || true
		return 1
	fi
	oracle_after="$(fingerprint_task_state_tree "$oracle_root")"
	candidate_after="$(fingerprint_task_state_tree "$candidate_root")"
	if [[ "$oracle_before" != "$oracle_after" ]]; then
		printf '%s/%s upstream command changed its fixture\n' "$scenario" "$case_name" >&2
		find "$oracle_root" -mindepth 1 -print | LC_ALL=C sort >&2
		find "$oracle_root" -type f -exec shasum -a 256 {} + | LC_ALL=C sort >&2
		return 1
	fi
	if [[ "$candidate_before" != "$candidate_after" ]]; then
		printf '%s/%s candidate command changed its fixture\n' "$scenario" "$case_name" >&2
		find "$candidate_root" -mindepth 1 -print | LC_ALL=C sort >&2
		find "$candidate_root" -type f -exec shasum -a 256 {} + | LC_ALL=C sort >&2
		return 1
	fi
	printf 'parity [%ss]: PASS store-failure/%s/%s\n' "$SECONDS" "$scenario" "$case_name"
}

for command in info ping status; do
	compare_store_failure missing-embedded "$command" "$command"
done
compare_store_failure missing-embedded info-whats-new info --whats-new
compare_store_failure missing-embedded info-whats-new-json info --whats-new --json
compare_store_failure missing-embedded info-whats-new-global info --whats-new --global
compare_store_failure unavailable-server info info
# Upstream opens the store in its root pre-run, before any command body runs. A closed server
# fails there with plain "Error: failed to open database: ...", without the command's context
# (such as "resolving <id>:") and without a JSON object under --json.
compare_store_failure unavailable-server info-json info --json
compare_store_failure unavailable-server ping ping
compare_store_failure unavailable-server ping-json ping --json
compare_store_failure unavailable-server status status
compare_store_failure unavailable-server status-json status --json
compare_store_failure unavailable-server list list
compare_store_failure unavailable-server list-json list --json
compare_store_failure unavailable-server show show test-1
compare_store_failure unavailable-server show-json show test-1 --json
compare_store_failure unavailable-server children children test-1
compare_store_failure unavailable-server children-json children test-1 --json
compare_store_failure unavailable-server search search parity
compare_store_failure unavailable-server search-json search parity --json
compare_store_failure unavailable-server query query status=open
compare_store_failure unavailable-server query-json query status=open --json
compare_store_failure unavailable-server count count
compare_store_failure unavailable-server count-json count --json
compare_store_failure unavailable-server ready ready
compare_store_failure unavailable-server ready-json ready --json
compare_store_failure unavailable-server stale stale
compare_store_failure unavailable-server stale-json stale --json
compare_store_failure unavailable-server orphans orphans
compare_store_failure unavailable-server orphans-json orphans --json
compare_store_failure unavailable-server comments comments test-1
compare_store_failure unavailable-server comments-json comments test-1 --json
compare_store_failure unavailable-server label-list label list test-1
compare_store_failure unavailable-server label-list-json label list test-1 --json
compare_store_failure unavailable-server label-list-all label list-all
compare_store_failure unavailable-server label-list-all-json label list-all --json
compare_store_failure unavailable-server history history test-1
compare_store_failure unavailable-server history-json history test-1 --json
compare_store_failure unavailable-server history-events-json history test-1 --events --json
compare_store_failure unavailable-server dep-list dep list test-1
compare_store_failure unavailable-server dep-list-json dep list test-1 --json
compare_store_failure unavailable-server dep-tree dep tree test-1
compare_store_failure unavailable-server dep-tree-json dep tree test-1 --json
# The command's own flag checks run after the store opens.
compare_store_failure unavailable-server dep-tree-bad-direction-json dep tree test-1 --direction sideways --json
compare_store_failure unavailable-server dep-cycles dep cycles
compare_store_failure unavailable-server dep-cycles-json dep cycles --json
compare_store_failure unavailable-server blocked blocked
compare_store_failure unavailable-server blocked-json blocked --json
compare_store_failure unavailable-server graph-check graph check
compare_store_failure unavailable-server graph-check-json graph check --json
compare_store_failure unavailable-server graph graph test-1
compare_store_failure unavailable-server graph-json graph test-1 --json
compare_store_failure unavailable-server graph-all graph --all
compare_store_failure unavailable-server graph-all-json graph --all --json
compare_store_failure unavailable-server types types
compare_store_failure unavailable-server types-json types --json
compare_store_failure unavailable-server types-sections types --sections
compare_store_failure unavailable-server statuses statuses
compare_store_failure unavailable-server statuses-json statuses --json
compare_store_failure unavailable-server events-tail events tail
compare_store_failure unavailable-server events-tail-json events tail --json
compare_store_failure unavailable-server events-export events export
compare_store_failure unavailable-server events-export-json events export --json
# These argument checks run in upstream's command body, after the pre-run store open.
compare_store_failure unavailable-server stale-zero-days stale --days 0
compare_store_failure unavailable-server stale-zero-days-json stale --days 0 --json
compare_store_failure unavailable-server stale-bad-status stale --status bogus
compare_store_failure unavailable-server stale-bad-status-json stale --status bogus --json
compare_store_failure unavailable-server search-no-query search
compare_store_failure unavailable-server search-no-query-json search --json
compare_store_failure unavailable-server query-no-expression query
compare_store_failure unavailable-server query-no-expression-json query --json
compare_store_failure unavailable-server query-parse-only query status=open --parse-only
compare_store_failure unavailable-server query-parse-only-json query status=open --parse-only --json
compare_store_failure unavailable-server query-offset query status=open --offset 1
compare_store_failure unavailable-server query-offset-json query status=open --offset 1 --json
compare_store_failure unavailable-server list-offset list --offset 1
compare_store_failure unavailable-server list-offset-json list --offset 1 --json
compare_store_failure unavailable-server ready-offset ready --offset 1
compare_store_failure unavailable-server ready-offset-json ready --offset 1 --json
compare_store_failure missing-embedded list-offset list --offset 1
compare_store_failure missing-embedded list-offset-json list --offset 1 --json
compare_store_failure missing-embedded ready-offset ready --offset 1
compare_store_failure missing-embedded ready-offset-json ready --offset 1 --json
compare_store_failure missing-embedded types types
compare_store_failure missing-embedded statuses statuses
compare_store_failure unavailable-server config-show config show
compare_store_failure unavailable-server config-show-json config show --json
compare_store_failure unavailable-server config-validate config validate
compare_store_failure unavailable-server config-validate-json config validate --json
compare_store_failure unavailable-server config-drift config drift
compare_store_failure unavailable-server config-drift-json config drift --json
# Without a database upstream opens no store: validate runs its checks and leaves the fixture as it was.
compare_store_failure missing-embedded config-validate config validate
compare_store_failure missing-embedded config-validate-json config validate --json
# A server workspace whose metadata.json names the port: upstream prints its deprecation warning once,
# before the open error.
compare_store_failure deprecated-port-server count count
compare_store_failure deprecated-port-server list-json list --json
compare_store_failure deprecated-port-server dep-tree dep tree test-1
compare_store_failure deprecated-port-server config-get config get issue_prefix
compare_store_failure deprecated-port-server types types

real_database_seed="$test_root/real-database-seed"
printf 'parity [%ss]: START database fixture setup\n' "$SECONDS"
mkdir -p "$real_database_seed/home" "$real_database_seed/config" "$real_database_seed/work"
touch "$real_database_seed/work/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$real_database_seed/work" >/dev/null
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
	# Upstream JSON escapes <, > and & as <, > and &; human output does not.
	"${seed_command[@]}" create "Escaping parity <b> & co" --priority 2 \
		--description "Compare a < b > c & d" --design "Keep <tags> & entities" \
		--notes "Notes <i> & more" --acceptance "Prints <, > and & alike" --json \
		>"$real_database_seed/escaping.json"
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
	"${seed_command[@]}" create "Labeled relation source" --priority 3 --json >"$real_database_seed/labeled-relation.json"
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
	# Related issues in show --json carry their own labels.
	"${seed_command[@]}" label add "$(jq -er '.id' "$real_database_seed/labeled-relation.json")" linked --json >/dev/null
	"${seed_command[@]}" dep add "$(jq -er '.id' "$real_database_seed/labeled-relation.json")" "$open_id" \
		--type relates-to >/dev/null
	"${seed_command[@]}" label add "$(jq -er '.id' "$real_database_seed/content.json")" alpha,beta --json >/dev/null
	"${seed_command[@]}" label add "$(jq -er '.id' "$real_database_seed/escaping.json")" 'r&d,<ui>' --json >/dev/null
	"${seed_command[@]}" comments add "$open_id" "Parity comment" --json >/dev/null
	closed_id="$(jq -er '.id' "$real_database_seed/closed.json")"
	"${seed_command[@]}" close "$closed_id" --reason done --json >/dev/null
	git commit -q --allow-empty -m "baseline"
	git commit -q --allow-empty -m "feat: implement ($open_id)"
)
real_database_issue_id="$(jq -er '.id' "$real_database_seed/issue.json")"
real_database_bug_id="$(jq -er '.id' "$real_database_seed/bug.json")"
real_database_content_id="$(jq -er '.id' "$real_database_seed/content.json")"
real_database_escaping_id="$(jq -er '.id' "$real_database_seed/escaping.json")"
real_database_epic_id="$(jq -er '.id' "$real_database_seed/epic.json")"
real_database_molecule_id="$(jq -er '.id' "$real_database_seed/molecule.json")"
real_database_gated_molecule_id="$(jq -er '.id' "$real_database_seed/gated-molecule.json")"
real_database_gated_step_id="$(jq -er '.id' "$real_database_seed/gated-step.json")"
real_database_child_id="$(jq -er '.id' "$real_database_seed/child.json")"
real_database_progress_id="$(jq -er '.id' "$real_database_seed/progress.json")"
real_database_closed_id="$(jq -er '.id' "$real_database_seed/closed.json")"
real_database_labeled_relation_id="$(jq -er '.id' "$real_database_seed/labeled-relation.json")"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config=""
real_database_extra_local_config=""
real_database_extra_metadata=""
real_database_extra_import=""
real_database_extra_sql=""
# Names a function that prepares each state root (its argument) of a database case before the run.
real_database_setup=""
# When set, a database case also requires the upstream command to leave its task state unchanged,
# and gives each side an empty TMPDIR that must stay empty.
real_database_read_only=""
real_database_case_count=0
candidate_only_case_count=0
# Names a function that prepares one candidate-only state root (its argument) before the run.
candidate_only_setup=""
printf 'parity [%ss]: PASS database fixture setup\n' "$SECONDS"

compare_real_database() {
	local name="$1"
	printf 'parity [%ss]: START database/%s\n' "$SECONDS" "$name"
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
		if [[ -n "$real_database_extra_local_config" ]]; then
			printf '%s\n' "$real_database_extra_local_config" >"$state_root/work/.beads/config.local.yaml"
		fi
		if [[ -n "$real_database_extra_metadata" ]]; then
			# Rewrite metadata.json in place, so the file keeps its mode.
			jq "$real_database_extra_metadata" "$state_root/work/.beads/metadata.json" >"$state_root/metadata.json"
			cat "$state_root/metadata.json" >"$state_root/work/.beads/metadata.json"
			rm -f "$state_root/metadata.json"
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
		if [[ -n "$real_database_extra_sql" ]]; then
			printf '%s\n' "$real_database_extra_sql" | "$fixture_sql" "$state_root/work" >/dev/null
		fi
		if [[ -n "$real_database_setup" ]]; then
			"$real_database_setup" "$state_root"
		fi
	done
	candidate_before="$(fingerprint_tree "$candidate_root")"
	local oracle_before="" oracle_temporary=(BEADSHX_PARITY_TMP=inherited) candidate_temporary=(BEADSHX_PARITY_TMP=inherited)
	if [[ -n "$real_database_read_only" ]]; then
		oracle_before="$(fingerprint_task_state_tree "$oracle_root")"
		mkdir -p "$case_root/oracle-tmp" "$case_root/candidate-tmp"
		oracle_temporary=(TMPDIR="$case_root/oracle-tmp")
		candidate_temporary=(TMPDIR="$case_root/candidate-tmp")
	fi

	local oracle_work candidate_work oracle_work_logical candidate_work_logical
	oracle_work="$(cd "$oracle_root/work" && pwd -P)"
	candidate_work="$(cd "$candidate_root/work" && pwd -P)"
	# Go's Getwd keeps the logical path that the run starts in, which filepath.Abs extends.
	oracle_work_logical="$(cd "$oracle_root/work" && pwd -L)"
	candidate_work_logical="$(cd "$candidate_root/work" && pwd -L)"
	# An extra variable names each side's own work directory as <work>.
	local oracle_extra_env=("${real_database_extra_env[@]//<work>/$oracle_work}")
	local candidate_extra_env=("${real_database_extra_env[@]//<work>/$candidate_work}")

	set +e
	(
		cd "$oracle_root/work"
		env HOME="$oracle_root/user-home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			"${oracle_temporary[@]}" \
			"${real_database_env[@]}" \
			"${oracle_extra_env[@]}" \
			"$oracle" "$@"
	) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr"
	oracle_exit=$?
	(
		cd "$candidate_root/work"
		env HOME="$candidate_root/user-home" \
			XDG_CONFIG_HOME="$candidate_root/config" \
			"${candidate_temporary[@]}" \
			"${real_database_env[@]}" \
			"${candidate_extra_env[@]}" \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	candidate_after="$(fingerprint_tree "$candidate_root")"
	set -e
	if [[ -n "$real_database_read_only" ]]; then
		if [[ "$oracle_before" != "$(fingerprint_task_state_tree "$oracle_root")" ]]; then
			printf '%s upstream command changed its fixture\n' "$name" >&2
			return 1
		fi
		for side in oracle candidate; do
			if [[ -n "$(find "$case_root/$side-tmp" -mindepth 1 -print -quit)" ]]; then
				printf '%s %s command wrote temporary files\n' "$name" "$side" >&2
				find "$case_root/$side-tmp" -mindepth 1 -print >&2
				return 1
			fi
		done
	fi

	if [[ "$oracle_exit" -ne "$candidate_exit" ]]; then
		printf '%s exit mismatch: upstream=%s candidate=%s\n' \
			"$name" "$oracle_exit" "$candidate_exit" >&2
		printf '%s upstream stdout:\n' "$name" >&2
		cat "$case_root/oracle.stdout" >&2
		printf '%s upstream stderr:\n' "$name" >&2
		cat "$case_root/oracle.stderr" >&2
		printf '%s candidate stdout:\n' "$name" >&2
		cat "$case_root/candidate.stdout" >&2
		printf '%s candidate stderr:\n' "$name" >&2
		cat "$case_root/candidate.stderr" >&2
		return 1
	fi
	# A metadata.json load warning names each side's own workspace.
	sed -e "s|$oracle_work|<work>|g" -e "s|$oracle_work_logical|<work>|g" \
		"$case_root/oracle.stderr" >"$case_root/oracle.stderr.normalized"
	sed -e "s|$candidate_work|<work>|g" -e "s|$candidate_work_logical|<work>|g" \
		"$case_root/candidate.stderr" >"$case_root/candidate.stderr.normalized"
	if ! cmp -s "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized"; then
		printf '%s stderr differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized" >&2 || true
		return 1
	fi
	if [[ "$candidate_before" != "$candidate_after" ]]; then
		printf '%s candidate command changed the read-only fixture\n' "$name" >&2
		return 1
	fi
	case "$comparison" in
	exact | exact-home)
		sed -e "s|$oracle_work|<work>|g" -e "s|$oracle_work_logical|<work>|g" \
			"$case_root/oracle.stdout" >"$case_root/oracle.normalized"
		sed -e "s|$candidate_work|<work>|g" -e "s|$candidate_work_logical|<work>|g" \
			"$case_root/candidate.stdout" >"$case_root/candidate.normalized"
		if [[ "$comparison" == exact-home ]]; then
			# The user config.yaml path names each side's own HOME, which Go prints cleaned.
			local oracle_home candidate_home
			oracle_home="$(cd "$oracle_root/user-home" && pwd -L)"
			candidate_home="$(cd "$candidate_root/user-home" && pwd -L)"
			sed -i.bak "s|$oracle_home|<home>|g" "$case_root/oracle.normalized"
			sed -i.bak "s|$candidate_home|<home>|g" "$case_root/candidate.normalized"
		fi
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
	config-validate-routing)
		# Upstream lists the valid routing modes from a Go map, in random order; compare them as a set.
		for side in oracle candidate; do
			jq -Rr 'if test("routing\\.mode: .* is invalid \\(valid values: [a-z, ]*\\)") then
				sub("\\(valid values: (?<modes>[a-z, ]*)\\)"; "(valid values: \(.modes | split(", ") | sort | join(", ")))")
			else . end' "$case_root/$side.stdout" >"$case_root/$side.normalized"
		done
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after sorting the routing modes\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	config-show-tied-text | config-show-tied-json)
		# config show sorts with sort.Slice, which is not stable, over rows gathered from Go maps,
		# so the rows of one key set by two sources print in either order. The exact cases pin
		# the order of distinct keys; here only the order of tied rows may vary.
		for side in oracle candidate; do
			if [[ "$comparison" == config-show-tied-json ]]; then
				jq 'sort_by(.key, .source, .value)' "$case_root/$side.stdout" >"$case_root/$side.normalized"
			else
				LC_ALL=C sort "$case_root/$side.stdout" >"$case_root/$side.normalized"
			fi
		done
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after sorting tied rows\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	stderr-only)
		# The exit code and stderr compared above. stdout prints this build's own name or identity.
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
	graph-open-json)
		# graph --open adds the rows it joins over left-out issues in Go map order.
		for side in oracle candidate; do
			jq -S '(.layout.Nodes[].DependsOn) |= (if . == null then . else sort end)' \
				"$case_root/$side.stdout" >"$case_root/$side.normalized"
		done
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after sorting DependsOn\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	graph-html)
		# graph --html lists its JSON nodes in Go map order. Each node starts with {"id":, which
		# cannot occur inside a JSON string, so split the nodes there and sort their exact text.
		for side in oracle candidate; do
			jq -Rr 'if startswith("const nodes = [{\"id\":") and endswith("}];") then
				"const nodes = [{\"id\":" + (.[21:-3] | split("},{\"id\":") | sort | join("},{\"id\":")) + "}];"
			else . end' "$case_root/$side.stdout" >"$case_root/$side.normalized"
		done
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after sorting the HTML nodes\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
		;;
	*)
		printf 'unknown real-database comparison: %s\n' "$comparison" >&2
		return 2
		;;
	esac
	printf 'parity [%ss]: PASS database/%s\n' "$SECONDS" "$name"
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

compare_real_database_local_config() {
	local name="$1"
	local comparison="$2"
	local config="$3"
	local local_config="$4"
	shift 4
	real_database_extra_config="$config"
	real_database_extra_local_config="$local_config"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_config=""
	real_database_extra_local_config=""
}

compare_real_database_metadata() {
	local name="$1"
	local comparison="$2"
	local filter="$3"
	shift 3
	real_database_extra_metadata="$filter"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_metadata=""
}

compare_real_database_config_env() {
	local name="$1"
	local comparison="$2"
	local config="$3"
	local environment="$4"
	shift 4
	real_database_extra_config="$config"
	real_database_extra_env=("$environment")
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_config=""
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
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

compare_real_database_sql() {
	local name="$1"
	local comparison="$2"
	local statements="$3"
	shift 3
	real_database_extra_sql="$statements"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_sql=""
}

# Runs only the candidate, for a view this build does not port yet: it must exit 1 with this
# exact output (stdout compared as compact JSON when given), leave the fixture and its HOME
# unchanged, and write nothing to its own empty TMPDIR.
expect_candidate_failure() {
	local name="$1"
	local expected_stdout="$2"
	local expected_stderr="$3"
	local statements="$4"
	shift 4
	printf 'parity [%ss]: START candidate-only/%s\n' "$SECONDS" "$name"
	candidate_only_case_count=$((candidate_only_case_count + 1))
	local case_root="$test_root/candidate-only-$name"
	local state_root="$case_root/candidate-state"
	local candidate_exit candidate_before candidate_after actual_stdout
	mkdir -p "$state_root/user-home/.dolt" "$state_root/config"
	printf '{}\n' >"$state_root/user-home/.dolt/config_global.json"
	copy_fixture_tree "$real_database_seed/work" "$state_root/work"
	chmod 700 "$state_root/work/.beads"
	if [[ -n "$statements" ]]; then
		printf '%s\n' "$statements" | "$fixture_sql" "$state_root/work" >/dev/null
	fi
	if [[ -n "$candidate_only_setup" ]]; then
		"$candidate_only_setup" "$state_root"
	fi
	mkdir -p "$case_root/candidate-tmp"
	candidate_before="$(fingerprint_tree "$state_root")"
	local candidate_work candidate_work_logical actual_stderr
	candidate_work="$(cd "$state_root/work" && pwd -P)"
	candidate_work_logical="$(cd "$state_root/work" && pwd -L)"
	local candidate_extra_env=("${real_database_extra_env[@]//<work>/$candidate_work}")
	set +e
	(
		cd "$state_root/work"
		env HOME="$state_root/user-home" \
			XDG_CONFIG_HOME="$state_root/config" \
			TMPDIR="$case_root/candidate-tmp" \
			"${real_database_env[@]}" \
			"${candidate_extra_env[@]}" \
			"$candidate" "$@"
	) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	candidate_exit=$?
	set -e
	candidate_after="$(fingerprint_tree "$state_root")"
	if [[ "$candidate_before" != "$candidate_after" ]]; then
		printf '%s candidate command changed the read-only fixture\n' "$name" >&2
		return 1
	fi
	if [[ -n "$(find "$case_root/candidate-tmp" -mindepth 1 -print -quit)" ]]; then
		printf '%s candidate command wrote temporary files\n' "$name" >&2
		find "$case_root/candidate-tmp" -mindepth 1 -print >&2
		return 1
	fi
	actual_stdout="$(cat "$case_root/candidate.stdout")"
	if [[ -n "$expected_stdout" ]]; then
		actual_stdout="$(jq -c . "$case_root/candidate.stdout" 2>/dev/null || cat "$case_root/candidate.stdout")"
	fi
	# A warning that names the workspace names it as <work>.
	actual_stderr="$(sed -e "s|$candidate_work|<work>|g" -e "s|$candidate_work_logical|<work>|g" "$case_root/candidate.stderr")"
	if [[ "$candidate_exit" -ne 1 || "$actual_stdout" != "$expected_stdout" ||
		"$actual_stderr" != "$expected_stderr" ]]; then
		printf '%s: expected exit 1, stdout [%s], stderr [%s]; got exit %s, stdout [%s], stderr [%s]\n' \
			"$name" "$expected_stdout" "$expected_stderr" "$candidate_exit" "$actual_stdout" \
			"$actual_stderr" >&2
		return 1
	fi
	printf 'parity [%ss]: PASS candidate-only/%s\n' "$SECONDS" "$name"
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
# The fixture has the custom type gate. Upstream fills an empty custom_types table from types.custom
# when it opens the store and then reads the table by name, so the config value prints each name
# once in byte order.
compare_real_database types-human exact types
compare_real_database types-json exact types --json
compare_real_database_env types-json-envelope exact BD_JSON_ENVELOPE=1 types --json
compare_real_database types-sections-human exact types --sections
compare_real_database types-sections-json exact types --sections --json
compare_real_database_env types-sections-json-envelope exact BD_JSON_ENVELOPE=1 types --sections --json
no_custom_types_sql="DELETE FROM custom_types
DELETE FROM config WHERE \`key\` = 'types.custom'"
compare_real_database_sql types-none-human exact "$no_custom_types_sql" types
compare_real_database_sql types-none-json exact "$no_custom_types_sql" types --json
custom_types_sql="INSERT INTO custom_types (name) VALUES ('zeta'), ('Alpha'), ('r&d<x>'), ('ünïcode'), (' spaced')"
compare_real_database_sql types-many-human exact "$custom_types_sql" types
compare_real_database_sql types-many-json exact "$custom_types_sql" types --json
types_config_sql="DELETE FROM custom_types
UPDATE config SET value = ' zeta, alpha ,zeta,,Beta ' WHERE \`key\` = 'types.custom'"
compare_real_database_sql types-config-human exact "$types_config_sql" types
types_config_json_sql="DELETE FROM custom_types
UPDATE config SET value = '[\"x\", \" y \", \"\", null, \"x\"]' WHERE \`key\` = 'types.custom'"
compare_real_database_sql types-config-json exact "$types_config_json_sql" types --json
# Server-mode, proxied and --global workspaces have no Haxe-owned route yet.
expect_candidate_failure types-global-unported "" \
	"Error: types is not available yet for server-mode or proxied workspaces in this build" "" types --global
# The fixture has no custom statuses. Upstream fills an empty custom_statuses table from a valid
# status.custom like custom_types, so those statuses print by name; an invalid value prints none.
compare_real_database statuses-human exact statuses
compare_real_database statuses-json exact statuses --json
custom_statuses_sql="INSERT INTO custom_statuses (name, category) VALUES ('review', 'active'), ('qa', 'wip'), ('shipped', 'done'), ('hold', 'frozen'), ('legacy', 'unspecified'), ('open', 'weird'), ('hooked', 'done'), ('pinned', 'active'), ('Ünï', 'wip'), ('a-very-long-status-name', 'x'), ('r&d<x>', 'wip')"
compare_real_database_sql statuses-many-human exact "$custom_statuses_sql" statuses
compare_real_database_sql statuses-many-json exact "$custom_statuses_sql" statuses --json
real_database_extra_sql="$custom_statuses_sql"
compare_real_database_env statuses-many-json-envelope exact BD_JSON_ENVELOPE=1 statuses --json
real_database_extra_sql=""
status_config_sql="DELETE FROM config WHERE \`key\` = 'status.custom'
INSERT INTO config (\`key\`, value) VALUES ('status.custom', ' zz:active , qa:wip,legacy,, hold:frozen ')"
compare_real_database_sql statuses-config-human exact "$status_config_sql" statuses
compare_real_database_sql statuses-config-json exact "$status_config_sql" statuses --json
compare_real_database_sql statuses-config-invalid-human exact "DELETE FROM config WHERE \`key\` = 'status.custom'
INSERT INTO config (\`key\`, value) VALUES ('status.custom', 'good:active,Bad')" statuses
expect_candidate_failure statuses-global-json-unported \
	'{"error":"statuses is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	statuses --global --json
# types.custom and status.custom also come from the layered config.yaml and BD_TYPES_CUSTOM or
# BD_STATUS_CUSTOM, through upstream's getConfigList: Viper's string list (a YAML sequence, or a
# scalar split at white space), each entry split again at commas. A set variable, even a blank
# one, replaces the YAML value; an empty one does not. Upstream appends these types to the
# database types, trimmed and each kept once, but uses these statuses only when the database has
# no custom_statuses row and no status.custom value.
types_yaml=$'types:\n  custom: " zeta, alpha ,zeta,,Beta "'
real_database_extra_sql="$no_custom_types_sql"
compare_real_database_config types-yaml-human exact "$types_yaml" types
compare_real_database_config types-yaml-json exact "$types_yaml" types --json
compare_real_database_config types-yaml-blank exact $'types:\n  custom: "  "' types
compare_real_database_env types-env-human exact 'BD_TYPES_CUSTOM=one two,three, one' types
compare_real_database_env types-env-json exact 'BD_TYPES_CUSTOM=one two,three, one' types --json
real_database_extra_sql=""
compare_real_database_config types-yaml-list exact $'types:\n  custom: [b c, "x,y", gate, "", 7]' types
compare_real_database_config types-yaml-flat-key exact 'types.custom: flat1,flat2' types --json
compare_real_database_config_env types-env-over-yaml exact "$types_yaml" BD_TYPES_CUSTOM=envonly types
compare_real_database_config_env types-empty-env-keeps-yaml exact "$types_yaml" BD_TYPES_CUSTOM= types
compare_real_database_config_env types-blank-env-hides-yaml exact "$types_yaml" 'BD_TYPES_CUSTOM=  ' types --json
compare_real_database_config_env types-yaml-json-envelope exact "$types_yaml" BD_JSON_ENVELOPE=1 types --json
compare_real_database_local_config types-local-over-yaml exact "$types_yaml" $'types:\n  custom: [local]' types
types_rows_yaml=$'types:\n  custom: "alpha, zeta ,Alpha,new,new"'
real_database_extra_sql="$custom_types_sql"
compare_real_database_config types-yaml-rows-human exact "$types_rows_yaml" types
compare_real_database_config types-yaml-rows-json exact "$types_rows_yaml" types --json
real_database_extra_sql="$types_config_sql"
compare_real_database_config types-yaml-config-value exact "$types_rows_yaml" types
real_database_extra_sql=""
statuses_yaml=$'status:\n  custom: " zz:active , qa:wip,legacy,, hold:frozen "'
compare_real_database_config statuses-yaml-human exact "$statuses_yaml" statuses
compare_real_database_config statuses-yaml-json exact "$statuses_yaml" statuses --json
compare_real_database_config statuses-yaml-list exact $'status:\n  custom: [review:active, "hold:frozen,qa"]' statuses --json
# A YAML value that does not parse lists each entry by name with the unspecified category.
compare_real_database_config statuses-yaml-invalid exact $'status:\n  custom: "review:bogus,open,Bad Name,qa,qa"' statuses
compare_real_database_config statuses-yaml-blank exact $'status:\n  custom: "  "' statuses --json
compare_real_database_env statuses-env-human exact 'BD_STATUS_CUSTOM=envst:wip later:frozen' statuses
compare_real_database_env statuses-env-json exact 'BD_STATUS_CUSTOM=envst:wip later:frozen' statuses --json
compare_real_database_config_env statuses-env-over-yaml exact "$statuses_yaml" BD_STATUS_CUSTOM=envst:done statuses
compare_real_database_config_env statuses-empty-env-keeps-yaml exact "$statuses_yaml" BD_STATUS_CUSTOM= statuses
compare_real_database_config_env statuses-blank-env-hides-yaml exact "$statuses_yaml" 'BD_STATUS_CUSTOM= ' statuses
compare_real_database_config_env statuses-yaml-json-envelope exact "$statuses_yaml" BD_JSON_ENVELOPE=1 statuses --json
real_database_extra_sql="$custom_statuses_sql"
compare_real_database_config statuses-rows-over-yaml exact "$statuses_yaml" statuses
real_database_extra_sql="$status_config_sql"
compare_real_database_config_env statuses-config-value-over-env exact "$statuses_yaml" BD_STATUS_CUSTOM=envst:wip statuses --json
# An invalid or blank status.custom value hides the layered statuses; an empty one does not.
real_database_extra_sql="DELETE FROM config WHERE \`key\` = 'status.custom'
INSERT INTO config (\`key\`, value) VALUES ('status.custom', 'good:active,Bad')"
compare_real_database_config statuses-invalid-value-hides-yaml exact "$statuses_yaml" statuses
real_database_extra_sql="DELETE FROM config WHERE \`key\` = 'status.custom'
INSERT INTO config (\`key\`, value) VALUES ('status.custom', '  ')"
compare_real_database_config statuses-blank-value-hides-yaml exact "$statuses_yaml" statuses
real_database_extra_sql="DELETE FROM config WHERE \`key\` = 'status.custom'
INSERT INTO config (\`key\`, value) VALUES ('status.custom', '')"
compare_real_database_env statuses-empty-value-uses-env exact BD_STATUS_CUSTOM=envst:wip statuses
real_database_extra_sql=""
# Like every upstream command, both warn once per config load that a config.yaml does not parse.
compare_real_database_config types-malformed-yaml exact $'types:\n  custom: [unclosed' types
compare_real_database_config statuses-malformed-yaml exact $'status:\n  custom: [unclosed' statuses --json
# bd config get and list. A database key reads the config table; a YAML-only key reads the layered
# config.yaml, config.local.yaml, BD_ variables and defaults through Viper; beads.role reads git
# config. Upstream prints values as stored, secrets included, so the fixtures use fake values.
# export.auto and backup.enabled stay off: with either on, upstream exports or backs up after any
# command, reads included.
compare_real_database config-list-human exact config list
compare_real_database config-list-json exact config list --json
compare_real_database_env config-list-json-envelope exact BD_JSON_ENVELOPE=1 config list --json
compare_real_database config-list-extra-argument exact config list extra
compare_real_database config-get-database-human exact config get issue_prefix
compare_real_database config-get-database-json exact config get issue_prefix --json
compare_real_database_env config-get-database-json-envelope exact BD_JSON_ENVELOPE=1 config get issue_prefix --json
compare_real_database config-get-unknown-human exact config get custom.missing
compare_real_database config-get-unknown-json exact config get custom.missing --json
compare_real_database config-get-empty-key exact config get ""
compare_real_database config-get-blank-key-json exact config get "  " --json
config_rows_sql="INSERT INTO config (\`key\`, value) VALUES ('custom.empty', ''), ('custom.api_token', 'fake-token-not-a-secret'), ('Zeta.Upper', 'say \"hi\"'), ('ünï.key', 'tab	here'), ('kv.memory.fake-note', 'hidden note'), ('kv.plain', 'hidden')"
compare_real_database_sql config-list-rows-human exact "$config_rows_sql" config list
compare_real_database_sql config-list-rows-json exact "$config_rows_sql" config list --json
compare_real_database_sql config-get-empty-value exact "$config_rows_sql" config get custom.empty
compare_real_database_sql config-get-fake-secret-json exact "$config_rows_sql" config get custom.api_token --json
compare_real_database_sql config-get-kv-hidden exact "$config_rows_sql" config get kv.memory.fake-note
compare_real_database_sql config-list-empty-human exact "DELETE FROM config" config list
compare_real_database_sql config-list-empty-json exact "DELETE FROM config" config list --json
real_database_extra_sql="$config_rows_sql"
compare_real_database_env config-list-database-env exact 'BD_ZETA_UPPER=say "hi"' config list
compare_real_database_env config-list-database-env-differs exact BD_ISSUE_PREFIX=zzz config list
compare_real_database_env config-get-database-ignores-env exact BD_ISSUE_PREFIX=zzz config get issue_prefix
real_database_extra_sql=""
compare_real_database config-get-yaml-default-human exact config get export.path
compare_real_database config-get-yaml-default-json exact config get export.auto --json
compare_real_database config-get-yaml-unset-human exact config get federation.remote
compare_real_database config-get-yaml-list-default exact config get federation.exclude_types
config_yaml=$'export:\n  git-add: true\n  interval:\n  path: ""\nsync:\n  remote: [first, second]\nrouting:\n  mode: Maintainer\nhierarchy:\n  max-depth: 0x10\nvalidation.on-create: warn\njira:\n  api_token: fake-token-not-a-secret\n  url: https://jira.example.invalid\ndolt:\n  max-conns: 1.50\nBackup:\n  Interval: 5m\nlist:\n  limit: 2\ncustom:\n  thing: yes'
compare_real_database_config config-list-yaml-human exact "$config_yaml" config list
compare_real_database_config config-list-yaml-json exact "$config_yaml" config list --json
compare_real_database_config config-get-yaml-bool exact "$config_yaml" config get export.git-add
compare_real_database_config config-get-yaml-null-default exact "$config_yaml" config get export.interval
compare_real_database_config config-get-yaml-empty-json exact "$config_yaml" config get export.path --json
compare_real_database_config config-get-yaml-list exact "$config_yaml" config get sync.remote
compare_real_database_config config-get-yaml-hex exact "$config_yaml" config get hierarchy.max-depth
compare_real_database_config config-get-yaml-float exact "$config_yaml" config get dolt.max-conns
compare_real_database_config config-get-yaml-folded-case exact "$config_yaml" config get backup.interval
compare_real_database_config config-get-yaml-flat-key exact "$config_yaml" config get validation.on-create
compare_real_database_config config-get-yaml-fake-secret exact "$config_yaml" config get jira.api_token
compare_real_database_config config-get-yaml-database-key exact "$config_yaml" config get jira.url
compare_real_database_config_env config-get-env-over-yaml exact "$config_yaml" BD_EXPORT_GIT_ADD=0 config get export.git-add
compare_real_database_config_env config-get-empty-env-keeps-yaml exact "$config_yaml" BD_ROUTING_MODE= config get routing.mode
compare_real_database_config_env config-get-blank-env-json exact "$config_yaml" 'BD_EXPORT_PATH= ' config get export.path --json
compare_real_database_config_env config-get-legacy-env-ignored exact "$config_yaml" BEADS_ROUTING_MODE=legacy config get routing.mode
compare_real_database_config_env config-list-env-over-yaml exact "$config_yaml" BD_EXPORT_GIT_ADD=false config list
compare_real_database_config_env config-list-legacy-env exact "$config_yaml" BEADS_ROUTING_MODE=legacy config list
compare_real_database_config_env config-list-empty-env exact "$config_yaml" BD_SYNC_REMOTE= config list
compare_real_database_env config-get-env-default exact BD_EXPORT_PATH=fake.jsonl config get export.path
compare_real_database_env config-get-bound-env exact BEADS_IDENTITY=fake-identity config get identity
compare_real_database_local_config config-get-local-over-yaml exact "$config_yaml" $'export:\n  git-add: false\nrouting:\n  mode: local' config get export.git-add
compare_real_database_local_config config-list-local exact "$config_yaml" $'routing:\n  mode: local' config list
malformed_yaml=$'export:\n  auto: [unclosed'
compare_real_database_config config-get-malformed-yaml exact "$malformed_yaml" config get export.auto
compare_real_database_config config-list-malformed-yaml exact "$malformed_yaml" config list
compare_real_database_local_config config-get-malformed-local exact "$config_yaml" "$malformed_yaml" config get routing.mode
compare_real_database config-get-beads-role exact config get beads.role
compare_real_database config-get-beads-role-json exact config get beads.role --json
compare_real_database config-get-backup-default exact config get backup.enabled
compare_real_database config-get-backup-default-json exact config get backup.enabled --json
compare_real_database_env config-get-backup-env exact BD_BACKUP_ENABLED=yes config get backup.enabled
compare_real_database_config config-get-backup-yaml-json exact $'backup:\n  enabled: false' config get backup.enabled --json
compare_real_database config-get-user-key exact-home config get metrics.disabled
compare_real_database config-get-user-key-json exact-home config get node_id --json
compare_real_database config-help exact config --help
compare_real_database config-bare exact config
compare_real_database config-unknown-subcommand exact config frobnicate
compare_real_database config-help-command exact help config
compare_real_database config-get-help exact config get --help
compare_real_database config-list-help exact config list --help
compare_real_database config-get-missing-argument exact config get
compare_real_database config-get-extra-argument exact config get one two
compare_real_database config-list-unknown-flag exact config list --bogus
# bd config show: every Viper key with its env, config.yaml or default source, then metadata.json
# fields, the database table without the kv. plane, git's beads.role and BEADS_MAX_ROWS, sorted
# by key. Upstream prints every value in full, secrets included; the fixtures use fake values.
compare_real_database config-show-human exact config show
compare_real_database config-show-json exact config show --json
compare_real_database_env config-show-json-envelope exact BD_JSON_ENVELOPE=1 config show --json
compare_real_database config-show-extra-argument exact config show extra
# --source keeps the rows whose source starts with the given text.
for config_source in default database metadata git env config.yaml; do
	compare_real_database "config-show-source-$config_source" exact config show --source "$config_source"
done
compare_real_database config-show-source-env-prefix exact config show --source "env: BEADS"
compare_real_database config-show-source-partial exact config show --source data
compare_real_database config-show-source-attached-json exact config show --source=git --json
compare_real_database config-show-source-empty exact config show --source=
compare_real_database config-show-source-unknown exact config show --source bogus
compare_real_database config-show-source-unknown-json exact config show --json --source bogus
compare_real_database_env config-show-source-unknown-envelope exact BD_JSON_ENVELOPE=1 config show --source bogus --json
compare_real_database config-show-help exact config show --help
compare_real_database config-show-help-command exact help config show
compare_real_database config-show-missing-source exact config show --source
compare_real_database config-show-unknown-flag exact config show --bogus
compare_real_database config-show-other-flag exact config show --sections
compare_real_database config-get-source-flag exact config get issue_prefix --source git
config_show_rows_sql="$config_rows_sql, ('custom.long', 'fake-long-value-0123456789-0123456789-0123456789-0123456789-end'), ('custom.sixty', 'sixty-bytes-0123456789-0123456789-0123456789-0123456789-0123'), ('custom.wide', 'a$(printf 'é%.0s' {1..35})'), ('custom.html', '<b>Tom & Jerry</b>')"
compare_real_database_sql config-show-rows-human exact "$config_show_rows_sql" config show
compare_real_database_sql config-show-rows-json exact "$config_show_rows_sql" config show --json
compare_real_database_sql config-show-rows-database exact "$config_show_rows_sql" config show --source database
compare_real_database_sql config-show-kv-only exact "DELETE FROM config WHERE \`key\` <> 'issue_prefix'
INSERT INTO config (\`key\`, value) VALUES ('kv.memory.fake-note', 'hidden note')" config show --source database
compare_real_database_sql config-show-empty-table-json exact "DELETE FROM config" config show --source database --json
compare_real_database_config config-show-yaml-human exact "$config_yaml" config show
compare_real_database_config config-show-yaml-json exact "$config_yaml" config show --json
compare_real_database_config config-show-yaml-source exact "$config_yaml" config show --source config.yaml
compare_real_database_config config-show-yaml-containers exact $'external_projects:\n  other: ../other\ndirectory:\n  labels:\n    frontend: fe\nrepos:\n  primary: "."\n  additional: [a, b]' config show --source config
compare_real_database_local_config config-show-local exact "$config_yaml" $'routing:\n  mode: local\nexport:\n  auto: true' config show --source config.yaml
compare_real_database_config config-show-malformed-yaml exact "$malformed_yaml" config show
compare_real_database_config_env config-show-env-over-yaml exact "$config_yaml" BD_EXPORT_GIT_ADD=0 config show --source env
compare_real_database_config_env config-show-legacy-env exact "$config_yaml" BEADS_ROUTING_MODE=legacy config show
compare_real_database_config_env config-show-empty-env exact "$config_yaml" BD_SYNC_REMOTE= config show --source env
compare_real_database_env config-show-env-default exact BD_EXPORT_PATH=fake.jsonl config show --source env
compare_real_database_env config-show-bound-env exact BEADS_IDENTITY=fake-identity config show
compare_real_database_env config-show-user-key-env exact BEADS_NODE_ID=fake-node config show --source env
compare_real_database_env config-show-max-rows exact BEADS_MAX_ROWS=25 config show
compare_real_database_env config-show-max-rows-json exact BEADS_MAX_ROWS=not-a-number config show --source env --json
compare_real_database_env config-show-max-rows-empty exact BEADS_MAX_ROWS= config show --source env
# The actor row follows upstream's BEADS_ACTOR > BD_ACTOR > config.yaml order.
compare_real_database_env config-show-actor-empty exact BEADS_ACTOR= config show --source env
compare_real_database_env config-show-actor-bd exact BD_ACTOR=bd-fixture config show --source env
real_database_extra_env=(BEADS_ACTOR= BD_ACTOR=bd-fixture)
compare_real_database config-show-actor-bd-only exact config show --source env
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database_config_env config-show-actor-yaml exact 'actor: yaml-actor' BEADS_ACTOR= config show --source env
compare_real_database_config config-show-actor-yaml-shadowed exact 'actor: yaml-actor' config show --source env
compare_real_database_metadata config-show-metadata-fields exact '.dolt_server_host = "db.example.invalid" | .dolt_server_user = "fake-user" | .dolt_server_tls = true | .dolt_remotesapi_port = 8080 | .deletions_retention_days = 7 | .stale_closed_issues_days = -5' config show --source metadata
# encoding/json matches metadata.json keys under case folding: ſ folds to s, but ı does not fold to i.
compare_real_database_metadata config-show-metadata-folded-keys exact '.DOLT_REMOTESAPI_PORT = 9090 | .Project_ID = "fake-project" | .dolt_server_user = null | .dolt_data_dir = null | .["ſtale_closed_issues_days"] = 9 | .["dolt_server_hoſt"] = "folded.example.invalid" | .["dolt_ſerver_user"] = "fake-user" | .["dolt_data_dır"] = "/not-a-match"' config show --source metadata --json
compare_real_database_metadata config-show-metadata-zero-values exact '.dolt_server_tls = false | .deletions_retention_days = 0 | .dolt_server_host = "" | del(.dolt_mode)' config show
# One key set by two sources prints two rows whose order upstream leaves to chance.
config_show_tied_yaml=$'issue_prefix: yaml-prefix\nproject_id: yaml-project\nbeads.role: yaml-role\ntypes:\n  custom: yaml-type'
compare_real_database_config config-show-tied-human config-show-tied-text "$config_show_tied_yaml" config show
compare_real_database_config config-show-tied-json config-show-tied-json "$config_show_tied_yaml" config show --json
# bd config validate: doctor's config.yaml, metadata.json and database checks, then the sync checks of
# the workspace config.yaml. Each case also requires upstream to leave the fixture and TMPDIR as they
# were. The JSON form exits 0 even when it lists issues.
real_database_read_only=1
compare_real_database config-validate-human exact config validate
compare_real_database config-validate-json exact config validate --json
compare_real_database_env config-validate-json-envelope exact BD_JSON_ENVELOPE=1 config validate --json
compare_real_database config-validate-extra-argument exact config validate extra
compare_real_database config-validate-help exact config validate --help
compare_real_database config-validate-help-command exact help config validate
compare_real_database config-validate-unknown-flag exact config validate --bogus
compare_real_database config-validate-source-flag exact config validate --source git
validate_valid_yaml=$'federation:\n  remote: dolthub://org/repo\n  sovereignty: t2'
compare_real_database_config config-validate-valid exact "$validate_valid_yaml" config validate
compare_real_database_config config-validate-valid-json exact "$validate_valid_yaml" config validate --json
validate_invalid_yaml=$'issue-prefix: 1bad-prefix-that-is-way-too-long\nactor: "-bad actor"\njson: maybe\nno-db: "1"\nsync:\n  require_confirmation_on_mass_delete: perhaps\nfederation:\n  sovereignty: t5\n  remote: "ftp://example.invalid/x"'
compare_real_database_config config-validate-invalid-values exact "$validate_invalid_yaml" config validate
compare_real_database_config config-validate-invalid-values-json exact "$validate_invalid_yaml" config validate --json
compare_real_database_config config-validate-routing-mode config-validate-routing $'routing:\n  mode: Maintainer' config validate
compare_real_database_config config-validate-routing-mode-json config-validate-routing $'routing:\n  mode: bogus' config validate --json
# Paths are checked from the current directory, and `~` from HOME.
validate_routing_yaml=$'routing:\n  mode: auto\n  contributor: ../planning\n  maintainer: /nonexistent/maint\n  default: "~/missing"\nrepos:\n  primary: .beads/config.yaml\n  additional: [../planning, .beads/metadata.json, .beads]'
compare_real_database_config config-validate-routing-auto exact "$validate_routing_yaml" config validate
compare_real_database_config config-validate-routing-unhydrated exact $'routing:\n  mode: auto\n  contributor: "~/plans"' config validate
compare_real_database_config config-validate-repos-unreadable exact $'repos:\n  primary: .beads/config.yaml/inner' config validate
validate_remote_index=0
for validate_remote in 'dolthub://org' 'https:///path' 's3:///key' 'az://' 'oci:///x' 'git+ssh:///repo' \
	'git+https://host/x' 'git@github.com:org/repo.git' '-upload-pack' 'example.invalid/repo' \
	'https://host/%zz' 'https://exa mple.com' '"tab\there"' 'file:///tmp/remote'; do
	validate_remote_index=$((validate_remote_index + 1))
	compare_real_database_config "config-validate-remote-$validate_remote_index" exact \
		$'federation:\n  remote: '"$validate_remote" config validate --json
done
compare_real_database_config config-validate-remote-pattern-miss exact \
	$'federation:\n  remote: dolthub://org/repo\n  allowed-remote-patterns: ["[", "dolthub://other/*"]' config validate
compare_real_database_config config-validate-remote-pattern-match exact \
	$'federation:\n  remote: dolthub://org/repo\n  allowed-remote-patterns: dolthub://org/*' config validate
# A URL that fails the structural check fails the pattern check too, so upstream reports it twice.
compare_real_database_config config-validate-remote-pattern-twice exact \
	$'federation:\n  remote: ftp://x\n  allowed-remote-patterns: ["ftp://*"]' config validate
# Like every command, both warn that config.yaml does not parse; validate also lists the parse error,
# split at its newlines.
compare_real_database_config config-validate-malformed-yaml exact "$malformed_yaml" config validate
compare_real_database_config config-validate-unmarshal-yaml exact $'- a\n- b' config validate --json
compare_real_database_metadata config-validate-metadata-database exact '.database = "beads.db"' config validate
compare_real_database_metadata config-validate-metadata-path exact '.database = "sub/dir"' config validate
compare_real_database_metadata config-validate-metadata-retention exact '.deletions_retention_days = -3' config validate --json
# validate reads only the workspace config.yaml: config.local.yaml and BD_ variables do not count.
compare_real_database_local_config config-validate-local-ignored exact "" $'routing:\n  mode: bogus' config validate
compare_real_database_env config-validate-env-ignored exact BD_ROUTING_MODE=bogus config validate
remove_embedded_database() {
	rm -rf "$1/work/.beads/embeddeddolt"
}
real_database_setup=remove_embedded_database
compare_real_database_metadata config-validate-no-database exact '.dolt_database = "te-st"' config validate
real_database_setup=""
# Without metadata.json or a database, upstream opens no store and checks config.yaml alone.
remove_database_and_metadata() {
	rm -rf "$1/work/.beads/embeddeddolt" "$1/work/.beads/metadata.json"
}
real_database_setup=remove_database_and_metadata
compare_real_database_config config-validate-config-only exact $'routing:\n  mode: auto\n  maintainer: ../maint' config validate
compare_real_database config-drift-config-only exact config drift
real_database_setup=""
# A Dolt data directory makes doctor dial a server for the database checks. Embedded workspaces
# configure none, so the dial goes to port 0 and fails at once; upstream lists the error's lines.
make_dolt_directory() {
	mkdir -p "$1/work/.beads/dolt"
}
real_database_setup=make_dolt_directory
compare_real_database config-validate-dolt-directory exact config validate
compare_real_database config-validate-dolt-directory-json exact config validate --json
compare_real_database_env config-validate-dolt-directory-auto-start-off exact BEADS_DOLT_AUTO_START=0 config validate
real_database_setup=""
# Without the workspace config.yaml, doctor reads the user one and the sync checks are skipped.
remove_workspace_config() {
	rm -f "$1/work/.beads/config.yaml"
}
real_database_setup=remove_workspace_config
compare_real_database config-validate-no-config-yaml exact config validate
real_database_setup=""
use_legacy_user_config() {
	rm -f "$1/work/.beads/config.yaml"
	mkdir -p "$1/user-home/.beads"
	printf 'actor: "bad actor"\n' >"$1/user-home/.beads/config.yaml"
}
real_database_setup=use_legacy_user_config
compare_real_database config-validate-user-config exact config validate
real_database_setup=""
# bd config drift: the git hooks, the Dolt remote and the server checks; exit 1 when one drifts. In an
# embedded workspace the remote check's server store does not open, so it reports that error.
compare_real_database config-drift-human exact config drift
compare_real_database config-drift-json exact config drift --json
compare_real_database_env config-drift-json-envelope exact BD_JSON_ENVELOPE=1 config drift --json
compare_real_database config-drift-extra-argument exact config drift extra
compare_real_database config-drift-help exact config drift --help
compare_real_database config-drift-help-command exact help config drift
compare_real_database config-drift-unknown-flag exact config drift --bogus
drift_hook_content=""
write_drift_hooks() {
	local hook
	mkdir -p "$1/work/.git/hooks"
	for hook in pre-commit post-merge pre-push post-checkout prepare-commit-msg; do
		printf '%s\n' "$drift_hook_content" >"$1/work/.git/hooks/$hook"
	done
}
real_database_setup=write_drift_hooks
drift_hook_content=$'#!/bin/sh\n# bd-shim v1\nexec bd hooks run'
compare_real_database config-drift-hooks-shim exact config drift
drift_hook_content=$'#!/bin/sh\n# bd-hooks-version: 0.9.0'
compare_real_database config-drift-hooks-legacy-json exact config drift --json
drift_hook_content=$'#!/bin/sh\n# bd-hooks-version: 1.2.1'
compare_real_database config-drift-hooks-current exact config drift
drift_hook_content=$'#!/bin/sh\n# bd (beads)\nbd sync'
compare_real_database config-drift-hooks-inline exact config drift
drift_hook_content=$'#!/bin/sh\necho user\n# --- BEGIN BEADS INTEGRATION v0.56.1 ---\nbd hooks run\n# --- END BEADS INTEGRATION ---'
compare_real_database config-drift-hooks-section exact config drift
drift_hook_content=$'#!/bin/sh\necho hi'
compare_real_database config-drift-hooks-foreign exact config drift
real_database_setup=""
# A directory reads as a missing hook; a legacy marker line keeps its version without the CR.
write_mixed_hooks() {
	mkdir -p "$1/work/.git/hooks/pre-commit"
	printf '# bd-hooks-version: 0.1\n' >"$1/work/.git/hooks/pre-push"
	printf '# bd (beads)\n' >"$1/work/.git/hooks/post-merge"
	printf '# bd-hooks-version: 0.2\r\n' >"$1/work/.git/hooks/prepare-commit-msg"
}
real_database_setup=write_mixed_hooks
compare_real_database config-drift-hooks-mixed exact config drift
real_database_setup=""
use_relative_hooks_path() {
	git -C "$1/work" config core.hooksPath .beads/hooks
	mkdir -p "$1/work/.beads/hooks"
	printf '# bd-shim v2\n' >"$1/work/.beads/hooks/pre-commit"
}
real_database_setup=use_relative_hooks_path
compare_real_database config-drift-hooks-path exact config drift
real_database_setup=""
use_home_hooks_path() {
	git -C "$1/work" config core.hooksPath '~/hooks'
	mkdir -p "$1/user-home/hooks"
	printf '# bd-shim v2\n' >"$1/user-home/hooks/pre-push"
}
real_database_setup=use_home_hooks_path
compare_real_database config-drift-hooks-home-path exact config drift --json
real_database_setup=""
remove_git_checkout() {
	rm -rf "$1/work/.git"
}
real_database_setup=remove_git_checkout
compare_real_database config-drift-not-git exact config drift
real_database_setup=""
# The server check reads .beads/dolt-server.pid and asks whether that process exists with signal 0.
# This shell's own pid is alive for the whole run.
drift_pid_content=""
write_server_pid() {
	printf '%s' "$drift_pid_content" >"$1/work/.beads/dolt-server.pid"
}
real_database_setup=write_server_pid
drift_pid_content="$$"$'\n'
compare_real_database config-drift-server-running exact config drift
drift_pid_content=" +$$ "$'\n'
compare_real_database config-drift-server-signed-pid exact config drift
drift_pid_content=$'2147483647\n'
compare_real_database config-drift-server-dead-pid exact config drift --json
drift_pid_content="0"
compare_real_database config-drift-server-zero-pid exact config drift
drift_pid_content="not-a-pid"
compare_real_database config-drift-server-garbage-pid exact config drift
real_database_setup=""
compare_real_database_env config-drift-auto-start-env exact BEADS_DOLT_AUTO_START=off config drift
compare_real_database_env config-drift-auto-start-bd-env exact BD_DOLT_AUTO_START=false config drift
compare_real_database_config config-drift-auto-start-config exact $'dolt:\n  auto-start: "0"' config drift
real_database_setup=remove_embedded_database
compare_real_database config-drift-no-database exact config drift --json
# Upstream will not open a test-named database on any server unless BEADS_TEST_SERVER=1.
compare_real_database_metadata config-drift-test-database exact '.dolt_database = "beads_test_parity"' config drift
real_database_extra_metadata='.dolt_database = "beads_test_parity"'
compare_real_database_env config-drift-test-database-allowed exact BEADS_TEST_SERVER=1 config drift
real_database_extra_metadata=""
real_database_setup=""
real_database_read_only=""
# In shared-server mode, or with a configured server address or port, upstream connects to that
# server or creates state for it; bdhx refuses before it dials or opens anything.
enable_shared_server() {
	printf 'dolt:\n  shared-server: true\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=enable_shared_server
expect_candidate_failure config-validate-shared-server-unported "" \
	"Error: config validate is not available yet in shared-server mode in this build" "" config validate
expect_candidate_failure config-drift-shared-server-unported \
	'{"error":"config drift is not available yet in shared-server mode in this build","schema_version":1}' "" "" \
	config drift --json
candidate_only_setup=""
real_database_extra_env=(BEADS_DOLT_SERVER_PORT=3307)
expect_candidate_failure config-drift-endpoint-unported "" \
	"Error: config drift is not available yet when a Dolt server endpoint is configured in this build" "" config drift
real_database_extra_env=(BEADS_DOLT_PORT=1)
candidate_only_setup=make_dolt_directory
expect_candidate_failure config-validate-endpoint-unported "" \
	"Error: config validate is not available yet when a Dolt server endpoint is configured in this build" "" config validate
candidate_only_setup=""
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
write_server_port_file() {
	printf '3307\n' >"$1/work/.beads/dolt-server.port"
}
candidate_only_setup=write_server_port_file
expect_candidate_failure config-drift-port-file-unported "" \
	"Error: config drift is not available yet when a Dolt server endpoint is configured in this build" "" config drift
candidate_only_setup=""
# A db setting moves upstream to another database path, where it creates a database.
set_database_path() {
	printf 'db: other/beads.db\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=set_database_path
expect_candidate_failure config-validate-db-setting-unported "" \
	"Error: config validate is not available yet when the db setting names a database in this build" "" config validate
candidate_only_setup=""
# config get, list and show refuse the same two settings before they open a store. Upstream connects
# to the shared server (creating ~/.beads/shared-server/dolt and a TMPDIR circuit file), or opens or
# creates the database that the db setting names.
candidate_only_setup=enable_shared_server
expect_candidate_failure config-get-shared-server-unported "" \
	"Error: config get is not available yet in shared-server mode in this build" "" config get issue_prefix
expect_candidate_failure config-get-yaml-shared-server-json-unported \
	'{"error":"config get is not available yet in shared-server mode in this build","schema_version":1}' "" "" \
	config get routing.mode --json
expect_candidate_failure config-list-shared-server-unported "" \
	"Error: config list is not available yet in shared-server mode in this build" "" config list
expect_candidate_failure config-list-shared-server-json-unported \
	'{"error":"config list is not available yet in shared-server mode in this build","schema_version":1}' "" "" \
	config list --json
expect_candidate_failure config-show-shared-server-unported "" \
	"Error: config show is not available yet in shared-server mode in this build" "" config show
expect_candidate_failure config-show-shared-server-json-unported \
	'{"error":"config show is not available yet in shared-server mode in this build","schema_version":1}' "" "" \
	config show --json
candidate_only_setup=""
# Upstream also turns shared-server mode on from config.local.yaml and from both variables.
enable_local_shared_server() {
	printf 'dolt:\n  shared-server: true\n' >"$1/work/.beads/config.local.yaml"
}
candidate_only_setup=enable_local_shared_server
expect_candidate_failure config-show-local-shared-server-unported "" \
	"Error: config show is not available yet in shared-server mode in this build" "" config show
candidate_only_setup=""
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure config-get-shared-server-env-unported "" \
	"Error: config get is not available yet in shared-server mode in this build" "" config get beads.role
real_database_extra_env=(BD_DOLT_SHARED_SERVER=true)
expect_candidate_failure config-list-shared-server-bd-env-unported "" \
	"Error: config list is not available yet in shared-server mode in this build" "" config list
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Without a database upstream opens no store for a key that needs none, but it prints a notice when
# metadata.json pins dolt_mode embedded, as this fixture's does.
enable_shared_server_without_database() {
	enable_shared_server "$1"
	remove_embedded_database "$1"
}
candidate_only_setup=enable_shared_server_without_database
expect_candidate_failure config-get-shared-server-no-database-unported "" \
	"Error: config get is not available yet in shared-server mode in this build" "" config get routing.mode
candidate_only_setup=set_database_path
expect_candidate_failure config-get-db-setting-unported "" \
	"Error: config get is not available yet when the db setting names a database in this build" "" config get issue_prefix
expect_candidate_failure config-get-yaml-db-setting-json-unported \
	'{"error":"config get is not available yet when the db setting names a database in this build","schema_version":1}' "" "" \
	config get routing.mode --json
expect_candidate_failure config-list-db-setting-unported "" \
	"Error: config list is not available yet when the db setting names a database in this build" "" config list
expect_candidate_failure config-show-db-setting-json-unported \
	'{"error":"config show is not available yet when the db setting names a database in this build","schema_version":1}' "" "" \
	config show --json
# An empty BD_DB counts as unset.
real_database_extra_env=(BD_DB=)
expect_candidate_failure config-get-db-setting-empty-bd-db-unported "" \
	"Error: config get is not available yet when the db setting names a database in this build" "" config get beads.role
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
set_local_database_path() {
	printf 'db: other/beads.db\n' >"$1/work/.beads/config.local.yaml"
}
candidate_only_setup=set_local_database_path
expect_candidate_failure config-show-local-db-setting-unported "" \
	"Error: config show is not available yet when the db setting names a database in this build" "" config show
candidate_only_setup=""
# Upstream takes the db setting only when no --db, -C, BEADS_DB, BD_DB or BEADS_DIR selects the
# workspace; otherwise these commands read the workspace as usual and write nothing.
real_database_read_only=1
real_database_setup=set_database_path
compare_real_database_env config-get-db-setting-bd-db exact BD_DB=fake-selector config get issue_prefix
compare_real_database_env config-show-db-setting-bd-db exact BD_DB=fake-selector config show --source env
compare_real_database_env config-validate-db-setting-bd-db exact BD_DB=fake-selector config validate
compare_real_database config-list-db-setting-directory exact -C . config list
compare_real_database config-show-db-setting-flag exact --db .beads config show --source config.yaml
real_database_setup=""
# In shared-server mode, upstream opens no store for a key that needs none when the workspace has
# no database and metadata.json does not pin dolt_mode, and then prints nothing about the mode.
real_database_setup=remove_embedded_database
real_database_extra_metadata='del(.dolt_mode)'
compare_real_database_config config-get-shared-server-no-database exact $'dolt:\n  shared-server: true' \
	config get routing.mode
compare_real_database_config config-get-shared-server-no-database-backup-json exact $'dolt:\n  shared-server: true' \
	config get backup.enabled --json
real_database_extra_metadata=""
real_database_setup=""
real_database_read_only=""
# Every other command that opens a store refuses the same two settings before it opens one. In
# shared-server mode upstream creates ~/.beads/shared-server/dolt and a TMPDIR circuit file, then
# fails to reach the server; with a db setting it creates an embedded database at that path.
# expect_store_refusal <case> <reason> <command path> <args>... expects the refusal in text, or in
# JSON on stdout when the arguments include --json.
expect_store_refusal() {
	local name="$1"
	local message="$3 is not available yet $2 in this build"
	shift 3
	if [[ " $* " == *" --json "* ]]; then
		expect_candidate_failure "$name" "{\"error\":\"$message\",\"schema_version\":1}" "" "" "$@"
	else
		expect_candidate_failure "$name" "" "Error: $message" "" "$@"
	fi
}
shared_reason="in shared-server mode"
candidate_only_setup=enable_shared_server
expect_store_refusal count-shared-server-unported "$shared_reason" count count
expect_store_refusal count-shared-server-json-unported "$shared_reason" count count --json
expect_store_refusal list-shared-server-unported "$shared_reason" list list
expect_store_refusal list-global-shared-server-unported "$shared_reason" list list --global
expect_store_refusal show-shared-server-json-unported "$shared_reason" show show "$real_database_issue_id" --json
expect_store_refusal children-shared-server-unported "$shared_reason" children children "$real_database_epic_id"
expect_store_refusal ready-shared-server-unported "$shared_reason" ready ready
expect_store_refusal blocked-shared-server-unported "$shared_reason" blocked blocked
expect_store_refusal search-shared-server-unported "$shared_reason" search search parity
expect_store_refusal query-shared-server-unported "$shared_reason" query query status=open
expect_store_refusal stale-shared-server-unported "$shared_reason" stale stale
expect_store_refusal orphans-shared-server-unported "$shared_reason" orphans orphans
expect_store_refusal dep-list-shared-server-unported "$shared_reason" "dep list" dep list "$real_database_issue_id"
expect_store_refusal dep-tree-shared-server-unported "$shared_reason" "dep tree" dep tree "$real_database_issue_id"
expect_store_refusal dep-cycles-shared-server-json-unported "$shared_reason" "dep cycles" dep cycles --json
expect_store_refusal graph-shared-server-unported "$shared_reason" graph graph "$real_database_issue_id"
expect_store_refusal graph-check-shared-server-unported "$shared_reason" "graph check" graph check
expect_store_refusal comments-shared-server-unported "$shared_reason" comments comments "$real_database_issue_id"
expect_store_refusal history-shared-server-unported "$shared_reason" history history "$real_database_issue_id"
expect_store_refusal events-tail-shared-server-unported "$shared_reason" "events tail" events tail
expect_store_refusal events-export-shared-server-unported "$shared_reason" "events export" events export
expect_store_refusal types-shared-server-unported "$shared_reason" types types
expect_store_refusal statuses-shared-server-json-unported "$shared_reason" statuses statuses --json
expect_store_refusal label-list-shared-server-unported "$shared_reason" "label list" label list "$real_database_issue_id"
expect_store_refusal label-list-all-shared-server-unported "$shared_reason" "label list-all" label list-all
expect_store_refusal info-shared-server-unported "$shared_reason" info info
expect_store_refusal info-whats-new-shared-server-unported "$shared_reason" info info --whats-new
expect_store_refusal status-shared-server-unported "$shared_reason" status status
expect_store_refusal ping-shared-server-json-unported "$shared_reason" ping ping --json
candidate_only_setup=enable_local_shared_server
expect_store_refusal ready-local-shared-server-unported "$shared_reason" ready ready
candidate_only_setup=""
enable_user_shared_server() {
	mkdir -p "$1/user-home/.config/bd"
	printf 'dolt:\n  shared-server: true\n' >"$1/user-home/.config/bd/config.yaml"
}
candidate_only_setup=enable_user_shared_server
expect_store_refusal show-user-shared-server-unported "$shared_reason" show show "$real_database_issue_id"
candidate_only_setup=""
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_store_refusal dep-tree-shared-server-env-unported "$shared_reason" "dep tree" dep tree "$real_database_issue_id"
real_database_extra_env=(BD_DOLT_SHARED_SERVER=true)
expect_store_refusal comments-shared-server-bd-env-json-unported "$shared_reason" comments comments "$real_database_issue_id" --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Without a database upstream writes nothing, but it prints a notice when metadata.json pins
# dolt_mode embedded and always gives the server-mode hint, which this build does not print.
candidate_only_setup=enable_shared_server_without_database
expect_store_refusal count-shared-server-no-database-unported "$shared_reason" count count
candidate_only_setup=""
enable_shared_server_without_database_or_mode() {
	enable_shared_server_without_database "$1"
	jq 'del(.dolt_mode)' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
candidate_only_setup=enable_shared_server_without_database_or_mode
expect_store_refusal list-shared-server-no-database-unported "$shared_reason" list list
candidate_only_setup=""
database_reason="when the db setting names a database"
candidate_only_setup=set_database_path
expect_store_refusal count-db-setting-unported "$database_reason" count count
expect_store_refusal list-db-setting-json-unported "$database_reason" list list --json
expect_store_refusal show-db-setting-unported "$database_reason" show show "$real_database_issue_id"
expect_store_refusal ready-db-setting-unported "$database_reason" ready ready
expect_store_refusal dep-tree-db-setting-unported "$database_reason" "dep tree" dep tree "$real_database_issue_id"
expect_store_refusal graph-check-db-setting-unported "$database_reason" "graph check" graph check
expect_store_refusal comments-db-setting-unported "$database_reason" comments comments "$real_database_issue_id"
expect_store_refusal history-db-setting-json-unported "$database_reason" history history "$real_database_issue_id" --json
expect_store_refusal events-tail-db-setting-unported "$database_reason" "events tail" events tail
expect_store_refusal types-db-setting-unported "$database_reason" types types
expect_store_refusal statuses-db-setting-unported "$database_reason" statuses statuses
expect_store_refusal label-list-all-db-setting-unported "$database_reason" "label list-all" label list-all
expect_store_refusal info-whats-new-db-setting-unported "$database_reason" info info --whats-new
expect_store_refusal status-db-setting-json-unported "$database_reason" status status --json
expect_store_refusal ping-db-setting-unported "$database_reason" ping ping
# An empty BD_DB counts as unset.
real_database_extra_env=(BD_DB=)
expect_store_refusal orphans-db-setting-empty-bd-db-unported "$database_reason" orphans orphans
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=set_local_database_path
expect_store_refusal blocked-local-db-setting-unported "$database_reason" blocked blocked
candidate_only_setup=""
set_user_database_path() {
	mkdir -p "$1/user-home/.config/bd"
	printf 'db: %s/elsewhere/beads.db\n' "$1" >"$1/user-home/.config/bd/config.yaml"
}
candidate_only_setup=set_user_database_path
expect_store_refusal search-user-db-setting-unported "$database_reason" search search parity
candidate_only_setup=""
# Upstream opens the database that the db setting names even when the workspace has none, or when
# no workspace is found at all.
set_database_path_without_database() {
	set_database_path "$1"
	remove_embedded_database "$1"
}
candidate_only_setup=set_database_path_without_database
expect_store_refusal stale-db-setting-no-database-unported "$database_reason" stale stale
candidate_only_setup=""
set_user_database_path_without_workspace() {
	set_user_database_path "$1"
	rm -rf "$1/work/.beads"
}
candidate_only_setup=set_user_database_path_without_workspace
expect_store_refusal count-db-setting-no-workspace-unported "$database_reason" count count
expect_store_refusal config-list-db-setting-no-workspace-unported "$database_reason" "config list" config list
candidate_only_setup=""
# Like upstream, these commands ignore the db setting when --db, -C or BD_DB selects the workspace,
# and run as usual without writing.
real_database_read_only=1
real_database_setup=set_database_path
compare_real_database_env count-db-setting-bd-db exact BD_DB=fake-selector count
compare_real_database_env comments-db-setting-bd-db-json exact BD_DB=fake-selector comments "$real_database_issue_id" --json
compare_real_database ready-db-setting-directory exact -C . ready
compare_real_database label-list-all-db-setting-flag exact --db .beads label list-all
real_database_setup=""
# Help needs no store, so upstream writes nothing in shared-server mode, and neither does bdhx.
real_database_setup=enable_shared_server
compare_real_database count-help-shared-server exact count --help
compare_real_database label-help-shared-server exact label
real_database_setup=""
# Shared-server mode is off unless the variable is 1 or true.
compare_real_database_env count-shared-server-env-off exact BEADS_DOLT_SHARED_SERVER=0 count
real_database_read_only=""
use_sqlite_backend() {
	jq '.backend = "sqlite"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
candidate_only_setup=use_sqlite_backend
expect_candidate_failure config-drift-backend-unported "" \
	"Error: config drift is not available yet for a storage backend other than dolt in this build" "" config drift
candidate_only_setup=""
expect_candidate_failure config-validate-global-unported \
	'{"error":"config is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	config validate --global --json
expect_candidate_failure config-drift-global-unported "" \
	"Error: config is not available yet for server-mode or proxied workspaces in this build" "" config drift --global
# Writes and the apply view are not ported; they fail before touching the fixture.
for config_subcommand in set set-many unset apply; do
	expect_candidate_failure "config-$config_subcommand-unported" "" \
		"Error: config $config_subcommand is not available yet in this build" "" config "$config_subcommand" export.auto true
done
expect_candidate_failure config-list-global-unported "" \
	"Error: config is not available yet for server-mode or proxied workspaces in this build" "" config list --global
expect_candidate_failure config-get-global-json-unported \
	'{"error":"config is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	config get export.auto --global --json
expect_candidate_failure config-show-global-unported "" \
	"Error: config is not available yet for server-mode or proxied workspaces in this build" "" config show --global
expect_candidate_failure config-show-global-json-unported \
	'{"error":"config is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	config show --global --json
# Upstream config show creates the embedded database when the workspace has none.
candidate_only_setup=remove_embedded_database
expect_candidate_failure config-show-no-database-unported "" \
	"Error: config show is not available yet for a workspace without a database in this build" "" config show
candidate_only_setup=""
# metrics.* and node_id come from the user config.yaml alone, which this build does not read yet.
write_user_config() {
	mkdir -p "$1/user-home/.config/bd"
	printf 'metrics:\n  disabled: true\n' >"$1/user-home/.config/bd/config.yaml"
}
candidate_only_setup=write_user_config
expect_candidate_failure config-show-user-config-unported \
	'{"error":"config show is not available yet when a user config.yaml exists in this build","schema_version":1}' "" "" \
	config show --json
candidate_only_setup=""
# Upstream's root pre-run reads metadata.json, or a legacy config.json, with configfile.LoadForDiscovery.
# When that fails it warns, and then where and every command that opens a store stop with the load
# error, as text even under --json. version, the root help and `bd help` only warn; a --help flag and
# the command groups skip the pre-run. Unknown keys, null members and duplicate keys (the last one
# wins) decode. Neither side may change the fixture or write temporary files.
real_database_read_only=1
# Replaces metadata.json in place with $raw_metadata, so the file keeps its mode.
write_raw_metadata() {
	printf '%s' "$raw_metadata" >"$1/work/.beads/metadata.json"
}
compare_raw_metadata() {
	local name="$1"
	local comparison="$2"
	raw_metadata="$3"
	shift 3
	real_database_setup=write_raw_metadata
	compare_real_database "$name" "$comparison" "$@"
	real_database_setup=""
}
type_error_metadata='{"database":"dolt","backend":"dolt","dolt_mode":"embedded","dolt_database":7}'
compare_raw_metadata metadata-type-count exact "$type_error_metadata" count
compare_raw_metadata metadata-type-count-json exact "$type_error_metadata" count --json
compare_raw_metadata metadata-type-list-json exact "$type_error_metadata" list --json
compare_raw_metadata metadata-type-show exact "$type_error_metadata" show "$real_database_issue_id"
compare_raw_metadata metadata-type-ready-json exact "$type_error_metadata" ready --json
compare_raw_metadata metadata-type-types exact "$type_error_metadata" types
compare_raw_metadata metadata-type-where exact "$type_error_metadata" where
compare_raw_metadata metadata-type-where-json exact "$type_error_metadata" where --json
compare_raw_metadata metadata-type-config-get exact "$type_error_metadata" config get issue_prefix
compare_raw_metadata metadata-type-config-show exact "$type_error_metadata" config show
compare_raw_metadata metadata-type-config-validate exact "$type_error_metadata" config validate
compare_raw_metadata metadata-type-config-drift-json exact "$type_error_metadata" config drift --json
compare_raw_metadata metadata-type-directory-flag exact "$type_error_metadata" -C . count
# The pre-run stops before the command body reads BEADS_MAX_ROWS.
real_database_extra_env=(BEADS_MAX_ROWS=bogus)
compare_raw_metadata metadata-type-max-rows exact "$type_error_metadata" list
real_database_extra_env=(BD_JSON=1)
compare_raw_metadata metadata-type-bd-json exact "$type_error_metadata" count
real_database_extra_env=(BEADS_DIR=.beads)
compare_raw_metadata metadata-type-beads-dir exact "$type_error_metadata" count
# A store command finds its workspace even when BEADS_DB names the database.
real_database_extra_env=(BEADS_DB=.beads/embeddeddolt)
compare_raw_metadata metadata-type-beads-db exact "$type_error_metadata" count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='json: true'
compare_raw_metadata metadata-type-json-setting-where exact "$type_error_metadata" where
real_database_extra_config=""
# version and the root help print this build's own name, so only their exit and stderr compare.
compare_raw_metadata metadata-type-version stderr-only "$type_error_metadata" version
compare_raw_metadata metadata-type-version-flag stderr-only "$type_error_metadata" --version
compare_raw_metadata metadata-type-root stderr-only "$type_error_metadata"
compare_raw_metadata metadata-type-help-command exact "$type_error_metadata" help count
compare_raw_metadata metadata-type-help-flag exact "$type_error_metadata" count --help
compare_raw_metadata metadata-type-label-group exact "$type_error_metadata" label
# Go's scanner names a syntax error; a type error names the Go struct field by its tag, or the Go type.
compare_raw_metadata metadata-truncated exact '{"database":"dolt",' count
compare_raw_metadata metadata-empty exact '' count
compare_raw_metadata metadata-trailing-text exact '{"database":"dolt"} x' count
compare_raw_metadata metadata-byte-order-mark exact $'\xef\xbb\xbf{"database":"dolt"}' count
compare_raw_metadata metadata-control-character exact $'{"database":"do\x01lt"}' count
compare_raw_metadata metadata-top-array exact '[1,2]' count
compare_raw_metadata metadata-int-fraction exact '{"dolt_server_port":1.5}' count
compare_raw_metadata metadata-int-overflow exact '{"dolt_server_port":9223372036854775808}' count
compare_raw_metadata metadata-folded-key exact '{"DOLT_DATABASE":7}' count
# json.Unmarshal reports the first type error even when a later duplicate fits.
compare_raw_metadata metadata-duplicate-bad-first exact '{"dolt_database":7,"dolt_database":"test"}' count
metadata_directory() {
	rm -f "$1/work/.beads/metadata.json"
	mkdir "$1/work/.beads/metadata.json"
}
real_database_setup=metadata_directory
compare_real_database metadata-directory exact count
# Without metadata.json the load reads a legacy config.json, but the warning still names metadata.json.
legacy_config_type_error() {
	rm -f "$1/work/.beads/metadata.json"
	printf '{"database":7}\n' >"$1/work/.beads/config.json"
}
real_database_setup=legacy_config_type_error
compare_real_database metadata-legacy-type-error exact count
compare_real_database metadata-legacy-type-error-where exact where
duplicate_dolt_database() {
	jq -c . "$1/work/.beads/metadata.json" |
		sed 's/"dolt_database":"test"/"dolt_database":"other","dolt_database":"test"/' >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
real_database_setup=duplicate_dolt_database
compare_real_database metadata-duplicate-last-wins exact count
compare_real_database metadata-duplicate-last-wins-where exact where
real_database_setup=""
compare_real_database_metadata metadata-unknown-and-null-members exact '.unknown_field = {"x": [1]} | .dolt_server_host = null' count
# Upstream's pre-run opens the embedded store with CREATE DATABASE IF NOT EXISTS, so metadata.json that
# selects a database the store lacks makes upstream create it (see the candidate-only cases below).
# Dolt finds a database by its lower-case name, and json.Unmarshal matches a case-folded key and keeps
# the last duplicate, so these select the fixture's database and write nothing.
compare_real_database_metadata missing-db-case-folded-name exact '.dolt_database = "TEST"' count
compare_raw_metadata missing-db-folded-key-comments exact '{"DOLT_DATABASE":"test"}' comments "$real_database_issue_id"
# null, {} and an empty dolt_database select the default database, which exists here. The directory
# name has a capital letter that Dolt's lookup ignores.
default_database_raw_metadata() {
	mv -f "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/Beads"
	write_raw_metadata "$1"
}
real_database_setup=default_database_raw_metadata
raw_metadata='null'
compare_real_database missing-db-default-null exact count
raw_metadata='{"dolt_database":""}'
compare_real_database missing-db-default-empty-name-list-json exact list --json
real_database_setup=""
# Strict read-only mode (--readonly, or the readonly setting) opens the store without creating the
# database, so upstream fails with the open error, as text even under --json, and writes nothing.
compare_raw_metadata missing-db-readonly-count exact '{}' --readonly count
compare_real_database_metadata missing-db-readonly-other-list-json exact '.dolt_database = "other"' --readonly list --json
real_database_extra_env=(BD_READONLY=1)
compare_raw_metadata missing-db-readonly-variable-show-json exact 'null' show "$real_database_issue_id" --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='readonly: true'
compare_raw_metadata missing-db-readonly-setting-types exact '{}' types
real_database_extra_config=""
compare_real_database_metadata missing-db-readonly-case-folded-name exact '.dolt_database = "TEST"' --readonly count
# Without .beads/metadata.json (and without a legacy config.json), upstream's pre-run takes the embedded
# database `beads` for every command that opens a store. It first prints a warning on stderr, also under
# --json, the json setting, BD_JSON and the JSON envelope, and then checks --global and --database.
# It ignores BEADS_DOLT_SERVER_DATABASE there, and Dolt finds the database by its lower-case name. The
# warning names the directory that upstream selected, as a --db path gives it. `where`, `version` and
# the help pages print no warning.
remove_metadata() {
	rm -f "$1/work/.beads/metadata.json"
}
no_metadata_database=beads
no_metadata_default_database() {
	remove_metadata "$1"
	mv -f "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/$no_metadata_database"
}
real_database_setup=no_metadata_default_database
compare_real_database no-metadata-default-count exact count
compare_real_database no-metadata-default-count-json exact count --json
compare_real_database no-metadata-default-info-json exact info --json
compare_real_database no-metadata-default-types-json exact types --json
compare_real_database no-metadata-default-config-get exact config get issue_prefix
compare_real_database no-metadata-default-where exact where
compare_real_database no-metadata-default-version stderr-only version
compare_real_database no-metadata-default-help-command exact help count
compare_real_database no-metadata-default-readonly-ready-json exact --readonly ready --json
compare_real_database no-metadata-default-global exact count --global
compare_real_database no-metadata-default-database-flag-json exact count --database other --json
compare_real_database no-metadata-default-db-flag exact --db .beads/embeddeddolt count
compare_real_database no-metadata-default-directory-flag-list-json exact -C . list --json
real_database_extra_config='json: true'
compare_real_database no-metadata-default-json-setting exact count
real_database_extra_config=""
real_database_extra_env=(BD_JSON=1)
compare_real_database no-metadata-default-bd-json exact status
real_database_extra_env=(BD_JSON_ENVELOPE=1)
compare_real_database no-metadata-default-json-envelope exact list --json
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=BEADS)
compare_real_database no-metadata-default-server-database-variable exact count
real_database_extra_env=(BEADS_DIR=.beads)
compare_real_database no-metadata-default-beads-dir exact config list
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
no_metadata_database=BEADS
compare_real_database no-metadata-default-folded-directory-list-json exact list --json
no_metadata_database=beads
# Strict read-only mode opens the store without creating `beads`; --global and --database fail first.
real_database_setup=remove_metadata
compare_real_database no-metadata-missing-readonly-count exact --readonly count
compare_real_database no-metadata-missing-readonly-list-json exact --readonly list --json
compare_real_database no-metadata-missing-global-json exact count --global --json
compare_real_database no-metadata-missing-database-flag exact count --database other
real_database_setup=""
# With metadata.json, the pre-run resolves the Dolt server port instead. When BEADS_DOLT_SERVER_PORT
# (any value Go reads as a number), a positive .beads/dolt-server.port, a config.yaml in the Dolt
# directory and a positive dolt.port name none, a positive dolt_server_port in metadata.json does, and
# upstream prints a three-line deprecation warning on stderr. It comes before the --global and
# --database checks, the store open and all command output, also under --json, and leaves the exit
# code as it is. `where`, `version` and the help pages open no store and print nothing.
real_database_extra_metadata='.dolt_server_port = 3307'
compare_real_database deprecated-port-list exact list
compare_real_database deprecated-port-count-json exact count --json
compare_real_database deprecated-port-ready-json exact ready --json
compare_real_database deprecated-port-info-json exact info --json
compare_real_database deprecated-port-dep-tree exact dep tree "$real_database_issue_id"
compare_real_database deprecated-port-comments-json exact comments "$real_database_issue_id" --json
compare_real_database deprecated-port-types exact types
compare_real_database deprecated-port-config-get exact config get issue_prefix
compare_real_database deprecated-port-config-get-yaml exact config get export.auto
compare_real_database deprecated-port-config-list-json exact config list --json
compare_real_database deprecated-port-config-validate exact config validate
compare_real_database deprecated-port-where exact where
compare_real_database deprecated-port-version stderr-only version
compare_real_database deprecated-port-help-command exact help count
compare_real_database deprecated-port-help-flag exact count --help
compare_real_database deprecated-port-global exact count --global
compare_real_database deprecated-port-database-flag-json exact count --database other --json
compare_real_database deprecated-port-missing-issue exact dep tree test-missing
real_database_extra_env=(BD_JSON_ENVELOPE=1)
compare_real_database deprecated-port-json-envelope exact list --json
real_database_extra_env=(BEADS_DOLT_SERVER_PORT=3307)
compare_real_database deprecated-port-variable exact count
real_database_extra_env=(BEADS_DOLT_SERVER_PORT=0)
compare_real_database deprecated-port-variable-zero exact count
real_database_extra_env=(BEADS_DOLT_SERVER_PORT=abc)
compare_real_database deprecated-port-variable-text exact count
real_database_extra_env=(BD_DOLT_PORT=3307)
compare_real_database deprecated-port-bd-variable exact count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config=$'dolt:\n  port: 3307'
compare_real_database deprecated-port-dolt-port exact count
real_database_extra_config=$'dolt:\n  port: 0'
compare_real_database deprecated-port-dolt-port-zero exact count
real_database_extra_config=""
real_database_setup=write_server_port_file
compare_real_database deprecated-port-port-file exact count
write_zero_port_file() {
	printf '0\n' >"$1/work/.beads/dolt-server.port"
}
real_database_setup=write_zero_port_file
compare_real_database deprecated-port-port-file-zero exact count
write_dolt_config_yaml() {
	mkdir -p "$1/work/.beads/dolt"
	printf 'log_level: info\n' >"$1/work/.beads/dolt/config.yaml"
}
real_database_setup=write_dolt_config_yaml
compare_real_database deprecated-port-dolt-config exact count
real_database_setup=""
real_database_extra_metadata=""
compare_real_database_metadata deprecated-port-zero exact '.dolt_server_port = 0' count
compare_real_database_metadata deprecated-port-negative exact '.dolt_server_port = -1' count
compare_real_database_metadata deprecated-port-readonly-missing-db exact \
	'.dolt_server_port = 3307 | .dolt_database = "other"' --readonly count
real_database_read_only=""
# Upstream's show also records the issue in .beads/last-touched, so these compare without the
# read-only check; an empty new database would print a not-found error instead.
compare_real_database_metadata missing-db-case-folded-name-show exact '.dolt_database = "Test"' show "$real_database_issue_id"
real_database_setup=duplicate_dolt_database
compare_real_database missing-db-duplicate-existing-last-show exact show "$real_database_issue_id"
real_database_setup=default_database_raw_metadata
raw_metadata='{}'
compare_real_database missing-db-default-empty-object-show exact show "$real_database_issue_id"
real_database_setup=""
# BEADS_DOLT_SERVER_DATABASE names the database before metadata.json does.
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=test)
compare_raw_metadata missing-db-server-database-variable-show exact '{}' show "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A database path selection names the workspace by that path as given, or makes upstream open a
# database in another directory.
break_metadata() {
	jq '.deletions_retention_days = "7"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
candidate_only_setup=break_metadata
expect_candidate_failure metadata-db-flag-unported "" \
	"Error: count is not available yet when a database path selects a workspace whose .beads/metadata.json does not decode in this build" "" \
	--db .beads/embeddeddolt count
expect_candidate_failure metadata-db-flag-where-json-unported \
	'{"error":"where is not available yet when a database path selects a workspace whose .beads/metadata.json does not decode in this build","schema_version":1}' "" "" \
	--db .beads/embeddeddolt where --json
candidate_only_setup=""
# Upstream creates the database that metadata.json selects when the embedded store lacks it: the default
# `beads` for null, {} or no dolt_database, or the name that dolt_database, its last duplicate or
# BEADS_DOLT_SERVER_DATABASE gives. This build refuses before it opens anything.
candidate_only_setup=write_raw_metadata
raw_metadata='null'
expect_candidate_failure missing-db-null-count-unported "" \
	'Error: count is not available yet when the embedded store has no database named "beads" in this build' "" count
raw_metadata='{}'
expect_candidate_failure missing-db-empty-object-count-json-unported \
	'{"error":"count is not available yet when the embedded store has no database named \"beads\" in this build","schema_version":1}' "" "" \
	count --json
raw_metadata='{"database":"dolt","backend":"dolt","dolt_mode":"embedded","dolt_database":"other"}'
expect_candidate_failure missing-db-other-show-unported "" \
	'Error: show is not available yet when the embedded store has no database named "other" in this build' "" \
	show "$real_database_issue_id"
expect_candidate_failure missing-db-other-ready-json-unported \
	'{"error":"ready is not available yet when the embedded store has no database named \"other\" in this build","schema_version":1}' "" "" \
	ready --json
expect_candidate_failure missing-db-other-types-unported "" \
	'Error: types is not available yet when the embedded store has no database named "other" in this build' "" types
expect_candidate_failure missing-db-other-config-get-json-unported \
	'{"error":"config get is not available yet when the embedded store has no database named \"other\" in this build","schema_version":1}' "" "" \
	config get issue_prefix --json
raw_metadata='{"dolt_database":"test","dolt_database":"other"}'
expect_candidate_failure missing-db-duplicate-last-other-list-json-unported \
	'{"error":"list is not available yet when the embedded store has no database named \"other\" in this build","schema_version":1}' "" "" \
	list --json
candidate_only_setup=""
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=other)
expect_candidate_failure missing-db-server-database-variable-info-unported "" \
	'Error: info is not available yet when the embedded store has no database named "other" in this build' "" info
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Upstream keeps a redirecting workspace's dolt_database across the redirect, and so creates `other`
# here, while the store open in this build would take the target's `test`.
redirect_with_source_database() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	printf '{"dolt_database":"other"}' >"$1/work/.beads/metadata.json"
}
candidate_only_setup=redirect_with_source_database
expect_candidate_failure missing-db-redirect-source-count-unported "" \
	'Error: count is not available yet when a redirect keeps the database of the redirecting workspace in this build' "" count
candidate_only_setup=""
# Without metadata.json upstream warns and then creates `beads` when the embedded store lacks it, also
# when BEADS_DOLT_SERVER_DATABASE names the fixture's database, which upstream ignores there. This build
# prints the same warning and then refuses before it opens anything.
no_metadata_warning='warning: no beads configuration found in <work>/.beads; using default database name "beads"'
candidate_only_setup=remove_metadata
expect_candidate_failure no-metadata-missing-count-unported "" \
	"$no_metadata_warning"$'\n''Error: count is not available yet when the embedded store has no database named "beads" in this build' "" count
expect_candidate_failure no-metadata-missing-list-json-unported \
	'{"error":"list is not available yet when the embedded store has no database named \"beads\" in this build","schema_version":1}' \
	"$no_metadata_warning" "" list --json
expect_candidate_failure no-metadata-missing-info-unported "" \
	"$no_metadata_warning"$'\n''Error: info is not available yet when the embedded store has no database named "beads" in this build' "" info
expect_candidate_failure no-metadata-missing-types-unported "" \
	"$no_metadata_warning"$'\n''Error: types is not available yet when the embedded store has no database named "beads" in this build' "" types
expect_candidate_failure no-metadata-missing-config-get-json-unported \
	'{"error":"config get is not available yet when the embedded store has no database named \"beads\" in this build","schema_version":1}' \
	"$no_metadata_warning" "" config get issue_prefix --json
# A --db path names the directory as upstream derives it from the path as given: `.` for `.beads`.
expect_candidate_failure no-metadata-missing-db-flag-unported "" \
	'warning: no beads configuration found in .; using default database name "beads"'$'\n''Error: count is not available yet when the embedded store has no database named "beads" in this build' "" \
	--db .beads count
real_database_extra_env=(BD_JSON=1)
expect_candidate_failure no-metadata-missing-bd-json-unported \
	'{"error":"ready is not available yet when the embedded store has no database named \"beads\" in this build","schema_version":1}' \
	"$no_metadata_warning" "" ready
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=test)
expect_candidate_failure no-metadata-missing-server-database-variable-unported "" \
	"$no_metadata_warning"$'\n''Error: count is not available yet when BEADS_DOLT_SERVER_DATABASE names a database other than "beads" and the workspace has no .beads/metadata.json in this build' "" \
	count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Upstream reads `beads` here, but the native store open would take BEADS_DOLT_SERVER_DATABASE, or
# server mode from BEADS_DOLT_SERVER_MODE or the dolt.mode setting, which upstream ignores without
# metadata.json.
candidate_only_setup=no_metadata_default_database
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=other)
expect_candidate_failure no-metadata-default-server-database-variable-other-unported "" \
	"$no_metadata_warning"$'\n''Error: show is not available yet when BEADS_DOLT_SERVER_DATABASE names a database other than "beads" and the workspace has no .beads/metadata.json in this build' "" \
	show "$real_database_issue_id"
real_database_extra_env=(BEADS_DOLT_SERVER_MODE=1)
expect_candidate_failure no-metadata-default-server-mode-json-unported \
	'{"error":"count is not available yet when server mode is configured and the workspace has no .beads/metadata.json in this build","schema_version":1}' \
	"$no_metadata_warning" "" count --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
no_metadata_server_mode_setting() {
	no_metadata_default_database "$1"
	printf 'dolt.mode: server\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=no_metadata_server_mode_setting
expect_candidate_failure no-metadata-default-server-mode-setting-unported "" \
	"$no_metadata_warning"$'\n''Error: status is not available yet when server mode is configured and the workspace has no .beads/metadata.json in this build' "" \
	status
# For a --db path upstream takes the first .beads directory beside the path's directory or one of its
# ancestors, where this build's discovery takes the path's directory itself.
no_metadata_nested_directories() {
	no_metadata_default_database "$1"
	mkdir -p "$1/work/sub/.beads" "$1/work/sub/data"
}
candidate_only_setup=no_metadata_nested_directories
expect_candidate_failure no-metadata-db-flag-ancestor-unported "" \
	'warning: no beads configuration found in sub/.beads; using default database name "beads"'$'\n''Error: count is not available yet when --db names this path in a workspace without .beads/metadata.json in this build' "" \
	--db sub/data/x count
candidate_only_setup=""
# Upstream's show records the issue in .beads/last-touched, and a redirect adds a gate lock beside its
# target, so these compare without the read-only check. A redirect keeps the redirecting workspace's
# dolt_database only in BEADS_DOLT_SERVER_DATABASE, which upstream ignores for a target without
# metadata.json, so it reads `beads` there.
real_database_setup=no_metadata_default_database
compare_real_database no-metadata-default-show exact show "$real_database_issue_id"
redirect_to_workspace_without_metadata() {
	no_metadata_default_database "$1"
	redirect_with_source_database "$1"
}
real_database_setup=redirect_to_workspace_without_metadata
compare_real_database no-metadata-default-redirect-count-json exact count --json
real_database_setup=""
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
# Incoming reads always return related issues, including caller-supplied batches.
# Preserve anchor order and duplicates rather than flattening into raw edge rows.
compare_real_database dep-list-up-human exact dep list "$real_database_gated_molecule_id" --direction up
compare_real_database dep-list-up-json exact dep list "$real_database_gated_molecule_id" --direction=up --json
compare_real_database dep-list-up-filter-json exact dep list "$real_database_gated_molecule_id" --direction up --type parent-child --json
compare_real_database dep-list-up-filter-empty-json exact dep list "$real_database_gated_molecule_id" --direction up --type tracks --json
compare_real_database dep-list-up-empty-human exact dep list "$real_database_bug_id" --direction up
compare_real_database dep-list-up-empty-json exact dep list "$real_database_bug_id" --direction up --json
compare_real_database dep-list-up-batch-json exact dep list "$real_database_gated_molecule_id" "$real_database_epic_id" --direction up --json
compare_real_database dep-list-up-duplicate-json exact dep list "$real_database_epic_id" "$real_database_epic_id" --direction up --json
compare_real_database dep-list-up-batch-missing-json exact dep list "$real_database_epic_id" test-missing --direction up --json
compare_real_database dep-list-up-missing-json exact dep list test-missing --direction up --json
compare_real_database dep-list-up-all-missing-json exact dep list test-missing test-also-missing --direction up --json
# bd refuses cycle-closing edges, so the cycle cases write them directly into each case's fixture copy.
dependency_row="INSERT INTO dependencies (id, issue_id, depends_on_issue_id, type, created_at, created_by) VALUES"
dep_cycle_sql="$dependency_row ('fixture-cycle-1', 'test-abcd22', 'test-abcd11', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-cycle-2', '$real_database_issue_id', '$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-cycle-3', '$real_database_bug_id', '$real_database_content_id', 'conditional-blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-cycle-4', '$real_database_content_id', '$real_database_issue_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-cycle-5', '$real_database_epic_id', 'test-abcd11', 'relates-to', '2026-08-21 10:00:00', 'fixture')"
dep_partial_cycle_sql="SET FOREIGN_KEY_CHECKS = 0
$dependency_row ('fixture-ghost-1', '$real_database_child_id', 'test-ghost', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-ghost-2', 'test-ghost', '$real_database_child_id', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database dep-cycles-none exact dep cycles
compare_real_database dep-cycles-none-json exact dep cycles --json
compare_real_database_sql dep-cycles-human exact "$dep_cycle_sql" dep cycles
compare_real_database_sql dep-cycles-json exact "$dep_cycle_sql" dep cycles --json
compare_real_database_sql dep-cycles-partial-human exact "$dep_partial_cycle_sql" dep cycles
compare_real_database_sql dep-cycles-partial-json exact "$dep_partial_cycle_sql" dep cycles --json
# Upstream sorts blocked issues by priority, then created_at, after a Go map walk, and created_at
# has one-second precision, so ties come out in random order. Spread created_at by ID first.
# updated_at is ON UPDATE CURRENT_TIMESTAMP; assigning it to itself keeps the seed value, as upstream
# does for is_blocked, so the two fixture copies cannot differ by a clock tick.
distinct_created_sql="UPDATE issues SET created_at = TIMESTAMPADD(SECOND, CONV(SUBSTRING(MD5(id), 1, 6), 16, 10), '2026-01-01 00:00:00'), updated_at = updated_at
UPDATE wisps SET created_at = TIMESTAMPADD(SECOND, CONV(SUBSTRING(MD5(id), 1, 6), 16, 10), '2026-01-01 00:00:00'), updated_at = updated_at"
compare_real_database_sql blocked-human exact "$distinct_created_sql" blocked
compare_real_database_sql blocked-json exact "$distinct_created_sql" blocked --json
compare_real_database_sql blocked-parent-json exact "$distinct_created_sql" blocked --parent "$real_database_molecule_id" --json
compare_real_database_sql blocked-parent-human exact "$distinct_created_sql" blocked --parent "$real_database_molecule_id"
compare_real_database blocked-parent-none-human exact blocked --parent "$real_database_closed_id"
compare_real_database blocked-parent-none-json exact blocked --parent "$real_database_closed_id" --json
compare_real_database_sql blocked-cycle-json exact "$distinct_created_sql
$dep_cycle_sql" blocked --json
# Upstream trusts the stored is_blocked flag. Set it directly to cover several blockers in row
# order, a closed blocker that is skipped, and an issue that names its parent instead.
molecule_step_one_id="$(jq -er '.id' "$real_database_seed/molecule-step-one.json")"
blocked_flags_sql="$distinct_created_sql
$dependency_row ('fixture-block-1', '$real_database_issue_id', '$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-block-2', '$real_database_issue_id', '$real_database_epic_id', 'waits-for', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-block-3', '$real_database_issue_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
UPDATE issues SET is_blocked = 1, updated_at = updated_at WHERE id IN ('$real_database_issue_id', '$molecule_step_one_id')"
compare_real_database_sql blocked-flags-human exact "$blocked_flags_sql" blocked
compare_real_database_sql blocked-flags-json exact "$blocked_flags_sql" blocked --json
compare_real_database_sql blocked-flags-parent-json exact "$blocked_flags_sql" blocked --parent "$real_database_molecule_id" --json
# dep tree walks parent-child chains (grandchild -> child -> epic), a molecule whose second step
# blocks on the first, and a gated step whose gate is closed. Cycles come from dep_cycle_sql.
real_database_grandchild_id="$(jq -er '.id' "$real_database_seed/grandchild.json")"
molecule_step_two_id="$(jq -er '.id' "$real_database_seed/molecule-step-two.json")"
compare_real_database dep-tree-down-human exact dep tree "$real_database_grandchild_id"
compare_real_database dep-tree-down-json exact dep tree "$real_database_grandchild_id" --json
compare_real_database dep-tree-blocked-root-human exact dep tree "$molecule_step_two_id"
compare_real_database dep-tree-ready-root-human exact dep tree "$real_database_gated_step_id"
compare_real_database dep-tree-up-human exact dep tree "$real_database_epic_id" --direction up
compare_real_database dep-tree-up-json exact dep tree "$real_database_epic_id" --direction=up --json
compare_real_database dep-tree-reverse-human exact dep tree "$real_database_molecule_id" --reverse
compare_real_database dep-tree-reverse-direction-wins exact dep tree "$real_database_molecule_id" --reverse --direction down
compare_real_database dep-tree-both-human exact dep tree "$real_database_child_id" --direction both
compare_real_database dep-tree-both-json exact dep tree "$real_database_child_id" --direction both --json
compare_real_database dep-tree-depth-one-human exact dep tree "$real_database_grandchild_id" -d 1 --show-all-paths
compare_real_database dep-tree-depth-two-json exact dep tree "$real_database_grandchild_id" --max-depth=2 --json
compare_real_database dep-tree-depth-zero-human exact dep tree "$real_database_grandchild_id" --max-depth 0
compare_real_database dep-tree-depth-zero-json exact dep tree "$real_database_grandchild_id" --max-depth 0 --json
compare_real_database dep-tree-direction-bogus-human exact dep tree "$real_database_grandchild_id" --direction sideways
compare_real_database dep-tree-direction-bogus-json exact dep tree "$real_database_grandchild_id" --direction sideways --json
compare_real_database dep-tree-status-open-human exact dep tree "$real_database_gated_step_id" --status open
compare_real_database dep-tree-status-closed-json exact dep tree "$real_database_gated_step_id" --status closed --json
compare_real_database dep-tree-status-none-down exact dep tree "$real_database_gated_step_id" --status deferred
compare_real_database dep-tree-status-none-up exact dep tree "$real_database_epic_id" --direction up --status deferred
compare_real_database dep-tree-status-none-both-json exact dep tree "$real_database_child_id" --direction both --status deferred --json
compare_real_database dep-tree-status-both-root-restored exact dep tree "$real_database_gated_molecule_id" --direction both --status closed
compare_real_database dep-tree-mermaid exact dep tree "$molecule_step_two_id" --format mermaid
compare_real_database dep-tree-mermaid-both exact dep tree "$real_database_child_id" --direction both --format mermaid --json
compare_real_database dep-tree-mermaid-empty exact dep tree abcd1 --format mermaid --status deferred
compare_real_database dep-tree-format-json exact dep tree "$real_database_molecule_id" --reverse --format JSON
compare_real_database dep-tree-missing-human exact dep tree test-missing
compare_real_database dep-tree-missing-json exact dep tree test-missing --json
compare_real_database dep-tree-partial-human exact dep tree abcd1
compare_real_database dep-tree-ambiguous-json exact dep tree abcd --json
compare_real_database dep-tree-no-args exact dep tree
compare_real_database dep-tree-two-args exact dep tree "$real_database_epic_id" "$real_database_child_id"
compare_real_database dep-tree-type-flag exact dep tree "$real_database_epic_id" --type blocks
compare_real_database_sql dep-tree-cycle-human exact "$dep_cycle_sql" dep tree "$real_database_issue_id"
compare_real_database_sql dep-tree-cycle-both-human exact "$dep_cycle_sql" dep tree test-abcd11 --direction both
compare_real_database_sql dep-tree-cycle-both-json exact "$dep_cycle_sql" dep tree test-abcd11 --direction both --json
# A first child with two dependencies of its own: upstream sets the vertical connector state one
# level late, so the root's sibling list draws no vertical line and the child's list does.
compare_real_database_sql dep-tree-connectors-human exact \
	"$dependency_row ('fixture-tree-1', '$real_database_molecule_id', '$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-tree-2', '$real_database_molecule_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')" \
	dep tree "$molecule_step_two_id"
compare_real_database_env dep-tree-json-envelope exact BD_JSON_ENVELOPE=1 dep tree "$real_database_grandchild_id" --json
compare_real_database dep-tree-max-rows-human exact dep tree "$real_database_grandchild_id" --max-rows 2
compare_real_database dep-tree-max-rows-json exact dep tree "$real_database_grandchild_id" --max-rows 3 --json
compare_real_database dep-tree-max-rows-negative-json exact dep tree "$real_database_grandchild_id" --max-rows -1 --json
compare_real_database_env dep-tree-max-rows-env exact BEADS_MAX_ROWS=1 dep tree "$real_database_grandchild_id"
compare_real_database_env dep-tree-max-rows-env-flag-zero exact BEADS_MAX_ROWS=1 dep tree "$real_database_grandchild_id" --max-rows 0
compare_real_database_env dep-tree-max-rows-env-malformed exact BEADS_MAX_ROWS=banana dep tree test-missing
# graph check walks the blocking edges from roots in Go map order, so a cycle with two or more
# members prints in random order. A self-loop is stable, and so is a cycle whose other members
# have no record: upstream drops them, and drops a cycle with no recorded member at all.
graph_self_loop_sql="$dependency_row ('fixture-self-1', '$real_database_issue_id', '$real_database_issue_id', 'blocks', '2026-08-21 10:00:00', 'fixture')"
graph_ghost_cycle_sql="$dep_partial_cycle_sql
$dependency_row ('fixture-ghost-3', 'test-ghost-self', 'test-ghost-self', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database graph-check-clean-human exact graph check
compare_real_database graph-check-clean-json exact graph check --json
compare_real_database graph-check-extra-arg exact graph check "$real_database_issue_id"
compare_real_database_env graph-check-json-envelope exact BD_JSON_ENVELOPE=1 graph check --json
compare_real_database_sql graph-check-self-loop-human exact "$graph_self_loop_sql" graph check
compare_real_database_sql graph-check-self-loop-json exact "$graph_self_loop_sql" graph check --json
compare_real_database_sql graph-check-ghost-human exact "$graph_ghost_cycle_sql" graph check
compare_real_database_sql graph-check-ghost-json exact "$graph_ghost_cycle_sql" graph check --json
# graph <id> walks every dependency type both ways from the root, then lays the nodes out by
# `blocks` edges only, lifts children to their parent's layer and sorts each layer, so upstream's
# Go map order reaches the output only where a case below says so. Every single-issue view is
# ported; --all is not.
graph_lift_sql="$dependency_row ('fixture-graph-1', '$real_database_epic_id', '$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')"
graph_external_row="INSERT INTO dependencies (id, issue_id, depends_on_external, type, created_at, created_by) VALUES"
graph_external_sql="$graph_external_row ('fixture-graph-2', '$real_database_issue_id', 'external:other:$real_database_labeled_relation_id', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database graph-hierarchy-json exact graph "$real_database_child_id" --json
compare_real_database graph-epic-json exact graph "$real_database_epic_id" --json
compare_real_database graph-blockers-json exact graph "$molecule_step_two_id" --json
compare_real_database graph-molecule-json exact graph "$real_database_molecule_id" --json
compare_real_database graph-gated-json exact graph "$real_database_gated_step_id" --json
compare_real_database graph-metadata-json exact graph "$real_database_issue_id" --json
compare_real_database graph-isolated-json exact graph "$real_database_bug_id" --json
compare_real_database graph-escaping-json exact graph "$real_database_escaping_id" --json
compare_real_database graph-format-json exact graph "$real_database_epic_id" --format json
compare_real_database graph-view-flags-json exact graph "$real_database_epic_id" --json --compact --box=true --dot --html
compare_real_database_env graph-json-envelope exact BD_JSON_ENVELOPE=1 graph "$real_database_issue_id" --json
compare_real_database_env graph-json-envelope-layers exact BD_JSON_ENVELOPE=1 graph "$real_database_child_id" --json
compare_real_database_sql graph-lift-json exact "$graph_lift_sql" graph "$real_database_grandchild_id" --json
compare_real_database_sql graph-cycle-json exact "$dep_cycle_sql" graph test-abcd11 --json
compare_real_database_sql graph-conditional-json exact "$dep_cycle_sql" graph "$real_database_issue_id" --json
compare_real_database_sql graph-external-json exact "$graph_external_sql" graph "$real_database_issue_id" --json
# A wisp keeps its rows in the wisp tables; the walk and the row reads route by wisp status.
graph_wisp_record="$(jq -nc --arg bug "$real_database_bug_id" --arg epic "$real_database_epic_id" '{
	id: "test-graph-wisp", title: "Graph wisp step", status: "open", priority: 2, issue_type: "task",
	created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z", ephemeral: true, labels: ["wisp-label"],
	dependencies: [
		{issue_id: "test-graph-wisp", depends_on_id: $bug, type: "blocks", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"},
		{issue_id: "test-graph-wisp", depends_on_id: $epic, type: "parent-child", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}
	]}')"
compare_real_database_import graph-wisp-json exact "$graph_wisp_record" graph test-graph-wisp --json
compare_real_database_import graph-wisp-dependent-json exact "$graph_wisp_record" graph "$real_database_bug_id" --json
compare_real_database graph-missing-human exact graph test-missing
compare_real_database graph-missing-json exact graph test-missing --json
compare_real_database graph-partial-json exact graph abcd1 --json
compare_real_database graph-ambiguous-json exact graph abcd --json
compare_real_database graph-no-args exact graph
compare_real_database graph-no-args-json exact graph --json
compare_real_database_env graph-no-args-envelope exact BD_JSON_ENVELOPE=1 graph --json
compare_real_database graph-two-args exact graph "$real_database_epic_id" "$real_database_child_id" --json
compare_real_database graph-all-with-id exact graph --all "$real_database_epic_id"
compare_real_database graph-all-with-id-json exact graph "$real_database_epic_id" --all --json
compare_real_database graph-unknown-flag exact graph "$real_database_epic_id" --status open
compare_real_database graph-view-flag-invalid exact graph "$real_database_epic_id" --dot=maybe
compare_real_database graph-check-view-flag exact graph check --compact
compare_real_database graph-max-rows-json exact graph "$real_database_epic_id" --max-rows 4 --json
compare_real_database graph-max-rows-fits-json exact graph "$real_database_molecule_id" --max-rows=3 --json
compare_real_database graph-max-rows-negative-json exact graph "$real_database_epic_id" --max-rows -1 --json
compare_real_database graph-max-rows-negative-missing exact graph test-missing --max-rows=-1
compare_real_database graph-max-rows-malformed exact graph "$real_database_epic_id" --max-rows x
compare_real_database_env graph-max-rows-env exact BEADS_MAX_ROWS=2 graph "$real_database_molecule_id" --json
compare_real_database_env graph-max-rows-env-flag-zero exact BEADS_MAX_ROWS=1 graph "$real_database_molecule_id" --max-rows 0 --json
compare_real_database_env graph-max-rows-env-malformed exact BEADS_MAX_ROWS=banana graph "$real_database_bug_id" --json
compare_real_database_env graph-max-rows-env-malformed-missing exact BEADS_MAX_ROWS=banana graph test-missing
# The human views reuse the same load and layout. graph_views_sql gives every status color, a
# blocker that is the root, edges that the views skip, and titles with a quote, a backslash, a
# tab, multibyte text and more than 40 characters. graph_empty_layer_sql lifts the only layer-0
# node into its parent's layer; graph_narrow_sql makes titles shorter than the IDs.
graph_pinned_id="$(jq -er '.id' "$real_database_seed/pinned.json")"
graph_views_sql="$dependency_row ('fixture-view-1', '$real_database_bug_id', '$real_database_progress_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-2', '$real_database_bug_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-3', '$real_database_bug_id', '$graph_pinned_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-4', '$real_database_content_id', '$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-5', '$real_database_content_id', '$real_database_progress_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-6', '$real_database_escaping_id', '$real_database_content_id', 'parent-child', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-7', '$real_database_labeled_relation_id', '$real_database_bug_id', 'relates-to', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-8', '$real_database_progress_id', '$real_database_closed_id', 'waits-for', '2026-08-21 10:00:00', 'fixture')
UPDATE issues SET status = 'blocked', updated_at = updated_at WHERE id = '$real_database_content_id'
UPDATE issues SET status = 'deferred', updated_at = updated_at WHERE id = '$real_database_escaping_id'
UPDATE issues SET status = 'hooked', updated_at = updated_at WHERE id = '$real_database_labeled_relation_id'
UPDATE issues SET title = 'Say \"hi\" to C:\\\\temp and keep going well past forty characters', updated_at = updated_at WHERE id = '$real_database_issue_id'
UPDATE issues SET title = 'Tab\\there in progress', updated_at = updated_at WHERE id = '$real_database_progress_id'
UPDATE issues SET title = 'Ünïcödé closed títle with ✓ marks and many more words', updated_at = updated_at WHERE id = '$real_database_closed_id'"
graph_empty_layer_sql="$dependency_row ('fixture-view-9', '$real_database_bug_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-10', '$real_database_closed_id', '$real_database_bug_id', 'parent-child', '2026-08-21 10:00:00', 'fixture')"
graph_narrow_sql="$dependency_row ('fixture-view-11', '$real_database_bug_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$dependency_row ('fixture-view-12', '$real_database_content_id', '$real_database_closed_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
UPDATE issues SET title = '', updated_at = updated_at WHERE id IN ('$real_database_bug_id', '$real_database_content_id')
UPDATE issues SET title = 'C', updated_at = updated_at WHERE id = '$real_database_closed_id'"
# --dot prints one invisible cluster per layer, then each blocks and parent-child row in load
# order. Only --open outranks it among the view flags.
compare_real_database graph-hierarchy-dot exact graph "$real_database_child_id" --dot
compare_real_database graph-blockers-dot exact graph "$molecule_step_two_id" --dot
compare_real_database graph-molecule-dot exact graph "$real_database_molecule_id" --dot
compare_real_database graph-gated-dot exact graph "$real_database_gated_step_id" --dot
compare_real_database graph-metadata-dot exact graph "$real_database_issue_id" --dot
compare_real_database graph-isolated-dot exact graph "$real_database_bug_id" --dot
compare_real_database graph-escaping-dot exact graph "$real_database_escaping_id" --dot
compare_real_database graph-dot-wins exact graph "$real_database_epic_id" --box --html --compact=true --dot
compare_real_database graph-dot-missing exact graph test-missing --dot
compare_real_database graph-dot-no-args exact graph --dot
compare_real_database graph-dot-max-rows exact graph "$real_database_epic_id" --max-rows 2 --dot
compare_real_database_sql graph-views-dot exact "$graph_views_sql" graph "$real_database_bug_id" --dot
compare_real_database_sql graph-empty-layer-dot exact "$graph_empty_layer_sql" graph "$real_database_bug_id" --dot
compare_real_database_sql graph-narrow-dot exact "$graph_narrow_sql" graph "$real_database_bug_id" --dot
compare_real_database_sql graph-lift-dot exact "$graph_lift_sql" graph "$real_database_grandchild_id" --dot
compare_real_database_sql graph-cycle-dot exact "$dep_cycle_sql" graph test-abcd11 --dot
compare_real_database_sql graph-external-dot exact "$graph_external_sql" graph "$real_database_issue_id" --dot
compare_real_database_import graph-wisp-dot exact "$graph_wisp_record" graph test-graph-wisp --dot
# --box sizes every box from the longest title cut to 30 characters and counted in UTF-8 bytes,
# cuts an ID that does not fit, turns a tab into four spaces in a title that is not open, and
# counts blocks/needs without the rows whose blocker is the root. Every other view flag but
# --json outranks it.
compare_real_database graph-hierarchy-box exact graph "$real_database_child_id" --box
compare_real_database graph-blockers-box exact graph "$molecule_step_two_id" --box
compare_real_database graph-molecule-box exact graph "$real_database_molecule_id" --box
compare_real_database graph-gated-box exact graph "$real_database_gated_step_id" --box
compare_real_database graph-metadata-box exact graph "$real_database_issue_id" --box
compare_real_database graph-isolated-box exact graph "$real_database_bug_id" --box
compare_real_database graph-escaping-box exact graph "$real_database_escaping_id" --box
compare_real_database graph-box-explicit exact graph "$real_database_epic_id" --dot=false --box=true
compare_real_database graph-box-missing exact graph test-missing --box
compare_real_database_env graph-box-max-rows-env-malformed exact BEADS_MAX_ROWS=banana graph "$real_database_bug_id" --box
compare_real_database_sql graph-views-box exact "$graph_views_sql" graph "$real_database_bug_id" --box
compare_real_database_sql graph-empty-layer-box exact "$graph_empty_layer_sql" graph "$real_database_bug_id" --box
compare_real_database_sql graph-narrow-box exact "$graph_narrow_sql" graph "$real_database_bug_id" --box
compare_real_database_sql graph-lift-box exact "$graph_lift_sql" graph "$real_database_grandchild_id" --box
compare_real_database_sql graph-cycle-box exact "$dep_cycle_sql" graph test-abcd11 --box
compare_real_database_sql graph-external-box exact "$graph_external_sql" graph "$real_database_issue_id" --box
compare_real_database_import graph-wisp-box exact "$graph_wisp_record" graph test-graph-wisp --box
# Without a view flag, graph draws each layer as a column of boxes and routes each blocks row
# from an earlier layer through the six-column gutters to its right, one channel per row change.
# A box fits the longest title cut to 22 characters (counted in runes) and the longest ID
# (counted in bytes) with its priority, and is at least 18 wide. The records below give the
# gutters fixed IDs, so each shape is the same on every run: edges that cross, several edges
# that merge into one node, edges that skip a layer (also past an empty row), and a wide fan-out
# whose channels share columns.
# graph_record ID TITLE STATUS PRIORITY [BLOCKER...] prints one issue that each BLOCKER blocks.
graph_record() {
	local id="$1" title="$2" status="$3" priority="$4"
	shift 4
	jq -nc --arg id "$id" --arg title "$title" --arg status "$status" --argjson priority "$priority" '{
		id: $id, title: $title, status: $status, priority: $priority, issue_type: "task",
		created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z",
		dependencies: [$ARGS.positional[] | {issue_id: $id, depends_on_id: ., type: "blocks",
			created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]}' --args "$@"
}
graph_crossing_records="$(
	graph_record test-gv-a "Cross source A" open 1
	graph_record test-gv-b "Cross source B" in_progress 2
	graph_record test-gv-c "Cross target C" open 2 test-gv-b test-gv-a
	graph_record test-gv-d "Cross target D" blocked 3 test-gv-a
	graph_record test-gv-e "Cross target E" deferred 4 test-gv-b
)"
graph_merge_records="$(
	graph_record test-gm-s1 "Merge source one" open 2
	graph_record test-gm-s2 "Merge source two" open 2
	graph_record test-gm-s3 "Merge source three" open 2
	graph_record test-gm-s4 "Merge source four" open 2
	graph_record test-gm-t "Merge target" open 1 test-gm-s1 test-gm-s2 test-gm-s3 test-gm-s4
	graph_record test-gm-u "Second merge target" open 1 test-gm-s4 test-gm-s1
)"
graph_skip_records="$(
	graph_record test-gs-a "Skip start" open 2
	graph_record test-gs-z "Skip other start" open 2
	graph_record test-gs-b "Skip middle" open 2 test-gs-a
	graph_record test-gs-y "Skip other middle" open 2 test-gs-z
	graph_record test-gs-c "Skip end" open 2 test-gs-b test-gs-z
	graph_record test-gs-x "Skip other end" open 2 test-gs-y test-gs-a
	graph_record test-gs-xz "Skip past an empty row" open 2 test-gs-y test-gs-a
	graph_record test-gs-w "Skip three layers" open 2 test-gs-c test-gs-z
)"
graph_fan_records="$(
	graph_record test-gf-0 "Fan root" open 0
	graph_record test-gf-9 "Second fan source" open 1
	graph_record test-gf-1 "Fan target one with a title long enough to cut" open 2 test-gf-0 test-gf-9
	graph_record test-gf-2 "Fan target two" open 2 test-gf-0
	graph_record test-gf-3 "Fan target three" open 2 test-gf-0
	graph_record test-gf-4 "Fan target four" open 2 test-gf-0
	graph_record test-gf-5 "Fan target five" open 2 test-gf-0
	graph_record test-gf-6 "Fan target six" open 2 test-gf-0 test-gf-9
)"
compare_real_database graph-hierarchy-visual exact graph "$real_database_child_id"
compare_real_database graph-epic-visual exact graph "$real_database_epic_id"
compare_real_database graph-blockers-visual exact graph "$molecule_step_two_id"
compare_real_database graph-molecule-visual exact graph "$real_database_molecule_id"
compare_real_database graph-gated-visual exact graph "$real_database_gated_step_id"
compare_real_database graph-metadata-visual exact graph "$real_database_issue_id"
compare_real_database graph-isolated-visual exact graph "$real_database_bug_id"
compare_real_database graph-escaping-visual exact graph "$real_database_escaping_id"
compare_real_database graph-visual-partial exact graph abcd1
compare_real_database graph-visual-explicit exact graph "$real_database_epic_id" --dot=false --box=false --compact=false --html=false
compare_real_database graph-visual-max-rows exact graph "$real_database_epic_id" --max-rows 2
compare_real_database_env graph-visual-max-rows-env-malformed exact BEADS_MAX_ROWS=banana graph "$real_database_bug_id"
compare_real_database_sql graph-views-visual exact "$graph_views_sql" graph "$real_database_bug_id"
compare_real_database_sql graph-empty-layer-visual exact "$graph_empty_layer_sql" graph "$real_database_bug_id"
compare_real_database_sql graph-narrow-visual exact "$graph_narrow_sql" graph "$real_database_bug_id"
compare_real_database_sql graph-lift-visual exact "$graph_lift_sql" graph "$real_database_grandchild_id"
compare_real_database_sql graph-cycle-visual exact "$dep_cycle_sql" graph test-abcd11
compare_real_database_sql graph-external-visual exact "$graph_external_sql" graph "$real_database_issue_id"
compare_real_database_import graph-wisp-visual exact "$graph_wisp_record" graph test-graph-wisp
compare_real_database_import graph-crossing-visual exact "$graph_crossing_records" graph test-gv-a
compare_real_database_import graph-merge-visual exact "$graph_merge_records" graph test-gm-t
compare_real_database_import graph-skip-visual exact "$graph_skip_records" graph test-gs-a
compare_real_database_import graph-fan-out-visual exact "$graph_fan_records" graph test-gf-0
# --compact prints one line per issue under its layer. Below each parent it prints the parent's
# children again, to any depth, sorted by priority and then by ID, with numeric ID segments
# compared as numbers. A title is cut to 50 characters, and a closed issue's tab turns into four
# spaces. --compact outranks only --box.
# graph_tree_record ID TITLE STATUS PRIORITY TYPE [DEPENDENCY_TYPE=TARGET...] prints one issue
# that depends on each TARGET through DEPENDENCY_TYPE.
graph_tree_record() {
	local id="$1" title="$2" status="$3" priority="$4" type="$5"
	shift 5
	jq -nc --arg id "$id" --arg title "$title" --arg status "$status" --argjson priority "$priority" --arg type "$type" '{
		id: $id, title: $title, status: $status, priority: $priority, issue_type: $type,
		created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z",
		dependencies: [$ARGS.positional[] | split("=") | {issue_id: $id, depends_on_id: .[1], type: .[0],
			created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]}
		+ if $status == "closed" then {closed_at: "2026-08-21T12:00:00Z"} else {} end' --args "$@"
}
graph_compact_records="$(
	graph_tree_record test-gc-root "Compact root epic" open 1 epic blocks=test-gc-blocker
	graph_tree_record test-gc-blocker "Blocks the root" open 3 task
	graph_tree_record test-gc-2 "Child two" open 2 task parent-child=test-gc-root
	graph_tree_record test-gc-10 "Child ten" blocked 2 task parent-child=test-gc-root
	graph_tree_record test-gc-1 "Urgent child" in_progress 0 task parent-child=test-gc-root
	graph_tree_record test-gc-2.1 $'Closed\tgrandchild with a tab' closed 3 task parent-child=test-gc-2
	graph_tree_record test-gc-2.10 "Grandchild ten" open 2 task parent-child=test-gc-2
	graph_tree_record test-gc-2.9 "Grandchild nine" deferred 2 task parent-child=test-gc-2
	graph_tree_record test-gc-10.1 "Ünïcödé grandchild title that runs well past the fifty rune limit" open 4 task \
		parent-child=test-gc-10
	graph_tree_record test-gc-10.1.1 $'Open\tgreat-grandchild' open 1 task parent-child=test-gc-10.1
)"
compare_real_database graph-hierarchy-compact exact graph "$real_database_child_id" --compact
compare_real_database graph-epic-compact exact graph "$real_database_epic_id" --compact
compare_real_database graph-blockers-compact exact graph "$molecule_step_two_id" --compact
compare_real_database graph-molecule-compact exact graph "$real_database_molecule_id" --compact
compare_real_database graph-gated-compact exact graph "$real_database_gated_step_id" --compact
compare_real_database graph-metadata-compact exact graph "$real_database_issue_id" --compact
compare_real_database graph-isolated-compact exact graph "$real_database_bug_id" --compact
compare_real_database graph-escaping-compact exact graph "$real_database_escaping_id" --compact
compare_real_database graph-compact-over-box exact graph "$real_database_epic_id" --box --compact=true
compare_real_database graph-compact-max-rows exact graph "$real_database_epic_id" --max-rows 2 --compact
compare_real_database_sql graph-views-compact exact "$graph_views_sql" graph "$real_database_bug_id" --compact
compare_real_database_sql graph-empty-layer-compact exact "$graph_empty_layer_sql" graph "$real_database_bug_id" --compact
compare_real_database_sql graph-narrow-compact exact "$graph_narrow_sql" graph "$real_database_bug_id" --compact
compare_real_database_sql graph-lift-compact exact "$graph_lift_sql" graph "$real_database_grandchild_id" --compact
compare_real_database_sql graph-cycle-compact exact "$dep_cycle_sql" graph test-abcd11 --compact
compare_real_database_sql graph-external-compact exact "$graph_external_sql" graph "$real_database_issue_id" --compact
compare_real_database_import graph-wisp-compact exact "$graph_wisp_record" graph test-graph-wisp --compact
compare_real_database_import graph-tree-compact exact "$graph_compact_records" graph test-gc-root --compact
# --open keeps the open, in_progress and blocked issues and prints them as --compact does. Each
# kept issue also blocks every kept issue that it reaches through `blocks` rows over issues left
# out. Other rows stay when both ends are kept. When the root is left out, the first issue with
# the lowest priority number becomes the root. --open outranks every view flag; with --json it
# prints the filtered graph. Upstream adds the joined rows in Go map order, so an issue with two
# or more of them lists its DependsOn in random order: graph-open-json sorts those lists.
graph_open_records="$(
	graph_tree_record test-go-p "Open parent epic" open 1 epic
	graph_tree_record test-go-a "Open source A" open 2 task parent-child=test-go-p
	graph_tree_record test-go-b "Closed middle B" closed 2 task blocks=test-go-a
	graph_tree_record test-go-c "Open target C" open 2 task blocks=test-go-b blocks=test-go-d parent-child=test-go-p
	graph_tree_record test-go-d "Deferred D" deferred 3 task
	graph_tree_record test-go-e "In progress E" in_progress 1 task blocks=test-go-d
	graph_tree_record test-go-x "Closed child X" closed 2 task parent-child=test-go-p
	graph_tree_record test-go-f "Blocked F" blocked 1 task blocks=test-go-c blocks=test-go-a
	graph_tree_record test-go-g "Closed chain G" closed 3 task blocks=test-go-c
	graph_tree_record test-go-g2 "Hooked chain G2" hooked 3 task blocks=test-go-g
	graph_tree_record test-go-h "Open after the chain" open 1 task blocks=test-go-g2
)"
graph_open_join_records="$(
	graph_tree_record test-goj-a "Join source A" open 2 task
	graph_tree_record test-goj-e "Join source E" in_progress 1 task
	graph_tree_record test-goj-b "Closed join B" closed 2 task blocks=test-goj-a blocks=test-goj-e
	graph_tree_record test-goj-c "Join target C" open 2 task blocks=test-goj-b
)"
compare_real_database_import graph-open-compact exact "$graph_open_records" graph test-go-p --open
compare_real_database_import graph-open-json exact "$graph_open_records" graph test-go-p --open --json
compare_real_database_import graph-open-closed-root exact "$graph_open_records" graph test-go-b --open
compare_real_database_import graph-open-closed-root-json exact "$graph_open_records" graph test-go-b --open --json
compare_real_database_import graph-open-over-views exact "$graph_open_records" graph test-go-p --dot --html --box --compact --open
compare_real_database_import graph-open-join exact "$graph_open_join_records" graph test-goj-c --open
compare_real_database_import graph-open-join-json graph-open-json "$graph_open_join_records" graph test-goj-c --open --json
compare_real_database graph-open-epic exact graph "$real_database_epic_id" --open
compare_real_database graph-open-gated exact graph "$real_database_gated_step_id" --open=true
compare_real_database graph-open-none exact graph "$real_database_closed_id" --open
compare_real_database graph-open-none-json exact graph "$real_database_closed_id" --open --json
compare_real_database graph-open-max-rows exact graph "$real_database_epic_id" --max-rows 2 --open
compare_real_database_env graph-open-json-envelope exact BD_JSON_ENVELOPE=1 graph "$real_database_child_id" --open --json
compare_real_database_sql graph-views-open exact "$graph_views_sql" graph "$real_database_bug_id" --open
compare_real_database_sql graph-views-open-json exact "$graph_views_sql" graph "$real_database_bug_id" --open --json
compare_real_database_sql graph-cycle-open exact "$dep_cycle_sql" graph test-abcd11 --open
# --html fills upstream's page template: the root's title and ID, HTML-escaped, in <title>, then
# one JSON node per issue with its layer and one JSON link per blocks or parent-child row, from
# the blocker. Upstream lists the nodes in Go map order, so graph-html sorts them; the page of a
# graph with one issue is the same every time. --html outranks --compact and --box.
graph_html_title_sql="UPDATE issues SET title = 'Quote \" it''s <b> & a\\ttab', updated_at = updated_at WHERE id = '$real_database_closed_id'"
compare_real_database graph-isolated-html exact graph "$real_database_bug_id" --html
compare_real_database graph-escaping-html exact graph "$real_database_escaping_id" --html
compare_real_database_sql graph-title-html exact "$graph_html_title_sql" graph "$real_database_closed_id" --html
compare_real_database graph-hierarchy-html graph-html graph "$real_database_child_id" --html
compare_real_database graph-epic-html graph-html graph "$real_database_epic_id" --html
compare_real_database graph-blockers-html graph-html graph "$molecule_step_two_id" --html
compare_real_database graph-molecule-html graph-html graph "$real_database_molecule_id" --html
compare_real_database graph-gated-html graph-html graph "$real_database_gated_step_id" --html
compare_real_database graph-metadata-html graph-html graph "$real_database_issue_id" --html
compare_real_database graph-html-over-compact graph-html graph "$real_database_epic_id" --box --compact --html=true
compare_real_database graph-html-max-rows exact graph "$real_database_epic_id" --max-rows 2 --html
compare_real_database graph-html-missing exact graph test-missing --html
compare_real_database_sql graph-views-html graph-html "$graph_views_sql" graph "$real_database_bug_id" --html
compare_real_database_sql graph-lift-html graph-html "$graph_lift_sql" graph "$real_database_grandchild_id" --html
compare_real_database_sql graph-cycle-html graph-html "$dep_cycle_sql" graph test-abcd11 --html
compare_real_database_sql graph-external-html graph-html "$graph_external_sql" graph "$real_database_issue_id" --html
compare_real_database_import graph-wisp-html graph-html "$graph_wisp_record" graph test-graph-wisp --html
compare_real_database_import graph-tree-html graph-html "$graph_compact_records" graph test-gc-root --html
# graph --all searches the open, in_progress and blocked issues (and wisps), joins them into
# connected groups and prints every group, the largest first and then by the priority of the
# group's first issue. Upstream orders the groups with Go's sort.Slice, which is not stable for
# more than 12 groups. The shared seed has more than 12 groups, but its random IDs and creation
# times change the search order on every run, so graph_all_records adds 19 groups with fixed IDs
# and times, and graph_all_sql takes every other issue out. They cover tied groups, an epic root,
# a wisp that the search merges between the issues by priority and creation time, labels, a row
# with metadata, other dependency types joining a group, a row to a closed issue that is left
# out, and an external row that names a loaded issue next to a direct row to the same issue,
# which only --open drops. Only --open outranks --html, and --html outranks --dot; --html joins
# the groups into one page.
graph_all_record() {
	local id="$1" title="$2" status="$3" priority="$4" type="$5" created="$6"
	shift 6
	jq -nc --arg id "$id" --arg title "$title" --arg status "$status" --argjson priority "$priority" --arg type "$type" \
		--arg created "$created" '{
		id: $id, title: $title, status: $status, priority: $priority, issue_type: $type,
		created_at: $created, updated_at: "2026-08-21T13:00:00Z",
		dependencies: [$ARGS.positional[] | split("=") | {issue_id: $id, depends_on_id: .[1], type: .[0],
			created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]}' --args "$@"
}
graph_all_records="$(
	graph_all_record test-ga-epic "All epic root" open 3 epic 2026-08-20T12:00:00Z
	graph_all_record test-ga-e1 "Epic child in progress" in_progress 0 task 2026-08-20T12:00:01Z parent-child=test-ga-epic
	graph_all_record test-ga-e2 "Epic child blocked" blocked 1 task 2026-08-20T12:00:02Z parent-child=test-ga-epic blocks=test-ga-e1
	graph_all_record test-ga-b1 "Chain start" open 3 task 2026-08-20T12:00:03Z
	graph_all_record test-ga-b2 "Chain middle" open 1 task 2026-08-20T12:00:04Z blocks=test-ga-b1
	graph_all_record test-ga-b3 "Chain end" open 1 bug 2026-08-20T12:00:05Z blocks=test-ga-b2
	graph_all_record test-ga-c1 "Created with the wisp" open 2 task 2026-08-20T12:00:06Z
	graph_all_record test-ga-r1 "Related one" open 2 task 2026-08-20T12:00:07Z relates-to=test-ga-r2
	graph_all_record test-ga-r2 "Related two" in_progress 2 feature 2026-08-20T12:00:08Z
	graph_all_record test-ga-x "Blocked by a closed issue" open 2 task 2026-08-20T12:00:09Z blocks=test-ga-closed
	graph_all_record test-ga-closed "Closed and left out" closed 2 task 2026-08-20T12:00:10Z |
		jq -c '. + {closed_at: "2026-08-21T12:00:00Z"}'
	graph_all_record test-ga-y "Also blocked by the closed issue" open 2 task 2026-08-20T12:00:11Z blocks=test-ga-closed
	for index in 1 2 3 4 5 6 7 8 9 10 11 12; do
		priorities=(2 1 3 2 1 0 2 2 1 3 2 2)
		statuses=(open open blocked open in_progress open open blocked open open in_progress open)
		graph_all_record "test-ga-s$index" "Singleton $index" "${statuses[index - 1]}" "${priorities[index - 1]}" task \
			"2026-08-20T11:00:$(printf '%02d' "$((index % 5))")Z"
	done
	jq -nc '{id: "test-ga-wisp", title: "Wisp among tied singletons", status: "open", priority: 2, issue_type: "task",
		created_at: "2026-08-20T12:00:06Z", updated_at: "2026-08-21T13:00:00Z", ephemeral: true, labels: ["wisp-label"]}'
	jq -nc '{id: "test-ga-labeled", title: "Labeled singleton <b>", status: "open", priority: 2, issue_type: "task",
		created_at: "2026-08-20T11:00:00Z", updated_at: "2026-08-21T13:00:00Z", labels: ["zeta", "alpha"],
		description: "Body & more", metadata: {"z": 1, "a": [true, null]}}'
)"
graph_all_sql="UPDATE issues SET status = 'deferred', updated_at = updated_at WHERE id NOT LIKE 'test-ga-%' AND status IN ('open', 'in_progress', 'blocked')
UPDATE wisps SET status = 'deferred', updated_at = updated_at WHERE id NOT LIKE 'test-ga-%' AND status IN ('open', 'in_progress', 'blocked')
$graph_external_row ('fixture-ga-1', 'test-ga-b3', 'external:other:test-ga-b2', 'blocks', '2026-08-21 10:00:00', 'fixture')
INSERT INTO dependencies (id, issue_id, depends_on_issue_id, type, created_at, created_by, metadata, thread_id) VALUES ('fixture-ga-2', 'test-ga-r2', 'test-ga-y', 'replies-to', '2026-08-21 11:00:00', 'fixture', '{\"note\":\"<x>\"}', 'thread-1')"
graph_all_empty_sql="UPDATE issues SET status = 'deferred', updated_at = updated_at WHERE status IN ('open', 'in_progress', 'blocked')
UPDATE wisps SET status = 'deferred', updated_at = updated_at WHERE status IN ('open', 'in_progress', 'blocked')"
# compare_graph_all NAME COMPARISON ARGS... runs a case on graph_all_records after graph_all_sql.
compare_graph_all() {
	local name="$1" comparison="$2"
	shift 2
	real_database_extra_sql="$graph_all_sql"
	compare_real_database_import "$name" "$comparison" "$graph_all_records" "$@"
	real_database_extra_sql=""
}
compare_graph_all graph-all-groups-json exact graph --all --json
compare_graph_all graph-all-groups-visual exact graph --all
compare_graph_all graph-all-groups-compact exact graph --all --compact
compare_graph_all graph-all-groups-box exact graph --all --box
compare_graph_all graph-all-groups-dot exact graph --all --dot
compare_graph_all graph-all-groups-html graph-html graph --all --html
compare_graph_all graph-all-groups-open exact graph --all --open
compare_graph_all graph-all-groups-open-json exact graph --all --open --json
compare_graph_all graph-all-html-over-dot graph-html graph --all --dot --html --box
compare_graph_all graph-all-dot-over-compact exact graph --all --compact --box --dot=true
compare_graph_all graph-all-compact-over-box exact graph --all --box --compact
compare_graph_all graph-all-open-over-html exact graph --all --html --dot --open
compare_graph_all graph-all-json-over-views exact graph --all --html --open --json
compare_graph_all graph-all-groups-max-rows exact graph --all --max-rows 17
compare_graph_all graph-all-groups-max-rows-fits-json exact graph --all --max-rows=18 --json
compare_real_database graph-all-json exact graph --all --json
compare_real_database graph-all-visual exact graph --all
compare_real_database graph-all-compact exact graph --all --compact
compare_real_database graph-all-box exact graph --all --box
compare_real_database graph-all-dot exact graph --all --dot
compare_real_database graph-all-html graph-html graph --all --html
compare_real_database graph-all-open exact graph --all --open
compare_real_database_env graph-all-json-envelope exact BD_JSON_ENVELOPE=1 graph --all --json
compare_real_database_import graph-all-wisp-json exact "$graph_wisp_record" graph --all --json
compare_real_database_sql graph-all-views-json exact "$graph_views_sql" graph --all --json
compare_real_database_sql graph-all-views-visual exact "$graph_views_sql" graph --all
compare_real_database_sql graph-all-cycle-compact exact "$dep_cycle_sql" graph --all --compact
compare_real_database_sql graph-all-cycle-json exact "$dep_cycle_sql" graph --all --json
compare_real_database_sql graph-all-empty exact "$graph_all_empty_sql" graph --all
compare_real_database_sql graph-all-empty-json exact "$graph_all_empty_sql" graph --all --json
compare_real_database_sql graph-all-empty-html exact "$graph_all_empty_sql" graph --all --html
compare_real_database graph-all-max-rows exact graph --all --max-rows 2
compare_real_database graph-all-max-rows-json exact graph --all --max-rows 2 --json
compare_real_database graph-all-max-rows-negative exact graph --all --max-rows -1
compare_real_database graph-all-max-rows-negative-json exact graph --all --max-rows=-1 --json
compare_real_database_env graph-all-max-rows-env exact BEADS_MAX_ROWS=1 graph --all --dot
compare_real_database_env graph-all-max-rows-env-flag-zero exact BEADS_MAX_ROWS=1 graph --all --max-rows 0 --compact
compare_real_database_env graph-all-max-rows-env-malformed exact BEADS_MAX_ROWS=banana graph --all --open
compare_real_database graph-all-two-args exact graph --all "$real_database_epic_id" "$real_database_child_id"
compare_real_database graph-check-all-flag exact graph check --all
# The views that are not ported yet must fail the same way every time; upstream prints them.
graph_unported_sql="$graph_external_row ('fixture-graph-3', '$real_database_issue_id', 'external:other:test-elsewhere', 'blocks', '2026-08-21 10:00:00', 'fixture')"
expect_candidate_failure graph-all-other-repository-unported "" \
	"Error: loading all issues: graph of an issue with a dependency on another repository is not available yet in this build" \
	"$graph_unported_sql" graph --all
expect_candidate_failure graph-all-other-repository-json-unported \
	'{"error":"loading all issues: graph of an issue with a dependency on another repository is not available yet in this build","schema_version":1}' "" \
	"$graph_unported_sql" graph --all --json
expect_candidate_failure graph-other-repository-unported \
	'{"error":"loading graph: graph of an issue with a dependency on another repository is not available yet in this build","schema_version":1}' "" \
	"$graph_unported_sql" graph "$real_database_issue_id" --json
expect_candidate_failure graph-other-repository-visual-unported "" \
	"Error: loading graph: graph of an issue with a dependency on another repository is not available yet in this build" \
	"$graph_unported_sql" graph "$real_database_issue_id"
compare_real_database dep-list-up-invalid-type-json exact dep list "$real_database_epic_id" "$real_database_gated_molecule_id" --direction up --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
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
compare_real_database show-json-escaping exact show "$real_database_escaping_id" --json
compare_real_database show-human-escaping exact show "$real_database_escaping_id"
compare_real_database show-missing-escaping-json exact show 'test-<&>' --json
compare_real_database list-escaping-json exact list --title-contains Escaping --json
compare_real_database ready-escaping-json exact ready --label 'r&d' --json
compare_real_database show-json-labeled-dependency exact show "$real_database_labeled_relation_id" --json
compare_real_database show-json-labeled-dependents exact show "$real_database_issue_id" --include-dependents --json
compare_real_database dep-list-up-labeled-json exact dep list "$real_database_issue_id" --direction up --json
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
# bd comments resolves a partial ID, reads the comment table that the issue's wisp status selects,
# orders by created_at and then comment ID, and renders each body as Markdown.
compare_no_workspace comments_help comments --help
compare_no_workspace comments_missing_argument comments
compare_no_workspace comments_extra_argument comments test-parent extra
compare_no_workspace comments_extra_argument_json comments test-parent extra --json
compare_no_workspace comments_misplaced_add comments test-parent add "a comment"
compare_no_workspace comments_misplaced_add_json comments test-parent add "a comment" --json
compare_no_workspace comments_unknown_flag comments test-parent --status open
compare_no_workspace comments_invalid_local_time comments test-parent --local-time=maybe
compare_no_workspace comments_no_workspace comments test-parent
compare_no_workspace comments_list_no_workspace comments list
compare_real_database comments-human exact comments "$real_database_issue_id"
compare_real_database comments-json exact comments "$real_database_issue_id" --json
compare_real_database comments-none-human exact comments "$real_database_bug_id"
compare_real_database comments-none-json exact comments "$real_database_bug_id" --json
compare_real_database comments-partial-human exact comments abcd11
compare_real_database comments-ambiguous-human exact comments abcd
compare_real_database comments-ambiguous-json exact comments abcd --json
compare_real_database comments-missing-human exact comments test-nope
compare_real_database comments-missing-json exact comments test-nope --json
compare_real_database comments-list-human exact comments list
compare_real_database comments-list-json exact comments list --json
compare_real_database_env comments-envelope-json exact BD_JSON_ENVELOPE=1 comments "$real_database_issue_id" --json
comments_record() {
	jq -nc --arg id "$1" --argjson ephemeral "$2" '{id: $id, title: "Comment thread", status: "open", priority: 2,
		issue_type: "task", created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z", ephemeral: $ephemeral,
		comments: [
			{author: "zed", text: "Late evening note", created_at: "2026-08-21T20:30:00Z"},
			{author: "amy", text: "# Heading\n\nSome **bold** text, `code`, <tags> & entities.\n\n- one\n- two",
				created_at: "2026-08-21T10:15:00Z"},
			{author: "bob", text: "Tie one", created_at: "2026-08-21T10:15:00Z"},
			{author: "cat", text: "Tie two", created_at: "2026-08-21T10:15:00Z"}]}'
}
comments_durable_record="$(comments_record test-cdur false)"
comments_wisp_record="$(comments_record test-cwisp true)"
compare_real_database_import comments-thread-human exact "$comments_durable_record" comments cdur
compare_real_database_import comments-thread-json exact "$comments_durable_record" comments test-cdur --json
compare_real_database_import comments-wisp-human exact "$comments_wisp_record" comments test-cwisp
compare_real_database_import comments-wisp-json exact "$comments_wisp_record" comments test-cwisp --json
# Kathmandu is UTC+05:45, so --local-time moves the minute, the hour and, at 20:30 UTC, the date.
real_database_extra_import="$comments_durable_record"
compare_real_database_env comments-local-time-human exact TZ=Asia/Kathmandu comments test-cdur --local-time
compare_real_database_env comments-utc-human exact TZ=Asia/Kathmandu comments test-cdur --local-time=false
real_database_extra_import=""
# bd label list resolves a partial ID and prints the sorted labels of the issue's detail read.
# bd label list-all counts the labels of every issue SearchIssues returns, closed issues,
# templates and wisps included, sorts them by byte and pads each to the longest byte length.
compare_no_workspace label_bare label
compare_no_workspace label_help label --help
compare_no_workspace help_label help label
compare_no_workspace label_unknown_subcommand label frob --json
compare_no_workspace label_list_help label list --help
compare_no_workspace help_label_list help label list
compare_no_workspace label_list_all_help label list-all -h
compare_no_workspace label_list_missing_argument label list
compare_no_workspace label_list_extra_argument label list test-a test-b --json
compare_no_workspace label_list_unknown_flag label list test-a --status open
compare_no_workspace label_list_all_unknown_flag label list-all -s open
compare_no_workspace label_list_no_workspace label list test-a --json
compare_no_workspace label_list_all_no_workspace label list-all
compare_real_database label-list-human exact label list "$real_database_issue_id"
compare_real_database label-list-json exact label list "$real_database_issue_id" --json
compare_real_database label-list-escaping-json exact label list "$real_database_escaping_id" --json
compare_real_database label-list-none-human exact label list "$real_database_bug_id"
compare_real_database label-list-none-json exact label list "$real_database_bug_id" --json
compare_real_database label-list-partial-human exact label list abcd11
compare_real_database label-list-ambiguous-human exact label list abcd
compare_real_database label-list-ambiguous-json exact label list abcd --json
compare_real_database label-list-missing-human exact label list test-nope
compare_real_database label-list-missing-json exact label list test-nope --json
compare_real_database_env label-list-envelope-json exact BD_JSON_ENVELOPE=1 label list "$real_database_issue_id" --json
compare_real_database label-list-all-human exact label list-all
compare_real_database label-list-all-json exact label list-all --json
compare_real_database label-list-all-extra-argument exact label list-all extra
compare_real_database_env label-list-all-envelope-json exact BD_JSON_ENVELOPE=1 label list-all --json
# Byte order puts U+FF3A (EF BC BA) before an emoji (F0 ...), where UTF-16 order would not.
label_records="$(
	for record in \
		'{id: "test-lbl-closed", status: "closed", closed_at: "2026-08-21T13:00:00Z", labels: ["parity", "closed-only"]}' \
		'{id: "test-lbl-wisp", ephemeral: true, labels: ["parity", "wisp-only"]}' \
		'{id: "test-lbl-template", is_template: true, labels: ["template-only", "parity"]}' \
		'{id: "test-lbl-wide", labels: ["é-accent", "Ｚ-wide", "🏷-emoji", "Zed", "zed", "a b"]}'; do
		jq -nc "{title: \"Labeled record\", status: \"open\", priority: 2, issue_type: \"task\",
			created_at: \"2026-08-20T12:00:00Z\", updated_at: \"2026-08-21T13:00:00Z\"} + $record"
	done
)"
compare_real_database_import label-list-all-mixed-human exact "$label_records" label list-all
compare_real_database_import label-list-all-mixed-json exact "$label_records" label list-all --json
compare_real_database_import label-list-wisp-human exact "$label_records" label list lbl-wisp
compare_real_database_import label-list-wide-human exact "$label_records" label list test-lbl-wide
compare_real_database_import label-list-wide-json exact "$label_records" label list test-lbl-wide --json
# A bead kept in the wisps table without being ephemeral (--no-history) still counts its wisp_labels rows.
# Dolt ignores the wisp tables, so the title change gives fixture-sql's commit something to record.
real_database_extra_import="$label_records"
compare_real_database_sql label-list-all-no-history-json exact \
	"UPDATE wisps SET ephemeral = 0, updated_at = updated_at WHERE id = 'test-lbl-wisp'
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'" label list-all --json
real_database_extra_import=""
compare_real_database_sql label-list-all-empty-human exact "DELETE FROM labels" label list-all
compare_real_database_sql label-list-all-empty-json exact "DELETE FROM labels" label list-all --json
expect_candidate_failure label-add-unported "" "Error: label add is not available yet in this build" "" \
	label add "$real_database_issue_id" fresh
expect_candidate_failure label-remove-unported "" "Error: label remove is not available yet in this build" "" \
	label remove "$real_database_issue_id" parity
expect_candidate_failure label-propagate-unported "" "Error: label propagate is not available yet in this build" "" \
	label propagate "$real_database_epic_id" parity
# bd history resolves a partial ID (only an ambiguous one is fatal; any other miss keeps the typed ID),
# reads one dolt_history_issues row for each commit that holds the issue, newest commit first, and then
# cuts the list to --limit. --events reads events, or wisp_events for an active wisp, with a SQL LIMIT.
compare_no_workspace history_help history --help
compare_no_workspace help_history help history
compare_no_workspace history_missing_argument history
compare_no_workspace history_extra_argument history test-a test-b
compare_no_workspace history_extra_argument_json history test-a test-b --json
compare_no_workspace history_invalid_limit history test-a --limit many
compare_no_workspace history_invalid_limit_equals history test-a --limit=many
compare_no_workspace history_limit_shorthand history test-a -n 3
compare_no_workspace history_invalid_events history test-a --events=maybe
compare_no_workspace history_unknown_flag history test-a --status open
compare_no_workspace history_no_workspace history test-a
compare_no_workspace history_no_workspace_json history test-a --events --json
compare_real_database history-human exact history "$real_database_issue_id"
compare_real_database history-json exact history "$real_database_issue_id" --json
compare_real_database history-closed-human exact history "$real_database_closed_id"
compare_real_database history-closed-json exact history "$real_database_closed_id" --json
compare_real_database history-limit-human exact history "$real_database_issue_id" --limit 2
compare_real_database history-limit-json exact history "$real_database_issue_id" --limit=2 --json
compare_real_database history-limit-above-human exact history "$real_database_closed_id" --limit 500
compare_real_database history-limit-negative-json exact history "$real_database_closed_id" --limit -1 --json
compare_real_database history-partial-human exact history abcd11 --limit 1
compare_real_database history-ambiguous-human exact history abcd
compare_real_database history-ambiguous-json exact history abcd --json
compare_real_database history-missing-human exact history test-nope
compare_real_database history-missing-json exact history test-nope --json
compare_real_database history-bare-missing-human exact history nope
compare_real_database_env history-envelope-json exact BD_JSON_ENVELOPE=1 history "$real_database_closed_id" --limit 1 --json
compare_real_database_env history-missing-envelope-json exact BD_JSON_ENVELOPE=1 history test-nope --json
# Commit dates print in the local zone (Kathmandu is UTC+05:45); event times stay in UTC.
compare_real_database_env history-local-zone-human exact TZ=Asia/Kathmandu history "$real_database_closed_id" --limit 3
compare_real_database_env history-events-local-zone-human exact TZ=Asia/Kathmandu history "$real_database_closed_id" --events
compare_real_database history-events-human exact history "$real_database_issue_id" --events
compare_real_database history-events-json exact history "$real_database_issue_id" --events --json
compare_real_database history-events-limit-human exact history "$real_database_issue_id" --events --limit 2
compare_real_database history-events-limit-json exact history "$real_database_issue_id" --events --limit 2 --json
compare_real_database history-events-partial-human exact history abcd11 --events
compare_real_database history-events-ambiguous-json exact history abcd --events --json
compare_real_database history-events-missing-human exact history test-nope --events
compare_real_database history-events-missing-json exact history test-nope --events --json
compare_real_database_env history-events-missing-envelope-json exact BD_JSON_ENVELOPE=1 history test-nope --events --json
# fixture-sql commits on each copy separately, so a commit that history prints pins its dates; the hash
# then matches on both copies. Events live in a table Dolt ignores, so a title change makes the commit.
history_dated_commit="SET @@SESSION.dolt_author_date = '2031-02-03T04:05:06Z'
SET @@SESSION.dolt_committer_date = '2031-02-03T04:05:06Z'"
history_sparse_sql="$history_dated_commit
UPDATE issues SET title = 'Sparse <row> & co', assignee = NULL, owner = NULL, created_by = NULL, estimated_minutes = 0, pinned = 1, mol_type = 'swarm', status = 'review', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database_sql history-sparse-human exact "$history_sparse_sql" history "$real_database_bug_id" --limit 2
compare_real_database_sql history-sparse-json exact "$history_sparse_sql" history "$real_database_bug_id" --limit 2 --json
history_events_sql="$history_dated_commit
DELETE FROM events WHERE issue_id = '$real_database_bug_id'
INSERT INTO events (id, issue_id, event_type, actor, old_value, new_value, comment, created_at) VALUES ('00000000-0000-0000-0000-000000000001', '$real_database_bug_id', 'commented', 'amy', NULL, NULL, 'Looks <good> & done', '2030-01-02 03:04:05'), ('00000000-0000-0000-0000-000000000002', '$real_database_bug_id', 'status_changed', 'bob', 'open', 'in_progress', '', '2030-01-02 03:04:05'), ('00000000-0000-0000-0000-000000000003', '$real_database_bug_id', 'updated', 'cat', '', 'x', NULL, '2029-12-31 23:59:59')
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database_sql history-events-rows-human exact "$history_events_sql" history "$real_database_bug_id" --events
compare_real_database_sql history-events-rows-json exact "$history_events_sql" history "$real_database_bug_id" --events --json
compare_real_database_sql history-events-rows-limit-human exact "$history_events_sql" history "$real_database_bug_id" --events --limit 1
history_no_events_sql="$history_dated_commit
DELETE FROM events WHERE issue_id = '$real_database_bug_id'
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database_sql history-events-none-human exact "$history_no_events_sql" history "$real_database_bug_id" --events
compare_real_database_sql history-events-none-json exact "$history_no_events_sql" history "$real_database_bug_id" --events --json
# Dolt ignores the wisp tables, so a wisp has no commit history; its events come from wisp_events. The
# import writes a created event at the current second on each copy, so the cases replace it.
real_database_extra_import="$comments_wisp_record"
compare_real_database history-wisp-human exact history cwisp
compare_real_database history-wisp-json exact history test-cwisp --json
history_wisp_events_sql="DELETE FROM wisp_events WHERE issue_id = 'test-cwisp'
INSERT INTO wisp_events (id, issue_id, event_type, actor, old_value, new_value, comment, created_at) VALUES ('00000000-0000-0000-0000-00000000000a', 'test-cwisp', 'closed', 'zed', '', 'done', '', '2030-05-06 07:08:09'), ('00000000-0000-0000-0000-00000000000b', 'test-cwisp', 'created', 'amy', NULL, NULL, NULL, '2030-05-06 07:00:00')
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database_sql history-wisp-events-human exact "$history_wisp_events_sql" history test-cwisp --events
compare_real_database_sql history-wisp-events-json exact "$history_wisp_events_sql" history test-cwisp --events --json
# A wisp event without created_at fails the scan into time.Time.
history_wisp_null_sql="INSERT INTO wisp_events (id, issue_id, event_type, actor, created_at) VALUES ('00000000-0000-0000-0000-00000000000c', 'test-cwisp', 'commented', 'amy', NULL)
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database_sql history-wisp-null-time-human exact "$history_wisp_null_sql" history test-cwisp --events
compare_real_database_sql history-wisp-null-time-json exact "$history_wisp_null_sql" history test-cwisp --events --json
real_database_extra_import=""
# Upstream reads proxied workspaces through the server; --global always selects a server database.
expect_candidate_failure history-global-unported "" \
	"Error: history is not available yet for server-mode or proxied workspaces in this build" "" \
	history "$real_database_issue_id" --global
expect_candidate_failure history-global-json-unported \
	'{"error":"history is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	history "$real_database_issue_id" --events --global --json
# bd events tail and export print bd_events_journal rows after --since as JSON lines, oldest first, cut by a
# SQL LIMIT. The stored payloads are compacted and HTML-escaped, never re-encoded. A read whose rows do not
# continue the checkpoint fails with the retained window. Reads never prune (the events family is exempt).
compare_no_workspace events_bare events
compare_no_workspace events_help events --help
compare_no_workspace help_events help events
compare_no_workspace events_unknown_subcommand events frob --json
compare_no_workspace events_tail_help events tail --help
compare_no_workspace help_events_tail help events tail
compare_no_workspace events_export_help events export -h
compare_no_workspace events_tail_no_workspace events tail --since -1
compare_no_workspace events_export_no_workspace_json events export --json
compare_no_workspace events_tail_invalid_since events tail --since many
compare_no_workspace events_tail_empty_since events tail --since=
compare_no_workspace events_tail_since_out_of_range events tail --since 99999999999999999999
compare_no_workspace events_tail_missing_since events tail --since
compare_no_workspace events_tail_invalid_limit events tail --limit=many
compare_no_workspace events_export_limit_out_of_range events export --limit 99999999999999999999
compare_no_workspace events_tail_limit_shorthand events tail -n 2
compare_no_workspace events_tail_invalid_follow events tail --follow=maybe
compare_no_workspace events_export_unknown_since events export --since 1
compare_no_workspace events_export_unknown_follow events export --follow
# `bd events` itself prints its usage under a flag error; pflag rejects an unknown flag before its value.
compare_no_workspace events_unknown_flag events --since 1
compare_no_workspace events_unknown_flag_before_subcommand events --bogus tail
compare_no_workspace events_unknown_subcommand_limit events frob --limit x
compare_no_workspace events_unknown_follow events --follow=maybe
compare_no_workspace list_unknown_since list --since x
compare_no_workspace events_tail_unknown_flag events tail --status open
compare_no_workspace events_tail_unknown_before events tail --before 3
compare_no_workspace events_prune_invalid_before events prune --before many
# The seed never enabled the journal: no rows and a head of 0.
compare_real_database events-tail-empty-human exact events tail
compare_real_database events-export-empty-json exact events export --json
compare_real_database events-tail-above-head exact events tail --since 5
compare_real_database events-tail-follow-false exact events tail --follow=false
compare_real_database events-tail-negative-since-human exact events tail --since -1
compare_real_database events-tail-negative-since-json exact events tail --since=-1 --json
compare_real_database_env events-tail-negative-since-envelope-json exact BD_JSON_ENVELOPE=1 events tail --since -1 --json
# fixture-sql writes journal rows directly. Dolt ignores the journal tables, so a title change gives its
# commit something to record. Row 1 has spaces and <, > and &; row 2 has a raw U+2028.
events_commit="UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
events_line_separator="$(printf '\342\200\250')"
events_rows_sql="INSERT INTO bd_events_journal (seq, ts, op, issue_id, issue_json, dep_json, comment_json) VALUES (1, '2030-01-02 03:04:05', 'create', 'test-ev1', '{ \"id\" : \"test-ev1\", \"title\": \"Spaced <b> & co\", \"n\": [1.50, 1E3, -0] }', NULL, NULL), (2, '2030-01-02 03:04:06', 'comment', 'test-ev1', '{\"id\":\"test-ev1\"}', '', '{\"id\":7,\"author\":\"amy\",\"text\":\"ünï${events_line_separator}x\",\"source\":\"\"}'), (3, '1999-12-31 23:59:59', 'dep_add', 'test-ev<2>', '{\"id\":\"test-ev<2>\"}', '{\"kind\":\"blocks\",\"target\":\"test-ev1\",\"metadata\":\"{}\"}', NULL), (4, '2030-12-31 00:00:00', 'delete', 'test-ev1', NULL, NULL, NULL)
UPDATE bd_events_seq SET next_seq = 4 WHERE id = 0
$events_commit"
compare_real_database_sql events-export-rows-human exact "$events_rows_sql" events export
compare_real_database_sql events-export-rows-json exact "$events_rows_sql" events export --json
compare_real_database_sql events-tail-since-inside exact "$events_rows_sql" events tail --since 2
compare_real_database_sql events-tail-since-hex exact "$events_rows_sql" events tail --since=0x1 --limit 0b10
compare_real_database_sql events-tail-since-at-head exact "$events_rows_sql" events tail --since 4
compare_real_database_sql events-tail-since-after-head exact "$events_rows_sql" events tail --since 9
compare_real_database_sql events-tail-limit exact "$events_rows_sql" events tail --since 1 --limit 2
compare_real_database_sql events-tail-negative-limit exact "$events_rows_sql" events tail --limit -3
compare_real_database_sql events-export-limit exact "$events_rows_sql" events export --limit=1 extra
real_database_extra_sql="$events_rows_sql"
compare_real_database_env events-tail-envelope-json exact BD_JSON_ENVELOPE=1 events tail --json
real_database_extra_sql=""
# A pruned prefix: rows 3 and 4 remain below a head of 4.
events_pruned_sql="$events_rows_sql
DELETE FROM bd_events_journal WHERE seq < 3"
compare_real_database_sql events-export-truncated-human exact "$events_pruned_sql" events export
compare_real_database_sql events-export-truncated-json exact "$events_pruned_sql" events export --json
compare_real_database_sql events-tail-truncated-limit-json exact "$events_pruned_sql" events tail --since 1 --limit 1 --json
compare_real_database_sql events-tail-from-floor exact "$events_pruned_sql" events tail --since 2
real_database_extra_sql="$events_pruned_sql"
compare_real_database_env events-export-truncated-envelope-json exact BD_JSON_ENVELOPE=1 events export --json
real_database_extra_sql=""
# Every row pruned: the floor is one past the head, and a caught-up checkpoint still reads nothing.
events_emptied_sql="$events_rows_sql
DELETE FROM bd_events_journal"
compare_real_database_sql events-tail-emptied-human exact "$events_emptied_sql" events tail --since 1
compare_real_database_sql events-tail-emptied-caught-up exact "$events_emptied_sql" events tail --since 4
# An interior hole reports the last contiguous row as the checkpoint.
events_gap_sql="$events_rows_sql
DELETE FROM bd_events_journal WHERE seq = 3"
compare_real_database_sql events-export-gap-human exact "$events_gap_sql" events export
compare_real_database_sql events-export-gap-json exact "$events_gap_sql" events export --json
# Legacy JSON round-trips the payload through float64, so a head above 2^53 rounds; the envelope does not.
events_huge_head_sql="$events_pruned_sql
UPDATE bd_events_seq SET next_seq = 9007199254740993 WHERE id = 0"
compare_real_database_sql events-export-huge-head-human exact "$events_huge_head_sql" events export
compare_real_database_sql events-export-huge-head-json exact "$events_huge_head_sql" events export --json
real_database_extra_sql="$events_huge_head_sql"
compare_real_database_env events-export-huge-head-envelope-json exact BD_JSON_ENVELOPE=1 events export --json
real_database_extra_sql=""
# A missing counter row is a head of 0; a missing table fails the read.
compare_real_database_sql events-export-no-counter-human exact "$events_pruned_sql
DELETE FROM bd_events_seq" events export
compare_real_database_sql events-export-no-counter-table-json exact "DROP TABLE bd_events_seq
$events_commit" events export --json
compare_real_database_sql events-tail-no-journal-table-human exact "DROP TABLE bd_events_journal
$events_commit" events tail
# A payload Go cannot compact stops the stream after the rows before it. An empty payload is absent.
events_bad_json_sql="$events_rows_sql
UPDATE bd_events_journal SET issue_json = '{\"id\": broken' WHERE seq = 3"
compare_real_database_sql events-export-bad-json-human exact "$events_bad_json_sql" events export
compare_real_database_sql events-export-bad-json-json exact "$events_bad_json_sql" events export --json
compare_real_database_sql events-export-blank-dep exact "$events_rows_sql
UPDATE bd_events_journal SET dep_json = ' ' WHERE seq = 2" events export
compare_real_database_sql events-export-empty-issue exact "$events_rows_sql
UPDATE bd_events_journal SET issue_json = '', dep_json = '' WHERE seq = 3" events export
# --follow polls until a signal; prune writes. Neither is ported, and --global always selects a server.
expect_candidate_failure events-tail-follow-unported "" "Error: events tail --follow is not available yet in this build" "" \
	events tail --follow
expect_candidate_failure events-prune-unported "" "Error: events prune is not available yet in this build" "" \
	events prune --before 3
expect_candidate_failure events-tail-global-unported "" \
	"Error: events tail is not available yet for server-mode or proxied workspaces in this build" "" \
	events tail --global
expect_candidate_failure events-export-global-json-unported \
	'{"error":"events export is not available yet for server-mode or proxied workspaces in this build","schema_version":1}' "" "" \
	events export --global --json

# The global JSON switch. Without --json or the root --format, upstream reads the `json` setting of
# the layered config (BD_JSON, then config.local.yaml, config.yaml and the user config.yaml) once
# it has selected the workspace, and every command then prints exactly what --json prints. BD_JSON
# counts only as Go's strconv.ParseBool reads it, and an empty BD_JSON is unset. --json and
# --json=<bool> outrank it, and so does a root --format, except that --format json always selects
# JSON. The --format of list and dep tree is their own flag and does not count. Help and --version
# print text, and flag errors stay text, as cobra prints them before the switch is read.
json_yaml='json: true'
compare_real_database_config global-json-yaml-list exact "$json_yaml" list
compare_real_database_config global-json-yaml-show exact "$json_yaml" show "$real_database_issue_id"
compare_real_database_config global-json-yaml-ready exact "$json_yaml" ready
compare_real_database_config global-json-yaml-count exact "$json_yaml" count
compare_real_database_config global-json-yaml-graph exact "$json_yaml" graph "$real_database_epic_id"
compare_real_database_config global-json-yaml-dep-tree exact "$json_yaml" dep tree "$real_database_grandchild_id"
compare_real_database_config global-json-yaml-comments exact "$json_yaml" comments "$real_database_issue_id"
real_database_extra_sql="$events_pruned_sql"
compare_real_database_config global-json-yaml-events-export exact "$json_yaml" events export
real_database_extra_sql=""
compare_real_database_config global-json-yaml-config-get exact "$json_yaml" config get json
compare_real_database_config global-json-yaml-types exact "$json_yaml" types
compare_real_database_config global-json-yaml-info-schema exact "$json_yaml" info --schema
compare_real_database_config global-json-yaml-ping ping-json "$json_yaml" ping
compare_real_database_config global-json-yaml-where exact "$json_yaml" where
compare_real_database_config global-json-yaml-list-help exact "$json_yaml" list --help
compare_real_database_config global-json-yaml-show-missing exact "$json_yaml" show test-missing
compare_real_database_config global-json-yaml-ready-bad-sort exact "$json_yaml" ready --sort bogus
compare_real_database_config global-json-yaml-ready-brief exact "$json_yaml" ready --brief
compare_real_database_config global-json-yaml-list-deps exact "$json_yaml" list --deps=all
compare_real_database_config global-json-yaml-flag-false exact "$json_yaml" count --json=false
compare_real_database_config global-json-yaml-format-text exact "$json_yaml" count --format=text
compare_real_database_config global-json-yaml-list-format-digraph exact "$json_yaml" list --format digraph
compare_real_database_config global-json-yaml-dep-tree-mermaid exact "$json_yaml" \
	dep tree "$real_database_grandchild_id" --format mermaid
compare_real_database_config global-json-yaml-yes exact 'json: yes' count
compare_real_database_env global-json-env-1-show exact BD_JSON=1 show "$real_database_issue_id"
compare_real_database_env global-json-env-true-list exact BD_JSON=true list
compare_real_database_env global-json-env-capital-t-ready exact BD_JSON=T ready
compare_real_database_env global-json-env-1-dep-tree exact BD_JSON=1 dep tree "$real_database_grandchild_id"
compare_real_database_env global-json-env-1-comments exact BD_JSON=1 comments "$real_database_issue_id"
compare_real_database_env global-json-env-1-events-tail exact BD_JSON=1 events tail --since=-1
compare_real_database_env global-json-env-1-config-get exact BD_JSON=1 config get issue_prefix
compare_real_database_env global-json-env-1-types exact BD_JSON=1 types
compare_real_database_env global-json-env-1-ping ping-json BD_JSON=1 ping
compare_real_database_env global-json-env-1-dep-tree-missing exact BD_JSON=1 dep tree test-missing
compare_real_database_env global-json-env-0-graph exact BD_JSON=0 graph "$real_database_epic_id"
compare_real_database_env global-json-env-false-ready exact BD_JSON=false ready
compare_real_database_env global-json-env-empty-count exact BD_JSON= count
compare_real_database_env global-json-env-yes-count exact BD_JSON=yes count
compare_real_database_env global-json-env-padded-count exact 'BD_JSON=1 ' count
compare_real_database_config_env global-json-env-0-over-yaml exact "$json_yaml" BD_JSON=0 count
compare_real_database_config_env global-json-env-empty-keeps-yaml exact "$json_yaml" BD_JSON= count
compare_real_database_config_env global-json-env-blank-over-yaml exact "$json_yaml" 'BD_JSON= ' count
compare_real_database_env global-json-flag-false-over-env exact BD_JSON=1 count --json=false
compare_real_database_env global-json-flag-over-env exact BD_JSON=0 count --json
compare_real_database_env global-json-format-json-over-env exact BD_JSON=0 ready --format=JSON
compare_real_database global-json-format-json-over-flag-false exact count --json=false --format json
compare_real_database global-json-format-last-wins exact list --format json --format digraph
compare_real_database global-json-format-folded exact count --format jſon
compare_real_database global-json-bad-flag-value exact count --json=bogus
compare_real_database_env global-json-env-graph-no-id exact BD_JSON=1 graph
# bd comments checks its arguments before the pre-run, where only --json has been read.
compare_real_database_env global-json-env-comments-extra-argument exact BD_JSON=1 comments "$real_database_issue_id" extra
compare_real_database global-json-comments-extra-argument-format exact comments "$real_database_issue_id" add x --format json
compare_real_database global-json-comments-extra-argument-flag exact comments "$real_database_issue_id" extra --json=true
compare_real_database_local_config global-json-local-yaml exact "" "$json_yaml" list
compare_real_database_local_config global-json-local-over-yaml exact "$json_yaml" 'json: false' count
write_json_user_config() {
	mkdir -p "$1/user-home/.config/bd"
	printf 'json: true\n' >"$1/user-home/.config/bd/config.yaml"
}
real_database_setup=write_json_user_config
compare_real_database global-json-user-yaml-count exact count
compare_real_database_config global-json-workspace-over-user-yaml exact 'json: false' count
real_database_setup=""
compare_no_workspace_env global_json_env_where BD_JSON=1 where
compare_no_workspace_env global_json_env_where_flag_false BD_JSON=1 where --json=false
compare_no_workspace_env global_json_env_list BD_JSON=1 list
compare_no_workspace_env global_json_env_config_get BD_JSON=1 config get export.auto
compare_no_workspace_env global_json_env_list_help BD_JSON=1 list --help
compare_no_workspace_env global_json_env_help_list BD_JSON=1 help list
compare_no_workspace_env global_json_env_unknown_flag BD_JSON=1 count --frobnicate
compare_no_workspace global_json_bad_flag_value where --json=bogus
compare_no_workspace global_json_empty_flag_value ready --json=
compare_no_workspace_user_config global_json_user_yaml_where "$json_yaml" where
compare_no_workspace_user_config global_json_user_yaml_config_get "$json_yaml" config get json
no_workspace_extra_env=(BD_JSON=1)
compare_version_mode global_json_env_version json version
compare_version_mode global_json_env_version_flag text --version
compare_version_mode global_json_env_version_shorthand text -V
compare_version_mode global_json_env_version_json_false text version --json=false
no_workspace_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_version_mode global_json_version_flag_with_json text --version --json
no_workspace_user_config="$json_yaml"
compare_version_mode global_json_user_yaml_version json version
no_workspace_user_config=""
# bdhx's refusals follow the same switch as upstream's errors.
real_database_extra_env=(BD_JSON=1)
candidate_only_setup=enable_shared_server
expect_candidate_failure global-json-env-shared-server-refusal \
	'{"error":"count is not available yet in shared-server mode in this build","schema_version":1}' "" "" count
candidate_only_setup=set_database_path
expect_candidate_failure global-json-env-db-setting-refusal \
	'{"error":"ready is not available yet when the db setting names a database in this build","schema_version":1}' "" "" ready
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
enable_shared_server_with_json() {
	enable_shared_server "$1"
	printf 'json: true\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=enable_shared_server_with_json
expect_candidate_failure global-json-yaml-shared-server-refusal \
	'{"error":"list is not available yet in shared-server mode in this build","schema_version":1}' "" "" list
expect_candidate_failure global-json-yaml-shared-server-flag-false-refusal "" \
	"Error: list is not available yet in shared-server mode in this build" "" list --json=false
candidate_only_setup=""

# Upstream's pre-run loads the selected workspace's .beads/.env with gotenv before it reads any
# setting, so a variable there counts as if it were exported, unless the environment already has
# it, even empty. First, when neither -C nor a set BEADS_DIR, BEADS_DB or BD_DB chooses the
# workspace, the .env file of the workspace found from the current directory may set those three.
# Then every variable of the selected workspace's .env that the environment lacks is added; that
# step cannot set BEADS_DIR, and $BEADS_DIR expands to the selected directory. gotenv takes nothing
# from a file with one line it rejects, and nothing is printed for a missing or rejected file.
dotenv_contents=""
write_dotenv() {
	printf '%s' "$dotenv_contents" >"$1/work/.beads/.env"
}
compare_real_database_dotenv() {
	local name="$1"
	local comparison="$2"
	dotenv_contents="$3"
	shift 3
	real_database_setup=write_dotenv
	compare_real_database "$name" "$comparison" "$@"
	real_database_setup=""
	dotenv_contents=""
}
compare_real_database_dotenv dotenv-json-count exact $'BD_JSON=1\n' count
compare_real_database_dotenv dotenv-json-list exact $'BD_JSON=true\n' list
compare_real_database_dotenv dotenv-json-show exact $'BD_JSON=1\n' show "$real_database_issue_id"
compare_real_database_dotenv dotenv-json-where exact $'BD_JSON=1\n' where
compare_real_database_dotenv dotenv-json-config-get exact $'BD_JSON=1\n' config get json
compare_real_database_dotenv dotenv-json-flag-false exact $'BD_JSON=1\n' count --json=false
compare_real_database_dotenv dotenv-json-help exact $'BD_JSON=1\n' count --help
real_database_extra_env=(BD_JSON=0)
compare_real_database_dotenv dotenv-json-environment-wins exact $'BD_JSON=1\n' count
real_database_extra_env=(BD_JSON=)
compare_real_database_dotenv dotenv-json-empty-environment-wins exact $'BD_JSON=1\n' count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='json: true'
compare_real_database_dotenv dotenv-json-over-yaml exact $'BD_JSON=0\n' count
compare_real_database_dotenv dotenv-json-empty-keeps-yaml exact $'BD_JSON=\n' count
real_database_extra_config=""
# gotenv's line rules: comments, blank lines, `export`, `=` or `: `, quotes, inline comments,
# multi-line quoted values, escapes in double quotes, $VAR expansion (the environment first, then
# the file's earlier lines) and CR, LF or CRLF line ends after an optional UTF-8 or UTF-16 BOM.
compare_real_database_dotenv dotenv-parse-comment-export exact $'# a comment\n\n  export BD_JSON=1\n' count
compare_real_database_dotenv dotenv-parse-duplicate-last-wins exact $'BD_JSON=1\nBD_JSON=0\n' count
compare_real_database_dotenv dotenv-parse-duplicate-last-wins-json exact $'BD_JSON=0\nBD_JSON=1\n' count
compare_real_database_dotenv dotenv-parse-crlf exact $'BD_JSON=1\r\nBD_ROUTING_PROBE=crlf\r\n' config get routing.probe
compare_real_database_dotenv dotenv-parse-cr exact $'BD_ROUTING_PROBE=cr\rBD_JSON=1' config get routing.probe
compare_real_database_dotenv dotenv-parse-bom exact $'\xef\xbb\xbfBD_JSON=1\n' count
compare_real_database_dotenv dotenv-parse-double-quotes exact $'BD_ROUTING_PROBE="a\\nb\\tc # d"\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-single-quotes exact $'BD_ROUTING_PROBE=\'a\\nb $A # c\'\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-inline-comment exact $'BD_ROUTING_PROBE=bare value   # comment\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-equals-in-value exact $'BD_ROUTING_PROBE = a=b=c\n' config get routing.probe --json
compare_real_database_dotenv dotenv-parse-colon exact $'BD_ROUTING_PROBE: colon\n' config get routing.probe --json
compare_real_database_dotenv dotenv-parse-colon-lazy-space exact $'BD_ROUTING_PROBE:  "a#b"\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-multiline exact $'BD_ROUTING_PROBE="first\n  second \\" quote\nthird"\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-expansion exact \
	$'A=1\nBEADSHX_PARITY_EXTRA=file\nBD_ROUTING_PROBE=${A}x$A}y${A $lower ${} $ \\$A $UNSET_X ${LATER} $BEADSHX_PARITY_EXTRA\nLATER=2\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-expansion-beads-dir exact $'BD_ROUTING_PROBE="$BEADS_DIR/x"\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-escapes exact $'BD_ROUTING_PROBE="\\$A \\\\ \\q \\\\n"\n' \
	config get routing.probe --json
compare_real_database_dotenv dotenv-parse-dotted-key exact $'BD_ROUTING.PROBE=dotted\nBD_JSON=1\n' config get routing.probe
write_utf16_dotenv() {
	printf '\377\376B\000D\000_\000J\000S\000O\000N\000=\0001\000\r\000\n\000' >"$1/work/.beads/.env"
}
real_database_setup=write_utf16_dotenv
compare_real_database dotenv-parse-utf16 exact count
real_database_setup=""
# One rejected line, an unclosed quote or a line longer than bufio.Scanner's 64 KiB limit makes
# gotenv take nothing from the file.
compare_real_database_dotenv dotenv-malformed-line exact $'BD_JSON=1\nnot a valid line\n' count
compare_real_database_dotenv dotenv-malformed-unclosed-quote exact $'BD_JSON=1\nBD_ROUTING_PROBE="open\n' count
compare_real_database_dotenv dotenv-malformed-export-without-value exact $'BD_JSON=1\nexport BD_ROUTING_PROBE\n' count
compare_real_database_dotenv dotenv-malformed-colon-without-space exact $'BD_JSON=1\nBD_ROUTING_PROBE:value\n' count
# "BD_ROUTING_PROBE=" is 17 bytes, so these lines are 65535 and 65536 bytes long.
dotenv_long_value="$(head -c 65518 /dev/zero | tr '\0' x)"
compare_real_database_dotenv dotenv-line-at-scanner-limit exact $'BD_JSON=1\nBD_ROUTING_PROBE='"$dotenv_long_value"$'\n' count
compare_real_database_dotenv dotenv-line-over-scanner-limit exact $'BD_JSON=1\nBD_ROUTING_PROBE='"${dotenv_long_value}x"$'\n' count
# A .env directory adds nothing, a symbolic link is followed, and a dangling one adds nothing.
write_dotenv_directory() {
	mkdir -p "$1/work/.beads/.env"
}
write_dotenv_symlink() {
	printf 'BD_JSON=1\n' >"$1/work/.beads/linked.env"
	ln -s linked.env "$1/work/.beads/.env"
}
write_dotenv_dangling_symlink() {
	ln -s missing.env "$1/work/.beads/.env"
}
real_database_setup=write_dotenv_directory
compare_real_database dotenv-directory exact count
real_database_setup=write_dotenv_symlink
compare_real_database dotenv-symlink exact count
real_database_setup=write_dotenv_dangling_symlink
compare_real_database dotenv-dangling-symlink exact count
real_database_setup=""
# Settings read through Viper's BD_ prefix and plain BEADS_ variables, with their provenance.
compare_real_database_dotenv dotenv-config-show exact \
	$'BD_LIST_LIMIT=3\nBD_ISSUE_PREFIX=zz\nBEADS_MAX_ROWS=7\nBD_ACTOR=dotenv-actor\n' config show
compare_real_database_dotenv dotenv-config-show-env-json exact $'BD_LIST_LIMIT=3\nBEADS_MAX_ROWS=7\n' \
	config show --source env --json
compare_real_database_dotenv dotenv-config-get-list-limit exact $'BD_LIST_LIMIT=3\n' config get list.limit --json
compare_real_database_dotenv dotenv-config-list exact $'BD_LIST_LIMIT=3\nBD_ROUTING_MODE=auto\n' config list
compare_real_database_dotenv dotenv-list-limit exact $'BD_LIST_LIMIT=2\n' list
compare_real_database_dotenv dotenv-max-rows-dep-tree exact $'BEADS_MAX_ROWS=1\n' dep tree "$real_database_grandchild_id"
compare_real_database_dotenv dotenv-types-custom exact $'BD_TYPES_CUSTOM=alpha,beta\n' types
compare_real_database_dotenv dotenv-statuses-custom exact $'BD_STATUS_CUSTOM=review:wip\n' statuses --json
compare_real_database_dotenv dotenv-json-envelope exact $'BD_JSON_ENVELOPE=1\nBD_JSON=1\n' count
# A .env file can choose another workspace through BEADS_DIR. These cases add a second workspace
# at work/sub, with its own .env.
dotenv_sub_contents=""
write_dotenv_with_sub_workspace() {
	write_dotenv "$1"
	mkdir -p "$1/work/sub"
	copy_fixture_tree "$real_database_seed/work/.beads" "$1/work/sub/.beads"
	printf '%s' "$dotenv_sub_contents" >"$1/work/sub/.beads/.env"
}
real_database_setup=write_dotenv_with_sub_workspace
dotenv_sub_contents=$'BD_ROUTING_PROBE=sub\n'
dotenv_contents=$'BEADS_DIR=sub/.beads\nBD_JSON=1\nBD_ROUTING_PROBE=work\n'
compare_real_database dotenv-select-beads-dir exact config get routing.probe
compare_real_database dotenv-select-beads-dir-where exact where
compare_real_database dotenv-select-directory-flag exact -C . config get routing.probe
compare_real_database dotenv-select-directory-sub exact -C sub config get routing.probe
compare_real_database dotenv-select-database-flag exact --db sub/.beads/embeddeddolt config get routing.probe
real_database_extra_env=(BEADS_DIR=.beads)
compare_real_database dotenv-select-environment-beads-dir exact config get routing.probe
real_database_extra_env=(BEADS_DIR=)
compare_real_database dotenv-select-empty-environment-beads-dir exact config get routing.probe
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
dotenv_contents=$'BEADS_DIR="  "\nBD_JSON=1\n'
compare_real_database dotenv-select-blank-beads-dir exact where
dotenv_contents=$'BEADS_DIR=missing/.beads\nBD_JSON=1\n'
compare_real_database dotenv-select-missing-beads-dir exact where
dotenv_contents=$'BEADS_DIR=sub/.beads\nBD_JSON=1\nnot a valid line\n'
compare_real_database dotenv-select-malformed exact where
dotenv_sub_contents=$'BEADS_DIR=../.beads\nBD_ROUTING_PROBE=sub\n'
dotenv_contents=$'BEADS_DIR=sub/.beads\n'
compare_real_database dotenv-select-once exact config get routing.probe
# A redirect selects its target, whose .env is loaded instead of the redirecting workspace's.
write_dotenv_redirect_to_sub() {
	write_dotenv_with_sub_workspace "$1"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=write_dotenv_redirect_to_sub
dotenv_sub_contents=$'BD_ROUTING_PROBE=sub\n'
dotenv_contents=$'BD_JSON=1\n'
compare_real_database dotenv-redirect exact config get routing.probe
compare_real_database dotenv-redirect-where exact where
real_database_setup=""
dotenv_sub_contents=""
dotenv_contents=""
# A selector from .env also makes upstream ignore the db setting, so it reads the workspace as usual
# and writes nothing.
write_dotenv_with_database_path() {
	set_database_path "$1"
	write_dotenv "$1"
}
real_database_read_only=1
real_database_setup=write_dotenv_with_database_path
dotenv_contents=$'BD_DB=fake-selector\nBD_JSON=1\n'
compare_real_database dotenv-db-setting-bd-db exact count
compare_real_database dotenv-db-setting-bd-db-config-get exact config get db
dotenv_contents=$'BEADS_DB=fake-selector\n'
compare_real_database dotenv-db-setting-beads-db exact ready
dotenv_contents=$'BEADS_DIR=.beads\n'
compare_real_database dotenv-db-setting-beads-dir exact list
real_database_setup=""
real_database_read_only=""
# Shared-server mode and the db setting from .env meet the same refusals as from the environment.
candidate_only_setup=write_dotenv
dotenv_contents=$'BEADS_DOLT_SHARED_SERVER=1\n'
expect_store_refusal dotenv-shared-server-unported "$shared_reason" count count
dotenv_contents=$'BD_DOLT_SHARED_SERVER=true\nBD_JSON=1\n'
expect_candidate_failure dotenv-bd-shared-server-json-unported \
	'{"error":"config show is not available yet in shared-server mode in this build","schema_version":1}' "" "" config show
candidate_only_setup=write_dotenv_with_database_path
dotenv_contents=$'BD_JSON=1\n'
expect_candidate_failure dotenv-db-setting-json-unported \
	'{"error":"ready is not available yet when the db setting names a database in this build","schema_version":1}' "" "" ready
candidate_only_setup=""
dotenv_contents=""
# Without a workspace, no .env file is read: not one in the current directory, and not one in a
# .beads directory that holds no project files.
write_stray_dotenv() {
	printf 'BD_JSON=1\n' >"$1/work/.env"
	mkdir -p "$1/work/.beads"
	printf 'BD_JSON=1\n' >"$1/work/.beads/.env"
}
no_workspace_setup=write_stray_dotenv
compare_no_workspace dotenv_without_workspace_where where
compare_no_workspace dotenv_without_workspace_count count
compare_no_workspace dotenv_without_workspace_config_get config get json
no_workspace_setup=""

# Upstream's commands that open the store take BEADS_DB, never BD_DB, only when no --db, -C or
# BEADS_DIR is set and no workspace is found from the current directory. `where` takes BEADS_DB, else
# BD_DB, before -C, BEADS_DIR and the current directory; only --db comes first. A path selects an
# embedded workspace when it names the workspace directory, its embeddeddolt directory, or a missing
# file directly in a .beads directory, such as a legacy beads.db: upstream then prints that file as
# the database path in `info`. The cases run in work, whose workspace moves to work/db.
move_workspace_to_db() {
	mkdir "$1/work/db"
	mv "$1/work/.beads" "$1/work/db/.beads"
}
# Also adds a copy of the workspace at work/other.
copy_workspace_to_other() {
	move_workspace_to_db "$1"
	mkdir "$1/work/other"
	copy_fixture_tree "$1/work/db/.beads" "$1/work/other/.beads"
}
# Keeps the current directory's workspace and adds the copy at work/other.
add_other_workspace() {
	mkdir "$1/work/other"
	copy_fixture_tree "$1/work/.beads" "$1/work/other/.beads"
}
compare_beads_db() {
	local name="$1"
	local comparison="$2"
	local environment="$3"
	shift 3
	read -r -a real_database_extra_env <<<"$environment"
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
}
real_database_read_only=1
real_database_setup=move_workspace_to_db
compare_beads_db beads-db-workspace-count exact BEADS_DB=db/.beads count
compare_beads_db beads-db-workspace-list-json exact BEADS_DB=db/.beads list --json
compare_beads_db beads-db-absolute-workspace-label-list exact BEADS_DB='<work>/db/.beads' label list "$real_database_issue_id"
compare_beads_db beads-db-workspace-info-schema-json exact BEADS_DB=db/.beads info --schema --json
compare_beads_db beads-db-database-directory-ready exact BEADS_DB=db/.beads/embeddeddolt ready
compare_beads_db beads-db-absolute-database-directory-info-json exact BEADS_DB='<work>/db/.beads/embeddeddolt' info --json
compare_beads_db beads-db-legacy-file-count exact BEADS_DB=db/.beads/beads.db count
compare_beads_db beads-db-legacy-dolt-path-config-get exact BEADS_DB=db/.beads/dolt config get issue_prefix
# Human `info` also checks the Git hooks, which this build does not port, so these print JSON.
compare_beads_db beads-db-legacy-file-info-json exact BEADS_DB=db/.beads/beads.db info --json
compare_beads_db beads-db-absolute-legacy-file-info-json exact BEADS_DB='<work>/db/.beads/beads.db' info --json
compare_beads_db beads-db-where exact BEADS_DB=db/.beads where
compare_beads_db beads-db-where-legacy-file-json exact BEADS_DB=db/.beads/beads.db where --json
compare_beads_db beads-db-where-bd-db exact BD_DB=db/.beads/embeddeddolt where
# Store commands ignore BD_DB.
compare_beads_db beads-db-bd-db-count exact BD_DB=db/.beads count
# A BEADS_DIR that names no workspace still keeps BEADS_DB from selecting.
compare_beads_db beads-db-invalid-beads-dir-count exact 'BEADS_DIR=. BEADS_DB=db/.beads' count
# -C is checked first; a file names no absolute path in the error.
compare_beads_db beads-db-where-invalid-directory exact BEADS_DB=db/.beads -C db/.beads/metadata.json where
# version runs as usual, even for a path that this build cannot select.
compare_beads_db beads-db-version stderr-only BEADS_DB=missing/beads.db version
# The selected workspace's config.yaml and .env apply.
real_database_extra_config='json: true'
compare_beads_db beads-db-json-setting-count exact BEADS_DB=db/.beads count
compare_beads_db beads-db-json-setting-where exact BEADS_DB=db/.beads where
real_database_extra_config=""
move_workspace_with_dotenv() {
	move_workspace_to_db "$1"
	printf 'BD_JSON=1\n' >"$1/work/db/.beads/.env"
}
real_database_setup=move_workspace_with_dotenv
compare_beads_db beads-db-dotenv-ready exact BEADS_DB=db/.beads ready
real_database_setup=copy_workspace_to_other
compare_beads_db beads-db-beads-dir-first-info-json exact 'BEADS_DIR=other/.beads BEADS_DB=db/.beads' info --json
compare_beads_db beads-db-directory-flag-first-info-json exact BEADS_DB=db/.beads -C other info --json
compare_beads_db beads-db-db-flag-first-info-json exact BEADS_DB=db/.beads --db other/.beads/embeddeddolt info --json
compare_beads_db beads-db-where-before-directory-flag exact BEADS_DB=db/.beads -C other where
compare_beads_db beads-db-where-before-beads-dir exact 'BEADS_DIR=other/.beads BEADS_DB=db/.beads' where
compare_beads_db beads-db-where-before-bd-db exact 'BEADS_DB=db/.beads BD_DB=other/.beads' where --json
compare_beads_db beads-db-where-db-flag-first exact BEADS_DB=db/.beads --db other/.beads where
real_database_setup=add_other_workspace
compare_beads_db beads-db-current-directory-first-info-json exact BEADS_DB=other/.beads info --json
compare_beads_db beads-db-where-before-current-directory exact BEADS_DB=other/.beads where
real_database_setup=""
real_database_read_only=""
no_workspace_extra_env=(BD_DB=missing)
compare_no_workspace beads-db-bd-db-without-workspace count
no_workspace_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Other paths are refused before anything opens. For a missing path outside a .beads directory, a
# directory that is not a workspace, or a workspace without a database, upstream creates an embedded
# database; it reads the workspace for a deeper path inside it or a trailing slash.
expect_beads_db_refusal() {
	local name="$1"
	local environment="$2"
	local stdout="$3"
	local stderr="$4"
	shift 4
	read -r -a real_database_extra_env <<<"$environment"
	expect_candidate_failure "$name" "$stdout" "$stderr" "" "$@"
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
}
candidate_only_setup=move_workspace_to_db
expect_beads_db_refusal beads-db-missing-path-unported BEADS_DB=missing/beads.db "" \
	"Error: count is not available yet when BEADS_DB names this path in this build" count
expect_beads_db_refusal beads-db-plain-directory-json-unported BEADS_DB=. \
	'{"error":"list is not available yet when BEADS_DB names this path in this build","schema_version":1}' "" list --json
expect_beads_db_refusal beads-db-project-directory-unported BEADS_DB='<work>/db' "" \
	"Error: show is not available yet when BEADS_DB names this path in this build" show "$real_database_issue_id"
expect_beads_db_refusal beads-db-deeper-path-unported BEADS_DB=db/.beads/missing/beads.db "" \
	"Error: ready is not available yet when BEADS_DB names this path in this build" ready
expect_beads_db_refusal beads-db-trailing-slash-unported BEADS_DB=db/.beads/ "" \
	"Error: where is not available yet when BEADS_DB names this path in this build" where
expect_beads_db_refusal beads-db-where-missing-path-unported BEADS_DB=missing/beads.db "" \
	"Error: where is not available yet when BEADS_DB names this path in this build" where
expect_beads_db_refusal beads-db-where-bd-db-json-unported BD_DB=missing \
	'{"error":"where is not available yet when BD_DB names this path in this build","schema_version":1}' "" where --json
move_workspace_without_database() {
	move_workspace_to_db "$1"
	rm -rf "$1/work/db/.beads/embeddeddolt"
}
candidate_only_setup=move_workspace_without_database
expect_beads_db_refusal beads-db-workspace-without-database-unported BEADS_DB=db/.beads "" \
	"Error: count is not available yet when BEADS_DB names this path in this build" count
candidate_only_setup=""

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
	printf 'parity [%ss]: START watch/%s\n' "$SECONDS" "$name"
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
	printf 'parity [%ss]: PASS watch/%s\n' "$SECONDS" "$name"
}

compare_watch_refresh show update show "$real_database_content_id" --watch
compare_watch_refresh list update list --watch --limit 0
compare_watch_refresh list-cap row-cap list --watch --label alpha --limit 0 --max-rows 1

json_deprecation='NOTE: bd --json output format will change in v2.0. Set BD_JSON_ENVELOPE=1 to opt in early. See docs/reference/json-schema.md for migration details.'

run_json_stderr_terminal() {
	local name="$1"
	printf 'parity [%ss]: START terminal/%s\n' "$SECONDS" "$name"
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
	printf 'parity [%ss]: PASS terminal/%s-json-legacy\n' "$SECONDS" "$implementation"

	run_json_stderr_terminal "$implementation-json-envelope" "$binary" 1
	if tr -d '\r' <"$test_root/$implementation-json-envelope.terminal" | \
		grep -Fq "$json_deprecation"; then
		printf '%s emitted the legacy JSON notice with BD_JSON_ENVELOPE=1\n' \
			"$implementation" >&2
		exit 1
	fi
	printf 'parity [%ss]: PASS terminal/%s-json-envelope\n' "$SECONDS" "$implementation"
done

printf 'oracle: %s\n' "$oracle_identity"
printf 'candidate: %s\n' "$candidate_identity"
printf 'parity identity smoke: PASS\n'
printf 'no-workspace differential: PASS (%s command forms)\n' "$no_workspace_case_count"
printf 'store-failure differentials: PASS (%s cases)\n' "$store_failure_case_count"
printf 'real-database differentials: PASS (%s cases; ping timings normalized)\n' "$real_database_case_count"
printf 'candidate-only checks: PASS (%s cases; views not ported yet fail the same way)\n' "$candidate_only_case_count"
printf 'watch differentials: PASS (%s cases; poll change, refresh error, and signal lifecycle)\n' "$watch_case_count"
printf 'JSON terminal notice differential: PASS\n'
