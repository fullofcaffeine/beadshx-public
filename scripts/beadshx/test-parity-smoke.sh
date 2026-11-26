#!/usr/bin/env bash
set -euo pipefail
# A directory that a case makes with mkdir gets mode 0755, whatever the caller's umask is. Upstream warns
# about a selected .beads directory that group or others can read, so each run must compare the same
# modes. The workspace fixtures set their .beads mode themselves (see real_database_beads_mode).
umask 022

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
# The exact stderr that both sides of a version case must print; empty by default.
version_expected_stderr=""
# When set, a no-workspace case compares stderr as a root flag error: see compare_root_usage_error.
no_workspace_root_usage=""
# When set, each side of a no-workspace case must print its own root help: see compare_root_help.
no_workspace_root_help=""

# Keeps the first line of a root flag error and replaces the root usage after it with one marker
# line. Any other text stays, so a missing usage or a second error line differs.
normalize_root_usage() {
	awk 'NR == 1 { print; next } NR == 2 && $0 == "Usage:" { print "<root usage>"; exit } { print }' "$1"
}

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
	if [[ -n "$no_workspace_root_help" ]]; then
		# The root help names each binary and lists its own commands, so each side's stdout must be
		# what that side prints for --help in the same environment.
		local side side_binary
		for side in oracle candidate; do
			side_binary="$oracle"
			[[ "$side" == candidate ]] && side_binary="$candidate"
			(
				cd "$case_root/$side/work"
				env HOME="$case_root/$side/home" \
					XDG_CONFIG_HOME="$case_root/$side/config" \
					BEADS_TELEMETRY_DISABLED=1 \
					BEADS_NO_AUTO_FLUSH=1 \
					BD_DISABLE_METRICS=1 \
					BD_DISABLE_EVENT_FLUSH=1 \
					BD_JSON_ENVELOPE="${BEADSHX_TEST_JSON_ENVELOPE:-0}" \
					NO_COLOR=1 \
					"${no_workspace_extra_env[@]}" \
					"$side_binary" --help
			) >"$case_root/$side.help" 2>/dev/null
			if ! cmp -s "$case_root/$side.stdout" "$case_root/$side.help"; then
				printf '%s %s stdout is not its root help\n' "$name" "$side" >&2
				diff -u "$case_root/$side.help" "$case_root/$side.stdout" >&2 || true
				return 1
			fi
		done
	elif ! cmp -s "$case_root/oracle.stdout" "$case_root/candidate.stdout"; then
		printf '%s stdout differs from upstream\n' "$name" >&2
		diff -u "$case_root/oracle.stdout" "$case_root/candidate.stdout" >&2 || true
		return 1
	fi
	local oracle_stderr="$case_root/oracle.stderr" candidate_stderr="$case_root/candidate.stderr"
	if [[ -n "$no_workspace_root_usage" ]]; then
		oracle_stderr="$case_root/oracle.stderr.normalized"
		candidate_stderr="$case_root/candidate.stderr.normalized"
		normalize_root_usage "$case_root/oracle.stderr" >"$oracle_stderr"
		normalize_root_usage "$case_root/candidate.stderr" >"$candidate_stderr"
	fi
	if ! cmp -s "$oracle_stderr" "$candidate_stderr"; then
		printf '%s stderr differs from upstream\n' "$name" >&2
		diff -u "$oracle_stderr" "$candidate_stderr" >&2 || true
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

# A flag error on the root command (no command found) prints cobra's root usage after the error.
# The root usage lists each build's own commands, so these cases compare the exit code, stdout and
# the error line exactly, and require the usage right after the error on both sides.
compare_root_usage_error() {
	no_workspace_root_usage=1
	compare_no_workspace "$@"
	no_workspace_root_usage=""
}

# Without a command the root prints its help. Such a case compares the exit code and stderr, and
# requires each side to print exactly its own --help output.
compare_root_help() {
	no_workspace_root_help=1
	compare_no_workspace "$@"
	no_workspace_root_help=""
}

# `version` prints each binary's own identity, so these no-workspace cases compare only the output
# mode: both sides print a JSON object with schema_version 1 (json), or one line that is not JSON
# (text), with exit 0, the stderr in version_expected_stderr (empty by default) and no file written.
# They take the same extra environment and user config.yaml as compare_no_workspace.
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
		if [[ "$side_exit" -ne 0 || "$(cat "$case_root/$side.stderr")" != "$version_expected_stderr" ]]; then
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
compare_no_workspace info_thanks info --thanks
compare_no_workspace info_thanks_json info --thanks --json
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
# `snapshot` is a recorded BeadsHX extension (engdocs/beadshx/program/exceptions.md), the one name that
# is exempt from the unknown-command comparison: upstream reports it as unknown and bdhx runs it. Both
# print the same root help, which does not list it. scripts/beadshx/test-snapshot.sh tests the artifact.
check_snapshot_extension() {
	local case_root="$test_root/snapshot-extension" status=0
	printf 'parity [%ss]: START extension/snapshot\n' "$SECONDS"
	mkdir -p "$case_root/home" "$case_root/config" "$case_root/work"
	local extension_env=(env HOME="$case_root/home" XDG_CONFIG_HOME="$case_root/config" BEADS_TELEMETRY_DISABLED=1
		BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1 BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1)
	(cd "$case_root/work" && "${extension_env[@]}" "$oracle" snapshot) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr" ||
		status=$?
	if [[ "$status" -ne 1 || -s "$case_root/oracle.stdout" ||
		"$(cat "$case_root/oracle.stderr")" != $'Error: unknown command "snapshot" for "bd"\nRun \'bd --help\' for usage.' ]]; then
		printf 'upstream no longer reports snapshot as an unknown command; review the extension\n' >&2
		return 1
	fi
	(cd "$case_root/work" && "${extension_env[@]}" "$candidate" snapshot --help) >"$case_root/candidate.stdout" 2>"$case_root/candidate.stderr"
	if [[ -s "$case_root/candidate.stderr" || "$(head -n 1 "$case_root/candidate.stdout")" != 'Print a read-only snapshot of every issue in the embedded workspace.' ]]; then
		printf 'bdhx snapshot --help does not describe the extension\n' >&2
		return 1
	fi
	(cd "$case_root/work" && "${extension_env[@]}" "$candidate" --help) >"$case_root/root-help.stdout"
	if grep -Fq snapshot "$case_root/root-help.stdout"; then
		printf 'the bdhx root help lists the hidden snapshot command\n' >&2
		return 1
	fi
	if [[ -n "$(find "$case_root/home" "$case_root/config" "$case_root/work" -mindepth 1 -print -quit)" ]]; then
		printf 'the snapshot extension check wrote files\n' >&2
		return 1
	fi
	printf 'parity [%ss]: PASS extension/snapshot\n' "$SECONDS"
}
check_snapshot_extension
compare_no_workspace list_help list --help
compare_no_workspace help_list help list
# list refuses positional arguments (with a hint for a bare flag name) after flag parsing and --help,
# but before it looks for a workspace.
compare_no_workspace list_positional list foo
compare_no_workspace list_positional_hint_json list foo bar overdue --json
compare_no_workspace list_positional_after_dashes list -- tree
compare_no_workspace list_positional_unknown_flag list foo --bogus
compare_no_workspace list_positional_help list foo --help
compare_no_workspace help_list_positional help list foo
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
# pflag parses an int flag's value with strconv.ParseInt(value, 0, 64) as it reads the flag, before the
# pre-run: a bad value prints `invalid argument "x" for "-n, --limit" flag: strconv.ParseInt: ...` also
# with --json. Go's 0x, 0o, 0b, leading-zero octal, sign and `_` forms are values. A shorthand takes its
# value from the next argument or from the rest of its own, after an optional "=". A flag that the
# command lacks is an unknown flag, and the first error in argument order wins.
compare_no_workspace list_invalid_limit list --limit x
compare_no_workspace list_invalid_limit_shorthand_json list -n x --json
compare_no_workspace list_empty_limit list --limit=
compare_no_workspace list_empty_limit_shorthand list -n ''
compare_no_workspace list_limit_out_of_range list --limit 999999999999999999999
compare_no_workspace list_limit_quoted list --limit '"é'
compare_no_workspace list_invalid_limit_attached list -n5x
compare_no_workspace list_invalid_limit_shorthand_equals list -n=x
compare_no_workspace list_missing_limit_shorthand list -n
compare_no_workspace list_limit_go_syntax list --limit 0x10 -n 1_0 --limit=+5 -n010 -n=0b1
compare_no_workspace list_invalid_limit_before_command --limit x list
compare_no_workspace list_invalid_limit_before_unknown_flag list --limit x --bogus
compare_no_workspace list_invalid_offset_json list --offset=x --json
compare_no_workspace list_invalid_max_rows list --max-rows 1.5
compare_no_workspace list_bad_boolean_quoted list --all='"'
compare_no_workspace ready_invalid_limit_shorthand ready -n x
compare_no_workspace ready_empty_limit ready --limit=
compare_no_workspace ready_invalid_priority ready --priority P1
compare_no_workspace ready_invalid_priority_shorthand_json ready -p 1x --json
compare_no_workspace ready_invalid_priority_attached ready -px
compare_no_workspace ready_missing_priority_shorthand ready -p
compare_no_workspace ready_invalid_priority_before_unknown_flag ready -p x --title x
compare_no_workspace ready_invalid_offset ready --offset 0x
compare_no_workspace ready_invalid_max_rows ready --max-rows=x
compare_no_workspace count_invalid_priority count --priority P1
compare_no_workspace count_invalid_priority_shorthand_json count -p high --json
compare_no_workspace count_invalid_priority_attached count -p=x
compare_no_workspace count_missing_priority_shorthand count -p
compare_no_workspace count_invalid_priority_min count --priority-min P1
compare_no_workspace count_invalid_priority_max_json count --priority-max=high --json
compare_no_workspace count_priority_out_of_range count -p 99999999999999999999
compare_no_workspace count_priority_any_integer count -p 7 --priority-min -1 --priority-max=0x10
compare_no_workspace count_invalid_priority_before_command -p x count
compare_no_workspace count_invalid_priority_before_bad_boolean count --priority x --by-status=maybe
compare_no_workspace count_bad_boolean_before_priority count --by-status=maybe --priority x
compare_no_workspace count_invalid_priority_max_before_min count --priority-max=x --priority-min=y
compare_no_workspace count_unknown_offset count --offset x
compare_no_workspace search_invalid_limit_shorthand search foo -n x
compare_no_workspace search_invalid_limit search foo --limit=1.0
compare_no_workspace search_missing_limit_shorthand search foo -n
compare_no_workspace query_invalid_limit query status=open -n x
compare_no_workspace query_invalid_offset_json query status=open --offset x --json
compare_no_workspace stale_invalid_days stale -d x
compare_no_workspace stale_invalid_days_equals stale --days=x
compare_no_workspace stale_invalid_days_attached stale -dx
compare_no_workspace stale_missing_days_shorthand stale -d
compare_no_workspace stale_invalid_limit stale -n x
compare_no_workspace dep_tree_invalid_max_depth_attached dep tree test-a -dx
compare_no_workspace dep_tree_max_depth_out_of_range dep tree test-a --max-depth 99999999999999999999
compare_no_workspace dep_tree_invalid_max_depth_before_subcommand dep --max-depth x tree test-a
compare_no_workspace graph_empty_max_rows graph test-a --max-rows=
compare_no_workspace graph_check_unknown_max_rows graph check --max-rows x
compare_no_workspace history_limit_out_of_range history test-a --limit 99999999999999999999
compare_no_workspace history_unknown_limit_attached history test-a -n5
compare_no_workspace show_unknown_limit show test-a --limit x
compare_no_workspace help_list_unknown_limit help list --limit x
# Cobra finds the command before pflag parses a flag. pflag then reads the arguments in order with the
# flags of that command and stops at the first problem: a flag that the command lacks, a value that a
# flag rejects, or a flag with no value after it. A flag of another command is unknown, also with a
# bad value or no value, and `bd help` has none of them.
compare_no_workspace ready_unknown_title_before_invalid_priority ready --title x -p x
compare_no_workspace unknown_title_before_invalid_priority_before_command --title x -p x ready
compare_no_workspace ready_unknown_title_before_missing_priority ready --title x -p
compare_no_workspace ready_unknown_title_before_count_flag ready --title x --by-status
compare_no_workspace ready_unknown_title_before_bad_boolean ready --title x --pretty=maybe
compare_no_workspace ready_unknown_title_before_bad_json ready --title x --json=maybe
compare_no_workspace ready_unknown_title_before_unknown_flag ready --title x -p 1 --bogus
compare_no_workspace count_unknown_offset_before_invalid_priority count --offset x -p y
compare_no_workspace stale_unknown_title_before_invalid_days stale --title x -d x
compare_no_workspace list_unknown_count_flag_before_invalid_limit list --by-status --limit x
compare_no_workspace ready_unknown_query_before_invalid_limit ready --query x -n x
compare_no_workspace ready_unknown_days_before_invalid_limit ready --days 1 -n x
compare_no_workspace ready_unknown_days_shorthand ready -d 5
compare_no_workspace search_unknown_spec_before_invalid_limit search foo --spec x -n x
compare_no_workspace ready_unknown_details_bad_value ready --details=maybe
compare_no_workspace show_unknown_all_bad_value show test-a --all=maybe
compare_no_workspace ready_unknown_count_flag_bad_value ready --by-status=x
compare_no_workspace list_unknown_graph_flag_bad_value list --dot=x
compare_no_workspace ready_unknown_title_missing_value ready --title
compare_no_workspace show_unknown_limit_missing_value show test-a --limit
compare_no_workspace ready_unknown_status_flag ready --no-blocked
compare_no_workspace list_unknown_info_flag list --schema
compare_no_workspace ready_unknown_show_flag ready --short
compare_no_workspace ready_unknown_watch_false ready --watch=false
compare_no_workspace list_unknown_ready_claim list --claim
compare_no_workspace list_unknown_ready_unassigned_shorthand list -u
compare_no_workspace list_unknown_ready_molecule list --mol test-a
compare_no_workspace list_unknown_ready_plain_before_invalid_limit list --plain -n x
compare_no_workspace help_unknown_title help --title x
compare_no_workspace help_count_unknown_count_flag help count --by-status
compare_no_workspace events_tail_invalid_since_before_unknown_flag events tail --since x --bogus
compare_no_workspace events_unknown_limit_shorthand_before_subcommand events -n 5 tail
compare_no_workspace dep_tree_days_shorthand_before_command -d 5 dep tree test-a
# A shorthand that takes a value names the shorthand when no value follows, and takes the next
# argument even when it looks like a flag.
compare_no_workspace list_missing_type_shorthand list -t
compare_no_workspace list_missing_assignee_shorthand list -a
compare_no_workspace list_missing_label_shorthand list -l
compare_no_workspace count_missing_type_shorthand count -t
compare_no_workspace ready_missing_assignee_shorthand ready -a
compare_no_workspace search_missing_label_shorthand search foo -l
compare_no_workspace list_type_shorthand_takes_flag_value list -t --json
# An int shorthand with its value attached also works before the command, which pflag parses with
# the flags of the command that cobra found later in the arguments.
compare_no_workspace limit_shorthand_attached_before_command -n5 list
compare_no_workspace priority_shorthand_attached_before_command -p1 count
compare_no_workspace days_shorthand_attached_before_command -d5 stale
compare_no_workspace invalid_days_shorthand_attached_before_command -dx stale
compare_no_workspace limit_shorthand_attached_before_unknown_command -n5 bogus
compare_no_workspace limit_shorthand_attached_before_show -n5 show test-a
# An unknown command comes before every flag error. Cobra's command search takes the argument after
# a flag that it does not know as that flag's value, unless the flag has "=". Upstream's pre-run
# checks (this build's empty --actor and --dolt-auto-commit checks) come after both.
compare_no_workspace readonly_bad_value_unknown_command --readonly=maybe bogus
compare_no_workspace global_empty_value_unknown_command --global= bogus
compare_no_workspace json_bad_value_unknown_command --json=maybe bogus
compare_no_workspace cpu_profile_bad_value_unknown_command --cpu-profile=x bogus
compare_no_workspace unknown_command_before_bad_readonly bogus --readonly=maybe
compare_no_workspace unknown_command_before_count_flag bogus --by-status
compare_no_workspace unknown_command_before_missing_value bogus --title
compare_no_workspace unknown_attached_flag_unknown_command --bogus=1 bogus2
compare_no_workspace unknown_flag_value_before_command --bogus x ready
compare_no_workspace empty_actor_unknown_title --actor= ready --title x
compare_no_workspace empty_actor_unknown_command --actor= bogus
compare_no_workspace bad_auto_commit_unknown_title --dolt-auto-commit=x ready --title x
# Without a command, a flag error comes from the root command, which prints its usage after it.
compare_root_usage_error root_bad_readonly_help --readonly=maybe --help
compare_root_usage_error root_empty_global_help --global= --help
compare_root_usage_error root_bad_readonly --readonly=maybe
compare_root_usage_error root_bad_schema_skew_help --ignore-schema-skew=x --help
compare_root_usage_error root_unknown_flag_after_json --json --bogus
compare_root_usage_error root_unknown_limit_shorthand_attached -n5
compare_root_usage_error root_unknown_shorthand_takes_command -x list
compare_root_usage_error root_unknown_flag_takes_value --bogus x
compare_root_usage_error root_limit_shorthand_takes_command -n list
compare_root_usage_error root_unknown_title --title x
compare_root_usage_error root_unknown_all --all
compare_root_usage_error root_missing_directory_shorthand -C
compare_root_usage_error root_missing_db --db
compare_root_usage_error root_missing_actor --actor
# --version is the root's own bool flag: with a command it is unknown, and the root reports other flag
# errors with its usage.
compare_root_usage_error root_version_unknown_flag --version --bogus
compare_root_usage_error root_version_unknown_shorthand_attached --version -tbug
compare_root_usage_error root_version_bad_value --version=bogus
compare_no_workspace version_flag_with_command --version list
compare_no_workspace version_flag_after_command list --version
compare_no_workspace version_shorthand_after_command list -V
compare_no_workspace version_flag_extra_argument --version extra
compare_no_workspace version_flag_help_command help --version
compare_version_mode version_flag_true text --version=true
compare_version_mode version_shorthand_true text -V=true
compare_version_mode version_shorthand_group text -qV
compare_version_mode version_flag_empty_actor text --actor= --version
# Until cobra finds the command it knows only the root's flags, and takes the argument after any other
# --flag or -x as that flag's value, also after a bool flag of a command. pflag then reads that
# argument as a positional argument of the command found.
compare_root_usage_error root_all_takes_unknown_command --all bogus
compare_root_usage_error root_all_takes_command --all list
compare_root_usage_error root_reverse_shorthand_takes_command -r list
compare_root_usage_error root_version_all_takes_command --version --all list
compare_root_usage_error root_status_flag_takes_command --no-activity list
compare_no_workspace all_takes_command_before_unknown --all list extra
compare_no_workspace all_skipped_argument_is_positional --all bogus list
compare_no_workspace no_activity_on_list list --no-activity
# pflag reads -rt as -r and -t; -t takes the next argument, which the search still takes as the command.
compare_no_workspace shorthand_group_value_takes_command -rt list
# The search also takes a flag after such a flag as that flag's value, so the value of the second
# flag can name the command. pflag still reads both flags with the command found, without it.
compare_no_workspace flag_value_takes_flag_unknown_command --all --title frobnicate list
compare_no_workspace flag_value_takes_shorthand_unknown_command --all -t frobnicate list
compare_no_workspace flag_value_takes_flag_missing_value --all --title list
# The search stops at --. Without a command before it, the root runs, prints its help and ignores the
# arguments after it; pflag reads no flag after it either.
compare_root_help dashes_before_command -- list
compare_root_help dashes_before_command_json -- list --json
compare_root_help json_dashes_before_command --json -- list
compare_root_help dashes_before_unknown_command -- frobnicate
compare_root_help dashes_before_unknown_flag -- --bogus
compare_root_usage_error unknown_flag_dashes_before_command --title x -- list
compare_version_mode version_dashes_before_command text --version -- list
# Like upstream, an empty --actor is accepted.
compare_no_workspace empty_actor_list --actor= list
# In shared-server mode upstream's hint also names `bd doctor`. Without a workspace it reads the mode
# from BEADS_DOLT_SHARED_SERVER (1 or true in any case), BD_DOLT_SHARED_SERVER and the user
# config.yaml. Neither side writes.
compare_no_workspace_env list_shared_server BEADS_DOLT_SHARED_SERVER=1 list
compare_no_workspace_env count_json_shared_server BEADS_DOLT_SHARED_SERVER=TRUE count --json
compare_no_workspace_env config_get_database_shared_server BEADS_DOLT_SHARED_SERVER=1 config get issue_prefix
compare_no_workspace_env config_get_database_json_shared_server BD_DOLT_SHARED_SERVER=true config get issue_prefix --json
compare_no_workspace_env config_get_yaml_shared_server BEADS_DOLT_SHARED_SERVER=1 config get export.auto
compare_no_workspace_env config_list_shared_server BEADS_DOLT_SHARED_SERVER=1 config list
compare_no_workspace_env config_list_json_shared_server BD_DOLT_SHARED_SERVER=t config list --json
compare_no_workspace_env config_validate_shared_server BEADS_DOLT_SHARED_SERVER=1 config validate
compare_no_workspace_env config_validate_json_shared_server BEADS_DOLT_SHARED_SERVER=1 config validate --json
compare_no_workspace_env where_shared_server BEADS_DOLT_SHARED_SERVER=1 where
compare_no_workspace_env where_json_shared_server BD_DOLT_SHARED_SERVER=1 where --json
compare_no_workspace_user_config info_user_shared_server $'dolt:\n  shared-server: true' info
compare_no_workspace_user_config where_user_shared_server $'dolt:\n  shared-server: true' where
# Any other value of the variable leaves shared-server mode off.
compare_no_workspace_env list_shared_server_other_value BEADS_DOLT_SHARED_SERVER=yes list
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
# The mode of the .beads directory of each store-failure fixture.
store_failure_beads_mode=700
# More variable assignments for both sides of a store-failure case.
store_failure_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Names a function that prepares each side root (its argument) of a store-failure case after the
# scenario wrote its workspace, before the fixture is fingerprinted.
store_failure_setup=""
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
	unavailable-server | deprecated-port-server | stale-embedded-server | test-source-server | test-target-server | \
		redirect-server | redirect-proxied-server)
		metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads"}'
		if [[ "$scenario" == test-target-server ]]; then
			metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads_test_target"}'
		fi
		# metadata.json also names the server port, which upstream warns is deprecated.
		if [[ "$scenario" == deprecated-port-server ]]; then
			metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads","dolt_server_port":1}'
		fi
		config_yaml=$'issue-prefix: test\ndolt:\n  mode: server\n  auto-start: false'
		if [[ "$scenario" == redirect-proxied-server ]]; then
			metadata='{"backend":"dolt","dolt_mode":"proxied-server","dolt_database":"beads"}'
			config_yaml='issue-prefix: test'
		fi
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
		chmod "$store_failure_beads_mode" "$command_root/work/.beads"
		printf '%s\n' "$metadata" >"$command_root/work/.beads/metadata.json"
		printf '%s\n' "$config_yaml" >"$command_root/work/.beads/config.yaml"
		# A server workspace that still holds the directory of an earlier embedded store.
		if [[ "$scenario" == stale-embedded-server ]]; then
			mkdir "$command_root/work/.beads/embeddeddolt"
		fi
		# The workspace moves to target/.beads, and a workspace of the same mode redirects to it: with its own
		# dolt_database in test-source-server and test-target-server, and without one in the redirect scenarios.
		if [[ "$scenario" == test-source-server || "$scenario" == test-target-server || "$scenario" == redirect-* ]]; then
			local source_metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"source"}'
			case "$scenario" in
			test-source-server) source_metadata='{"backend":"dolt","dolt_mode":"server","dolt_database":"beads_test_source"}' ;;
			redirect-server) source_metadata='{"backend":"dolt","dolt_mode":"server"}' ;;
			redirect-proxied-server) source_metadata='{"backend":"dolt","dolt_mode":"proxied-server"}' ;;
			esac
			mkdir "$command_root/work/target"
			mv -f "$command_root/work/.beads" "$command_root/work/target/.beads"
			mkdir "$command_root/work/.beads"
			chmod "$store_failure_beads_mode" "$command_root/work/.beads"
			printf '%s\n' "$source_metadata" >"$command_root/work/.beads/metadata.json"
			printf '%s\n' "$config_yaml" >"$command_root/work/.beads/config.yaml"
			printf 'target/.beads\n' >"$command_root/work/.beads/redirect"
		fi
		if [[ -n "$store_failure_setup" ]]; then
			"$store_failure_setup" "$command_root"
		fi
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
			"${store_failure_extra_env[@]}" \
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
			"${store_failure_extra_env[@]}" \
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
	# A warning about the permissions of the .beads directory names each side's own workspace.
	local side side_work side_work_logical
	for side in oracle candidate; do
		side_work="$(cd "$case_root/$side/work" && pwd -P)"
		side_work_logical="$(cd "$case_root/$side/work" && pwd -L)"
		sed -e "s|$side_work|<work>|g" -e "s|$side_work_logical|<work>|g" \
			"$case_root/$side.stderr" >"$case_root/$side.stderr.normalized"
	done
	if ! cmp -s "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized"; then
		printf '%s/%s stderr differs from upstream\n' "$scenario" "$case_name" >&2
		diff -u "$case_root/oracle.stderr.normalized" "$case_root/candidate.stderr.normalized" >&2 || true
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
compare_store_failure missing-embedded info-thanks info --thanks
compare_store_failure unavailable-server info-thanks-json info --thanks --json
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
# A negative --offset, --pinned with --no-pinned and an unknown --sort value fail in the command body
# too, so the store-open error (or the missing database) comes first.
compare_store_failure unavailable-server list-negative-offset list --offset -1
compare_store_failure unavailable-server list-negative-offset-json list --offset -1 --json
compare_store_failure unavailable-server query-negative-offset query status=open --offset -1
compare_store_failure unavailable-server query-negative-offset-json query status=open --offset -1 --json
compare_store_failure unavailable-server list-pinned-conflict list --pinned --no-pinned
compare_store_failure unavailable-server list-pinned-conflict-json list --pinned --no-pinned --json
compare_store_failure unavailable-server list-bad-sort list --sort bogus
compare_store_failure unavailable-server list-bad-sort-json list --sort bogus --json
compare_store_failure unavailable-server ready-bad-sort ready --sort bogus
compare_store_failure unavailable-server ready-bad-sort-json ready --sort bogus --json
compare_store_failure missing-embedded list-bad-sort list --sort bogus
compare_store_failure missing-embedded query-negative-offset-json query status=open --offset -1 --json
# The other checks of list's gatherListInput, ready's --brief rules and its gather, and count's --by-*
# and date checks also run in the command body, after the store-open error.
compare_store_failure unavailable-server list-bad-priority list --priority bogus
compare_store_failure unavailable-server list-bad-priority-min-json list --priority-min bogus --json
compare_store_failure unavailable-server list-bad-priority-max list --priority-max 9
compare_store_failure unavailable-server list-bad-mol-type list --mol-type bogus
compare_store_failure unavailable-server list-bad-wisp-type-json list --wisp-type bogus --json
compare_store_failure unavailable-server list-bad-created-after list --created-after bogus
compare_store_failure unavailable-server list-bad-metadata-field-json list --metadata-field bad --json
compare_store_failure unavailable-server list-bad-has-metadata-key list --has-metadata-key 1bad
compare_store_failure unavailable-server list-negative-max-rows-json list --max-rows -1 --json
compare_store_failure unavailable-server list-brief-format list --brief --format '{{.ID}}'
compare_store_failure unavailable-server list-brief-parent list --brief --parent test-1
compare_store_failure unavailable-server ready-brief ready --brief
compare_store_failure unavailable-server ready-brief-gated-json ready --brief --gated --json
compare_store_failure unavailable-server ready-bad-mol-type-json ready --mol-type bogus --json
compare_store_failure unavailable-server ready-bad-metadata-field ready --metadata-field bad
compare_store_failure unavailable-server ready-bad-has-metadata-key-json ready --has-metadata-key 1bad --json
compare_store_failure unavailable-server ready-negative-max-rows-json ready --max-rows -1 --json
compare_store_failure unavailable-server readonly-ready-claim-gated --readonly ready --claim --gated
compare_store_failure unavailable-server count-by-conflict count --by-status --by-type
compare_store_failure unavailable-server count-by-conflict-json count --by-status --by-type --json
compare_store_failure unavailable-server count-bad-created-after-json count --created-after bogus --json
compare_store_failure missing-embedded list-bad-mol-type-json list --mol-type bogus --json
compare_store_failure missing-embedded list-negative-max-rows list --max-rows -1
compare_store_failure missing-embedded ready-brief-json ready --brief --explain --json
compare_store_failure missing-embedded ready-bad-metadata-field-json ready --metadata-field bad --json
compare_store_failure missing-embedded count-by-conflict-json count --by-status --by-label --json
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
compare_store_failure deprecated-port-server list-bad-sort list --sort bogus
compare_store_failure deprecated-port-server ready-bad-sort-json ready --sort bogus --json
compare_store_failure deprecated-port-server list-bad-priority list --priority bogus
compare_store_failure deprecated-port-server list-bad-due-before-json list --due-before bogus --json
compare_store_failure deprecated-port-server ready-brief-mol ready --brief --mol test-1
compare_store_failure deprecated-port-server ready-bad-mol-type ready --mol-type bogus
compare_store_failure deprecated-port-server count-by-conflict-json count --by-priority --by-assignee --json
# search checks its dates, priority range and metadata filters in its command body, and takes any
# --sort value, so the store-open error comes first.
compare_store_failure unavailable-server search-bad-sort search parity --sort bogus
compare_store_failure unavailable-server search-bad-sort-json search parity --sort bogus --json
compare_store_failure unavailable-server search-bad-created-after search parity --created-after bogus
compare_store_failure unavailable-server search-bad-priority-min-json search parity --priority-min 9 --json
compare_store_failure unavailable-server search-bad-metadata-field search parity --metadata-field bad
compare_store_failure unavailable-server search-bad-has-metadata-key-json search parity --has-metadata-key 1bad --json
compare_store_failure missing-embedded search-bad-closed-before search parity --closed-before bogus
# list refuses positional arguments before the pre-run, so that error comes first.
compare_store_failure unavailable-server list-positional list foo
compare_store_failure unavailable-server list-positional-hint-json list foo ready --json
compare_store_failure missing-embedded list-positional list foo
# A leftover .beads/embeddeddolt directory does not make a server workspace embedded: the store-open
# error still comes before the checks of the command body.
compare_store_failure stale-embedded-server list list
compare_store_failure stale-embedded-server list-bad-sort list --sort bogus
compare_store_failure stale-embedded-server ready-bad-sort-json ready --sort bogus --json
compare_store_failure stale-embedded-server count-by-conflict count --by-status --by-type
compare_store_failure stale-embedded-server search-no-query search
compare_store_failure stale-embedded-server search-bad-created-after-json search parity --created-after bogus --json
compare_store_failure stale-embedded-server query-negative-offset query status=open --offset -1
# The Haxe-owned embedded readers do not answer for such a workspace either: upstream reads it through
# its server, so blocked, dep cycles and graph check stop at the same store-open error. With a server
# that answers, bdhx reports that these views are not available yet instead of reading the directory.
compare_store_failure stale-embedded-server blocked blocked
compare_store_failure stale-embedded-server blocked-json blocked --json
compare_store_failure stale-embedded-server dep-cycles dep cycles
compare_store_failure stale-embedded-server graph-check-json graph check --json
compare_store_failure stale-embedded-server ready-explain ready --explain
compare_store_failure stale-embedded-server stale-json stale --days 1 --json
# Upstream keeps a redirecting workspace's dolt_database in BEADS_DOLT_SERVER_DATABASE in every store mode
# (preserveRedirectSourceDatabase, cmd/bd/main.go:496-508, :603, :1210). Its server open checks that name before
# it dials: it refuses a test-named database unless BEADS_TEST_SERVER=1 (internal/storage/dolt/store.go:1509).
# In test-source-server the redirecting workspace names beads_test_source and its target beads; in
# test-target-server the redirecting workspace names source and its target beads_test_target (beadshx-m08.53).
compare_store_failure test-source-server count count
compare_store_failure test-source-server list-json list --json
compare_store_failure test-source-server readonly-count --readonly count
compare_store_failure test-source-server info info
compare_store_failure test-source-server show show test-1
compare_store_failure test-source-server config-get config get issue_prefix
# With -C the pre-run binds the target before it looks for a redirect, so it keeps no name.
compare_store_failure test-source-server change-directory-count -C . count
compare_store_failure test-target-server count count
compare_store_failure test-target-server list-json list --json
compare_store_failure test-target-server readonly-count --readonly count
# With BD_DEBUG_ROUTING, upstream prints a line each time it follows a redirect. Its warnMultipleDatabases
# follows the redirects from the current directory up only after the store opens (cmd/bd/main.go:1688),
# so a server open that fails prints none of those lines. A proxied-server workspace never gets there
# (:1554-1577); its --global check fails at the store open. info --whats-new opens the store too.
store_failure_extra_env=(BD_DEBUG_ROUTING=1)
for scenario in redirect-server test-source-server test-target-server; do
	compare_store_failure "$scenario" routing-count count
	compare_store_failure "$scenario" routing-change-directory-count -C . count
	compare_store_failure "$scenario" routing-show-json show test-1 --json
	compare_store_failure "$scenario" routing-info info
	compare_store_failure "$scenario" routing-global-count --global count
done
compare_store_failure redirect-server routing-list list
compare_store_failure redirect-server routing-ready-json ready --json
compare_store_failure redirect-server routing-ping ping
compare_store_failure redirect-server routing-status-json status --json
compare_store_failure redirect-server routing-info-whats-new info --whats-new
compare_store_failure redirect-server routing-info-whats-new-global info --whats-new --global
compare_store_failure redirect-server routing-dep-tree dep tree test-1
compare_store_failure redirect-server routing-graph-all-json graph --all --json
compare_store_failure redirect-server routing-label-list-all label list-all
compare_store_failure redirect-server routing-config-get config get issue_prefix
compare_store_failure redirect-server routing-types types
compare_store_failure redirect-proxied-server routing-global-count --global count
compare_store_failure redirect-proxied-server routing-global-show-json show test-1 --global --json
compare_store_failure redirect-proxied-server routing-global-config-get --global config get issue_prefix
compare_store_failure redirect-proxied-server routing-readonly-count --readonly count
store_failure_extra_env=(BEADSHX_PARITY_EXTRA=1)

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
real_database_grandchild_id="$(jq -er '.id' "$real_database_seed/grandchild.json")"
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
# A directory below the work directory that a database case starts in instead of the work directory.
real_database_directory=""
# The mode of the work/.beads directory of each database and candidate-only case, set before its setup.
real_database_beads_mode=700
# When set, a database case also requires the upstream command to leave its task state unchanged,
# and gives each side an empty TMPDIR that must stay empty.
real_database_read_only=""
real_database_case_count=0
real_database_out_of_memory_count=0
candidate_only_case_count=0
# Names a function that prepares one candidate-only state root (its argument) before the run.
candidate_only_setup=""
# The exit code that a candidate-only case expects: 1, for a refusal, unless a case reads normally.
candidate_only_exit=1
printf 'parity [%ss]: PASS database fixture setup\n' "$SECONDS"

# Upstream's thanks page (cmd/bd/thanks.go) sorts its contributor map by commit count with an unstable
# sort, so contributors with the same count print in a random order. This reads a page's names in their
# order, requires each contributor once with the counts never rising, and requires the rows and wrapped
# lines that upstream's layout gives for that order. It then prints the page with the names in one order:
# by count, then as upstream's source lists them.
thanks_page_python='
import re
import sys

source, page = sys.argv[1], sys.argv[2]
table = re.findall(r"^\t\"([^\"]+)\":\s+(\d+),$", open(source, encoding="utf-8").read(), re.M)
commits = {name: int(count) for name, count in table}
rank = {name: index for index, (name, _) in enumerate(table)}
lines = open(page, encoding="utf-8").read().split("\n")
sgr = re.compile(r"\x1b\[[0-9;]*m")
plain = [sgr.sub("", line) for line in lines]
featured_at = plain.index("  Featured Contributors")
additional_at = plain.index("  Additional Contributors")
rows = slice(featured_at + 2, additional_at - 1)
wrapped = slice(additional_at + 2, len(lines) - 2)
if plain[additional_at - 1] != "" or plain[len(lines) - 2:] != ["", ""]:
    sys.exit("the page does not end as upstream'"'"'s does")


def full_name(shown):
    if shown in commits:
        return shown
    cut = [name for name in commits if len(name.encode()) > 20 and name.encode()[:17].decode() + "..." == shown]
    if len(cut) != 1:
        sys.exit("unknown contributor: " + repr(shown))
    return cut[0]


def style_of(line):
    codes = sgr.findall(line)
    return (codes[0], codes[1]) if codes else ("", "")


order = [full_name(shown) for row in plain[rows] for shown in re.split(r" {2,}", row[2:].rstrip(" "))]
order += [full_name(shown) for shown in "".join(line[2:] for line in plain[wrapped]).split(", ")]
if sorted(order) != sorted(commits):
    sys.exit("the page does not name each contributor once")
if any(commits[left] < commits[right] for left, right in zip(order, order[1:])):
    sys.exit("the page does not sort the contributors by commit count")
name_open, name_close = style_of(lines[rows][0])
dim_open, dim_close = style_of(lines[wrapped][0])


def render(names):
    featured, rest = names[:20], names[20:]
    width = min(max(len(name.encode()) for name in featured), 20) + 2
    cells = [name if len(name.encode()) <= 20 else name.encode()[:17].decode() + "..." for name in featured]
    columns = ["  " + "".join(name_open + cell + " " * (width - len(cell)) + name_close for cell in cells[at:at + 4])
               for at in range(0, len(cells), 4)]
    out, line, length = [], "  ", 2
    for index, name in enumerate(rest):
        entry = name + (", " if index < len(rest) - 1 else "")
        if length + len(entry.encode()) > width * 4 + 4 and length > 2:
            out.append(line)
            line, length = "  ", 2
        line += dim_open + entry + dim_close
        length += len(entry.encode())
    return columns, out + [line]


if render(order) != (lines[rows], lines[wrapped]):
    sys.exit("the rows differ from upstream'"'"'s layout for the same order")
columns, rest = render(sorted(order, key=lambda name: (-commits[name], rank[name])))
sys.stdout.write("\n".join(lines[:rows.start] + columns + lines[rows.stop:wrapped.start] + rest + lines[wrapped.stop:]))
'

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
		chmod "$real_database_beads_mode" "$state_root/work/.beads"
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
		cd "$oracle_root/work${real_database_directory:+/$real_database_directory}"
		env HOME="$oracle_root/user-home" \
			XDG_CONFIG_HOME="$oracle_root/config" \
			"${oracle_temporary[@]}" \
			"${real_database_env[@]}" \
			"${oracle_extra_env[@]}" \
			"$oracle" "$@"
	) >"$case_root/oracle.stdout" 2>"$case_root/oracle.stderr"
	oracle_exit=$?
	(
		cd "$candidate_root/work${real_database_directory:+/$real_database_directory}"
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

	# An upstream run that cannot finish for lack of memory gives no answer to compare. A very
	# large row cap makes Dolt reserve memory in proportion to the cap, so on a small CI runner
	# both sides die with Go's out-of-memory error and only their stack traces differ. Skip the
	# case only when both sides ran out of memory, and report it; one side alone still fails.
	if grep -q '^fatal error: runtime: out of memory' "$case_root/oracle.stderr" &&
		grep -q '^fatal error: runtime: out of memory' "$case_root/candidate.stderr"; then
		real_database_out_of_memory_count=$((real_database_out_of_memory_count + 1))
		printf 'parity [%ss]: SKIP database/%s (upstream and candidate both ran out of memory)\n' "$SECONDS" "$name"
		return 0
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
	# A metadata.json load warning names each side's own workspace. Dolt's logrus warnings carry the time
	# of each side's own run.
	sed -e "s|$oracle_work|<work>|g" -e "s|$oracle_work_logical|<work>|g" -e 's/^time="[^"]*" /time="<time>" /' \
		"$case_root/oracle.stderr" >"$case_root/oracle.stderr.normalized"
	sed -e "s|$candidate_work|<work>|g" -e "s|$candidate_work_logical|<work>|g" -e 's/^time="[^"]*" /time="<time>" /' \
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
	thanks-page)
		for side in oracle candidate; do
			if ! python3 -I -c "$thanks_page_python" "$repository_root/cmd/bd/thanks.go" "$case_root/$side.stdout" \
				>"$case_root/$side.normalized" 2>"$case_root/$side.thanks-error"; then
				printf '%s %s stdout is not a thanks page in upstream'"'"'s layout: %s\n' \
					"$name" "$side" "$(cat "$case_root/$side.thanks-error")" >&2
				cat "$case_root/$side.stdout" >&2
				return 1
			fi
		done
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after ordering the tied contributors\n' "$name" >&2
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
		if ! cmp -s "$case_root/oracle.normalized" "$case_root/candidate.normalized"; then
			printf '%s stdout differs from upstream after normalizing the ping timing\n' "$name" >&2
			diff -u "$case_root/oracle.normalized" "$case_root/candidate.normalized" >&2 || true
			return 1
		fi
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
	chmod "$real_database_beads_mode" "$state_root/work/.beads"
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
	# A warning that names the workspace names it as <work>, and one that names
	# its parent (the candidate state root) names it as <state>.
	local candidate_state
	candidate_state="$(cd "$state_root" && pwd -P)"
	actual_stderr="$(sed -e "s|$candidate_work|<work>|g" -e "s|$candidate_work_logical|<work>|g" \
		-e "s|$candidate_state|<state>|g" "$case_root/candidate.stderr")"
	if [[ "$candidate_exit" -ne "$candidate_only_exit" || "$actual_stdout" != "$expected_stdout" ||
		"$actual_stderr" != "$expected_stderr" ]]; then
		printf '%s: expected exit %s, stdout [%s], stderr [%s]; got exit %s, stdout [%s], stderr [%s]\n' \
			"$name" "$candidate_only_exit" "$expected_stdout" "$expected_stderr" "$candidate_exit" \
			"$actual_stdout" "$actual_stderr" >&2
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
# info --thanks prints upstream's thank-you page once the pre-run has opened the store. Upstream checks it
# before --whats-new and prints the page in every output mode. Its text styles take internal/ui's colors
# when the process starts, so --no-color, which the pre-run reads later, leaves them on; the box style
# reads them when it renders, so --no-color turns off the color of the border.
compare_real_database info-thanks thanks-page info --thanks
compare_real_database info-thanks-json thanks-page info --thanks --json
compare_real_database info-thanks-whats-new thanks-page info --whats-new --thanks extra
compare_real_database info-thanks-true thanks-page info --thanks=true
compare_real_database info-thanks-false-schema-json exact info --thanks=false --schema=1 --json
compare_real_database info-whats-new-false-json exact info --whats-new=false --json
compare_real_database info-thanks-bad-value exact info --thanks=maybe
compare_real_database list-thanks-unknown exact list --thanks
compare_real_database list-schema-value-unknown exact list --schema=true
real_database_extra_env=(NO_COLOR= CLICOLOR_FORCE=1)
compare_real_database info-thanks-color thanks-page info --thanks
compare_real_database info-thanks-color-no-color-flag thanks-page --no-color info --thanks
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
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
# A Dolt directory config.yaml that Dolt cannot decode, or whose listener port is 0 or less, names no
# server port, so the dial still goes to port 0.
write_unknown_key_dolt_config() {
	mkdir -p "$1/work/.beads/dolt"
	printf 'unknown_key: 1\n' >"$1/work/.beads/dolt/config.yaml"
}
real_database_setup=write_unknown_key_dolt_config
compare_real_database config-validate-dolt-config-unknown-key exact config validate
compare_real_database config-drift-dolt-config-unknown-key exact config drift
write_zero_port_dolt_config() {
	mkdir -p "$1/work/.beads/dolt"
	printf 'listener:\n  port: 0\n' >"$1/work/.beads/dolt/config.yaml"
}
real_database_setup=write_zero_port_dolt_config
compare_real_database config-validate-dolt-config-port-zero exact config validate
compare_real_database config-drift-dolt-config-port-zero-json exact config drift --json
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
# Human `bd info` ends with upstream's warning about the bd hooks that CheckGitHooks finds missing
# or outdated, in the same hooks directory; outside a git repository all five are missing. --json
# prints no warning.
compare_real_database info-hooks-missing exact info
compare_real_database info-schema-hooks-missing exact info --schema
real_database_setup=write_drift_hooks
drift_hook_content=$'#!/bin/sh\n# bd-shim v1\nexec bd hooks run'
compare_real_database info-hooks-shim exact info
drift_hook_content=$'#!/bin/sh\n# bd-hooks-version: 0.9.0'
compare_real_database info-hooks-legacy exact info
compare_real_database info-hooks-legacy-json exact info --json
drift_hook_content=$'#!/bin/sh\n# bd-hooks-version: 1.2.1'
compare_real_database info-hooks-current exact info
drift_hook_content=$'#!/bin/sh\n# bd (beads)\nbd sync'
compare_real_database info-hooks-inline exact info
drift_hook_content=$'#!/bin/sh\necho hi'
compare_real_database info-hooks-foreign exact info
real_database_setup=write_mixed_hooks
compare_real_database info-schema-hooks-mixed exact info --schema
real_database_setup=use_relative_hooks_path
compare_real_database info-hooks-path exact info
real_database_setup=remove_git_checkout
compare_real_database info-not-git exact info
compare_real_database info-not-git-json exact info --json
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
# Upstream asks for the user's role (git config --get beads.role in the current directory) before
# list, ready and children read issues, and when show, comments, dep list or dep tree look up an ID
# that they do not find. Without maintainer or contributor there, it prints a three-line warning on
# stderr each time, also with --json. The fixture's Git repository sets the role; without it, the
# disposable HOME and XDG_CONFIG_HOME set none.
real_database_setup=remove_git_checkout
compare_real_database role-warning-list exact list
compare_real_database role-warning-list-json exact list --json
compare_real_database role-warning-ready exact ready
compare_real_database role-warning-ready-json exact ready --json
compare_real_database role-warning-children exact children "$real_database_epic_id"
compare_real_database role-warning-children-missing exact children test-missing
compare_real_database role-warning-show-missing exact show test-missing
compare_real_database role-warning-show-missing-json exact show test-missing --json
compare_real_database role-warning-show-short-missing exact show test-missing --short
compare_real_database role-warning-show-each-missing exact show "$real_database_issue_id" test-missing test-gone
compare_real_database role-warning-show-thread-missing exact show --thread test-missing
compare_real_database role-warning-show-refs-missing exact show --refs test-missing
compare_real_database role-warning-show-children-missing exact show --children test-missing
compare_real_database role-warning-show-watch-missing exact show --watch test-missing
compare_real_database role-warning-comments-missing exact comments test-missing
compare_real_database role-warning-dep-list-missing exact dep list test-missing
compare_real_database role-warning-dep-list-batch exact dep list "$real_database_issue_id" test-missing
compare_real_database role-warning-dep-tree-missing exact dep tree test-missing --json
# The BEADS_MAX_ROWS warning and the argument checks come first; a check that fails prints no warning.
compare_real_database_env role-warning-after-max-rows-warning exact BEADS_MAX_ROWS=banana ready
compare_real_database role-warning-list-check-first exact list --priority 9
compare_real_database role-warning-list-max-rows-first exact list --max-rows -1
# Other reads and a found ID ask for no role.
compare_real_database role-warning-none-show exact show "$real_database_issue_id"
compare_real_database role-warning-none-count exact count
compare_real_database role-warning-none-graph-missing exact graph test-missing
compare_real_database role-warning-none-label-missing exact label list test-missing
compare_real_database role-warning-none-ready-explain exact ready --explain
# The role counts from any config that Git reads: here the user's global config.
set_global_role() {
	remove_git_checkout "$1"
	printf '[beads]\n\trole = contributor\n' >"$1/user-home/.gitconfig"
}
real_database_setup=set_global_role
compare_real_database role-global-config-list exact list
# Upstream accepts only maintainer and contributor.
set_unknown_role() {
	git -C "$1/work" config beads.role admin
}
real_database_setup=set_unknown_role
compare_real_database role-unknown-value-list exact list
# A jj secondary workspace has no Git repository; upstream then asks the primary workspace that its
# .jj/repo file names, relative to .jj or absolute.
make_jj_secondary_workspace() {
	remove_git_checkout "$1"
	mkdir -p "$1/primary/.jj/repo" "$1/work/.jj"
	git -C "$1/primary" init -q
	git -C "$1/primary" config beads.role "$2"
	printf '%s\n' "$3" >"$1/work/.jj/repo"
}
jj_secondary_relative() { make_jj_secondary_workspace "$1" maintainer ../../primary/.jj/repo; }
jj_secondary_absolute() { make_jj_secondary_workspace "$1" contributor "$1/primary/.jj/repo"; }
jj_secondary_unknown_role() { make_jj_secondary_workspace "$1" admin ../../primary/.jj/repo; }
real_database_setup=jj_secondary_relative
compare_real_database role-jj-primary-relative exact list
real_database_setup=jj_secondary_absolute
compare_real_database role-jj-primary-absolute exact show test-missing
real_database_setup=jj_secondary_unknown_role
compare_real_database role-jj-primary-unknown exact ready
real_database_setup=""
# In shared-server mode, or with a configured server address or port, upstream connects to that
# server or creates state for it; bdhx refuses before it dials or opens anything.
enable_shared_server() {
	printf 'dolt:\n  shared-server: true\n' >>"$1/work/.beads/config.yaml"
}
# In shared-server mode upstream's setup for the workspace it selects first prints this notice on
# stderr when metadata.json pins dolt_mode embedded, as the fixture's does; bdhx prints it before
# its refusals too.
shared_server_notice='Notice: shared-server mode is enabled (BEADS_DOLT_SHARED_SERVER or dolt.shared-server in config.yaml) but .beads/metadata.json pins dolt_mode="embedded". Using the shared server for this run.
  To persist server mode: set dolt_mode to "server" in .beads/metadata.json and commit it.
  To stay embedded: unset BEADS_DOLT_SHARED_SERVER (or remove dolt.shared-server from config.yaml).'
candidate_only_setup=enable_shared_server
expect_candidate_failure config-validate-shared-server-unported "" \
	"$shared_server_notice"$'\n'"Error: config validate is not available yet in shared-server mode in this build" "" config validate
expect_candidate_failure config-drift-shared-server-unported \
	'{"error":"config drift is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" \
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
# A Dolt directory config.yaml that Dolt decodes names its listener port, 3306 by default.
write_portless_dolt_config() {
	mkdir -p "$1/work/.beads/dolt"
	printf 'log_level: info\n' >"$1/work/.beads/dolt/config.yaml"
}
candidate_only_setup=write_portless_dolt_config
expect_candidate_failure config-validate-dolt-config-default-port-unported "" \
	"Error: config validate is not available yet when a Dolt server endpoint is configured in this build" "" config validate
candidate_only_setup=""
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
	"$shared_server_notice"$'\n'"Error: config get is not available yet in shared-server mode in this build" "" config get issue_prefix
expect_candidate_failure config-get-yaml-shared-server-json-unported \
	'{"error":"config get is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" \
	config get routing.mode --json
expect_candidate_failure config-list-shared-server-unported "" \
	"$shared_server_notice"$'\n'"Error: config list is not available yet in shared-server mode in this build" "" config list
expect_candidate_failure config-list-shared-server-json-unported \
	'{"error":"config list is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" \
	config list --json
expect_candidate_failure config-show-shared-server-unported "" \
	"$shared_server_notice"$'\n'"Error: config show is not available yet in shared-server mode in this build" "" config show
expect_candidate_failure config-show-shared-server-json-unported \
	'{"error":"config show is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" \
	config show --json
# The notice also comes before the --database check, which upstream reaches after it has written.
expect_candidate_failure config-get-database-flag-shared-server-notice "" \
	"$shared_server_notice"$'\n'"Error: --database (or a --db value naming a database) is only supported in proxied-server mode" "" \
	config get issue_prefix --database other
candidate_only_setup=""
# Upstream also turns shared-server mode on from config.local.yaml and from both variables.
enable_local_shared_server() {
	printf 'dolt:\n  shared-server: true\n' >"$1/work/.beads/config.local.yaml"
}
candidate_only_setup=enable_local_shared_server
expect_candidate_failure config-show-local-shared-server-unported "" \
	"$shared_server_notice"$'\n'"Error: config show is not available yet in shared-server mode in this build" "" config show
candidate_only_setup=""
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure config-get-shared-server-env-unported "" \
	"$shared_server_notice"$'\n'"Error: config get is not available yet in shared-server mode in this build" "" config get beads.role
real_database_extra_env=(BD_DOLT_SHARED_SERVER=true)
expect_candidate_failure config-list-shared-server-bd-env-unported "" \
	"$shared_server_notice"$'\n'"Error: config list is not available yet in shared-server mode in this build" "" config list
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Without a database upstream finds none and writes nothing (see the database cases below). It opens
# the database that a --db path names, so config get refuses that even for a key that needs no
# database, and config show would create an embedded database.
enable_shared_server_without_database() {
	enable_shared_server "$1"
	remove_embedded_database "$1"
}
candidate_only_setup=enable_shared_server_without_database
expect_candidate_failure config-get-db-path-shared-server-no-database-unported "" \
	"$shared_server_notice"$'\n'"Error: config get is not available yet in shared-server mode in this build" "" \
	--db .beads config get routing.mode
expect_candidate_failure config-show-shared-server-no-database-unported "" \
	"$shared_server_notice"$'\n'"Error: config show is not available yet for a workspace without a database in this build" "" \
	config show
expect_candidate_failure config-validate-shared-server-no-database-unported "" \
	"$shared_server_notice"$'\n'"Error: config validate is not available yet in shared-server mode in this build" "" \
	config validate
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
# JSON on stdout when the arguments include --json. A set store_refusal_notice is the stderr that
# comes before it.
store_refusal_notice=""
expect_store_refusal() {
	local name="$1"
	local message="$3 is not available yet $2 in this build"
	shift 3
	local notice_lines=""
	if [[ -n "$store_refusal_notice" ]]; then
		notice_lines="$store_refusal_notice"$'\n'
	fi
	if [[ " $* " == *" --json "* ]]; then
		expect_candidate_failure "$name" "{\"error\":\"$message\",\"schema_version\":1}" "$store_refusal_notice" "" "$@"
	else
		expect_candidate_failure "$name" "" "${notice_lines}Error: $message" "" "$@"
	fi
}
shared_reason="in shared-server mode"
store_refusal_notice="$shared_server_notice"
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
# The refusal stands for upstream's pre-run, so it comes before the command body's argument checks.
expect_store_refusal list-bad-sort-shared-server-unported "$shared_reason" list list --sort bogus
expect_store_refusal ready-bad-sort-shared-server-json-unported "$shared_reason" ready ready --sort bogus --json
expect_store_refusal query-negative-offset-shared-server-unported "$shared_reason" query query status=open --offset -1
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
# Upstream opens the database that a --db path names, also in a workspace without one.
candidate_only_setup=enable_shared_server_without_database
expect_store_refusal count-db-path-shared-server-no-database-json-unported "$shared_reason" count --db .beads count --json
candidate_only_setup=""
store_refusal_notice=""
enable_shared_server_without_database_or_mode() {
	enable_shared_server_without_database "$1"
	jq 'del(.dolt_mode)' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
# Without dolt_mode no notice prints, and a --db path still makes upstream reach the shared server.
candidate_only_setup=enable_shared_server_without_database_or_mode
expect_store_refusal config-get-db-path-shared-server-no-mode-unported "$shared_reason" "config get" \
	--db .beads config get routing.mode
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
# In shared-server mode the selected-workspace setup prints a three-line notice on stderr when
# metadata.json pins dolt_mode embedded, as the fixture's does (case and surrounding space do not
# count): for where, version, the root help and `bd help`, but not for a --help flag or a command
# group. where still reads the prefix from the embedded database, unless BEADS_DOLT_SHARED_SERVER or
# dolt_mode server makes the workspace a server workspace. Neither side writes.
real_database_setup=enable_shared_server
compare_real_database shared-server-notice-where exact where
compare_real_database shared-server-notice-where-json exact where --json
compare_real_database shared-server-notice-directory-where exact -C . where
compare_real_database shared-server-notice-version stderr-only version
compare_real_database shared-server-notice-version-json stderr-only version --json
compare_real_database shared-server-notice-root stderr-only
compare_real_database shared-server-notice-help-command exact help count
real_database_setup=enable_local_shared_server
compare_real_database shared-server-notice-local-where exact where
real_database_setup=enable_user_shared_server
compare_real_database shared-server-notice-user-where-json exact where --json
real_database_setup=""
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database shared-server-notice-env-where exact where
compare_real_database shared-server-notice-env-help-command exact help ready
real_database_extra_env=(BD_DOLT_SHARED_SERVER=true)
compare_real_database shared-server-notice-bd-env-where-json exact where --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=enable_shared_server
compare_real_database_metadata shared-server-notice-mode-spelling exact '.dolt_mode = " Embedded "' where
compare_real_database_metadata shared-server-no-mode-where exact 'del(.dolt_mode)' where
compare_real_database_metadata shared-server-server-mode-where-json exact '.dolt_mode = "server"' where --json
real_database_setup=enable_shared_server_without_database
compare_real_database shared-server-notice-no-database-where exact where
# A BEADS_DB, BD_DB or db setting path makes where, version and help pages set up the directory that
# upstream derives from the path: a parent .beads directory with metadata.json, a workspace that
# claims the path, or else the first .beads directory above the path's directory. They print the
# notice for that directory.
real_database_setup=enable_shared_server
real_database_extra_env=("BEADS_DB=<work>/.beads")
compare_real_database shared-server-notice-beads-db-version stderr-only version
compare_real_database shared-server-notice-beads-db-help-command exact help count
compare_real_database shared-server-notice-beads-db-root stderr-only
real_database_extra_env=(BD_DB=.beads/embeddeddolt)
compare_real_database shared-server-notice-bd-db-version-json stderr-only version --json
real_database_extra_env=(BD_DB=.beads/beads.db)
compare_real_database shared-server-notice-bd-db-file-help-command exact help ready
real_database_extra_env=(BEADS_DB=../work/sub/beads.db)
compare_real_database shared-server-notice-beads-db-above-version stderr-only version
# A path that selects no workspace sets up a directory without metadata.json: no notice.
real_database_extra_env=(BEADS_DB=.beads/sub/beads.db)
compare_real_database shared-server-notice-beads-db-elsewhere-version stderr-only version
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
enable_shared_server_with_database_setting() {
	enable_shared_server "$1"
	printf 'db: .beads/beads.db\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=enable_shared_server_with_database_setting
compare_real_database shared-server-notice-db-setting-where exact where
compare_real_database shared-server-notice-db-setting-version stderr-only version
compare_real_database shared-server-notice-db-setting-help-command exact help list
real_database_setup=""
# Commands that open a store set up the same directory for the db setting, and upstream's where for a
# BEADS_DB path, before the step that this build refuses.
candidate_only_setup=enable_shared_server_with_database_setting
store_refusal_notice="$shared_server_notice"
expect_store_refusal count-db-setting-shared-server-notice-unported "$database_reason" count count
expect_store_refusal list-db-setting-shared-server-notice-json-unported "$database_reason" list list --json
store_refusal_notice=""
candidate_only_setup=enable_shared_server
real_database_extra_env=(BEADS_DB=../work/sub/beads.db)
expect_candidate_failure where-beads-db-shared-server-notice-unported "" \
	"$shared_server_notice"$'\n'"Error: where is not available yet when BEADS_DB names this path in this build" "" where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
# A found workspace without a database: upstream finds none and writes nothing. It prints the notice
# when metadata.json pins dolt_mode embedded, then its hint, which names bd doctor in shared-server
# mode, as text even with --json; a config key that needs no database runs as usual.
real_database_setup=enable_shared_server_without_database
compare_real_database shared-server-no-database-count exact count
compare_real_database shared-server-no-database-count-json exact count --json
compare_real_database shared-server-no-database-show-json exact show "$real_database_issue_id" --json
compare_real_database shared-server-no-database-ready-bad-sort exact ready --sort bogus
compare_real_database shared-server-no-database-dep-tree exact dep tree "$real_database_issue_id"
compare_real_database shared-server-no-database-info exact info
compare_real_database shared-server-no-database-directory-list exact -C . list
compare_real_database shared-server-no-database-types exact types
compare_real_database shared-server-no-database-statuses-json exact statuses --json
compare_real_database shared-server-no-database-config-get exact config get routing.mode
compare_real_database shared-server-no-database-config-get-json exact config get routing.mode --json
compare_real_database shared-server-no-database-config-get-table exact config get issue_prefix
compare_real_database shared-server-no-database-config-list-json exact config list --json
compare_real_database shared-server-no-database-backup exact config get backup.enabled
real_database_setup=enable_shared_server_without_database_or_mode
compare_real_database shared-server-no-database-no-mode-list exact list
compare_real_database shared-server-no-database-no-mode-config-list exact config list
real_database_setup=remove_embedded_database
real_database_extra_env=(BD_DOLT_SHARED_SERVER=true)
compare_real_database shared-server-no-database-bd-env-count exact count
compare_real_database shared-server-no-database-bd-env-config-get-json exact config get export.auto --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# The config warning of each selected-workspace setup comes before the notice.
break_workspace_config_without_database() {
	remove_embedded_database "$1"
	printf '[a, b\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=break_workspace_config_without_database
real_database_extra_env=(BD_DOLT_SHARED_SERVER=1)
compare_real_database shared-server-no-database-broken-config-types exact types
compare_real_database shared-server-no-database-broken-config-get exact config get routing.mode
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=""
# Shared-server mode is off unless the variable is 1 or true.
compare_real_database_env count-shared-server-env-off exact BEADS_DOLT_SHARED_SERVER=0 count
real_database_read_only=""
use_sqlite_backend() {
	jq '.backend = "sqlite"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
# Upstream's legacy-workspace guard refuses a removed backend before config drift runs, and so does this build.
real_database_setup=use_sqlite_backend
compare_real_database config-drift-removed-backend exact config drift
real_database_setup=""
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
# The load error stops the pre-run before the command body checks its arguments.
compare_raw_metadata metadata-type-list-bad-sort exact "$type_error_metadata" list --sort bogus
compare_raw_metadata metadata-type-list-bad-sort-json exact "$type_error_metadata" list --sort bogus --json
compare_raw_metadata metadata-type-ready-bad-sort exact "$type_error_metadata" ready --sort bogus
compare_raw_metadata metadata-type-ready-bad-sort-json exact "$type_error_metadata" ready --sort bogus --json
compare_raw_metadata metadata-type-list-negative-offset exact "$type_error_metadata" list --offset -1
compare_raw_metadata metadata-type-query-negative-offset-json exact "$type_error_metadata" query status=open --offset -1 --json
compare_raw_metadata metadata-type-list-pinned-conflict exact "$type_error_metadata" list --pinned --no-pinned
compare_raw_metadata metadata-type-list-bad-priority exact "$type_error_metadata" list --priority bogus
compare_raw_metadata metadata-type-list-bad-priority-min-json exact "$type_error_metadata" list --priority-min 7 --json
compare_raw_metadata metadata-type-list-bad-mol-type exact "$type_error_metadata" list --mol-type bogus
compare_raw_metadata metadata-type-list-bad-wisp-type-json exact "$type_error_metadata" list --wisp-type bogus --json
compare_raw_metadata metadata-type-list-bad-closed-after exact "$type_error_metadata" list --closed-after bogus
compare_raw_metadata metadata-type-list-bad-metadata-field exact "$type_error_metadata" list --metadata-field bad
compare_raw_metadata metadata-type-list-bad-has-metadata-key-json exact "$type_error_metadata" list --has-metadata-key 1bad --json
compare_raw_metadata metadata-type-list-negative-max-rows exact "$type_error_metadata" list --max-rows -1
compare_raw_metadata metadata-type-list-brief-format exact "$type_error_metadata" list --brief --format '{{.ID}}'
compare_raw_metadata metadata-type-ready-brief exact "$type_error_metadata" ready --brief
compare_raw_metadata metadata-type-ready-brief-gated-json exact "$type_error_metadata" ready --brief --gated --json
compare_raw_metadata metadata-type-ready-bad-mol-type-json exact "$type_error_metadata" ready --mol-type bogus --json
compare_raw_metadata metadata-type-ready-bad-metadata-field exact "$type_error_metadata" ready --metadata-field bad
compare_raw_metadata metadata-type-ready-negative-max-rows-json exact "$type_error_metadata" ready --max-rows -1 --json
compare_raw_metadata metadata-type-readonly-ready-claim-brief-json exact "$type_error_metadata" --readonly ready --claim --brief --json
compare_raw_metadata metadata-type-count-by-conflict exact "$type_error_metadata" count --by-status --by-type
compare_raw_metadata metadata-type-count-by-conflict-json exact "$type_error_metadata" count --by-status --by-type --json
compare_raw_metadata metadata-type-count-bad-created-before exact "$type_error_metadata" count --created-before bogus
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
# A legacy-only workspace has a valid .beads/config.json and no metadata.json. Upstream rewrites it as
# metadata.json when `where` or a command that opens a store runs. version, help pages and unknown
# commands leave it in place, and so does this build, which matches them exactly. Until migration
# parity (M12), `where` and every command that reads the database refuse here instead of writing,
# also when a --db path or a redirect selects the workspace.
use_legacy_config() {
	mv -f "$1/work/.beads/metadata.json" "$1/work/.beads/config.json"
}
real_database_setup=use_legacy_config
compare_real_database legacy-config-version stderr-only version
compare_real_database legacy-config-version-json stderr-only version --json
compare_real_database legacy-config-root stderr-only
compare_real_database legacy-config-root-help-flag stderr-only --help
compare_real_database legacy-config-help-command exact help list
compare_real_database legacy-config-help-flag exact list --help
compare_real_database legacy-config-unknown-command exact frobnicate
compare_real_database legacy-config-directory-version stderr-only -C . version
# With a --db path, upstream's pre-run finds the workspace with configfile.Load, which rewrites the file
# even for version and help pages. This build prints the same output and writes nothing.
real_database_read_only=""
compare_real_database legacy-config-db-path-version stderr-only --db .beads version
compare_real_database legacy-config-db-embedded-path-help-command exact --db .beads/embeddeddolt help count
real_database_read_only=1
legacy_config_refusal() {
	printf '%s is not available yet when the workspace has only a legacy config.json in this build' "$1"
}
candidate_only_setup=use_legacy_config
expect_candidate_failure legacy-config-where-unported "" "Error: $(legacy_config_refusal where)" "" where
expect_candidate_failure legacy-config-where-json-unported \
	"{\"error\":\"$(legacy_config_refusal where)\",\"schema_version\":1}" "" "" where --json
expect_candidate_failure legacy-config-list-unported "" "Error: $(legacy_config_refusal list)" "" list
expect_candidate_failure legacy-config-show-unported "" "Error: $(legacy_config_refusal show)" "" \
	show "$real_database_issue_id"
expect_candidate_failure legacy-config-count-json-unported \
	"{\"error\":\"$(legacy_config_refusal count)\",\"schema_version\":1}" "" "" count --json
expect_candidate_failure legacy-config-label-list-all-unported "" "Error: $(legacy_config_refusal 'label list-all')" "" \
	label list-all
expect_candidate_failure legacy-config-directory-list-unported "" "Error: $(legacy_config_refusal list)" "" -C . list
expect_candidate_failure legacy-config-db-path-where-unported "" "Error: $(legacy_config_refusal where)" "" --db .beads where
expect_candidate_failure legacy-config-db-path-list-unported "" "Error: $(legacy_config_refusal list)" "" --db .beads list
expect_candidate_failure legacy-config-db-embedded-path-count-unported "" "Error: $(legacy_config_refusal count)" "" \
	--db .beads/embeddeddolt count
# A redirect into a legacy-only workspace selects that workspace.
redirect_to_legacy_config() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	mv -f "$1/work/sub/.beads/metadata.json" "$1/work/sub/.beads/config.json"
}
real_database_setup=redirect_to_legacy_config
compare_real_database legacy-config-redirect-version stderr-only version
compare_real_database legacy-config-redirect-help-command exact help count
candidate_only_setup=redirect_to_legacy_config
expect_candidate_failure legacy-config-redirect-where-unported "" "Error: $(legacy_config_refusal where)" "" where
expect_candidate_failure legacy-config-redirect-list-unported "" "Error: $(legacy_config_refusal list)" "" list
candidate_only_setup=""
# Upstream's legacy-workspace guard reads the legacy config.json too, and refuses before the rewrite
# (beadshx-m08-03.13): a .beads/dolt directory without an embedded repository, or a removed backend.
legacy_config_with_legacy_dolt_directory() {
	: "${1:?state root}"
	use_legacy_config "$1"
	mv -f "$1/work/.beads/embeddeddolt" "$1/work/.beads/dolt"
}
real_database_setup=legacy_config_with_legacy_dolt_directory
compare_real_database legacy-config-legacy-dolt-count exact count
compare_real_database legacy-config-legacy-dolt-where-json exact where --json
legacy_config_with_removed_backend() {
	use_legacy_config "$1"
	jq '.backend = "sqlite"' "$1/work/.beads/config.json" >"$1/config.json"
	cat "$1/config.json" >"$1/work/.beads/config.json"
	rm -f "$1/config.json"
}
real_database_setup=legacy_config_with_removed_backend
compare_real_database legacy-config-removed-backend-list exact list
real_database_setup=""
# LoadForDiscovery reads the legacy config.json as the workspace's config, so in shared-server mode its
# embedded dolt_mode gives the notice, and version prints it as upstream does.
real_database_setup=use_legacy_config
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database legacy-config-shared-server-version stderr-only version
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
use_legacy_config_with_broken_yaml() {
	use_legacy_config "$1"
	printf '[a, b\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=use_legacy_config_with_broken_yaml
compare_real_database legacy-config-broken-yaml-version stderr-only version
real_database_setup=""
# Without a database path, upstream's where rewrites the file only in its body, after both setups and the
# lookups before FindDatabasePath; a command that opens a store rewrites it after its first setup. The
# refusals follow the warnings and the notice that upstream prints before.
legacy_yaml_failure="error reading config file: While parsing config: yaml: line 72: did not find expected ',' or ']'"
candidate_only_setup=use_legacy_config_with_broken_yaml
expect_candidate_failure legacy-config-broken-yaml-where-unported "" \
	"Warning: failed to initialize config: $legacy_yaml_failure"$'\n'"Warning: failed to reinitialize config for selected beads dir: $legacy_yaml_failure"$'\n'"Warning: failed to reinitialize config for selected beads dir: $legacy_yaml_failure"$'\n'"Error: $(legacy_config_refusal where)" "" \
	where
expect_candidate_failure legacy-config-broken-yaml-count-unported "" \
	"Warning: failed to initialize config: $legacy_yaml_failure"$'\n'"Warning: failed to reinitialize config for selected beads dir: $legacy_yaml_failure"$'\n'"Error: $(legacy_config_refusal count)" "" \
	count
candidate_only_setup=use_legacy_config
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure legacy-config-shared-server-where-unported "" \
	"$shared_server_notice"$'\n'"Error: $(legacy_config_refusal where)" "" where
expect_candidate_failure legacy-config-shared-server-count-json-unported \
	"{\"error\":\"$(legacy_config_refusal count)\",\"schema_version\":1}" "$shared_server_notice" "" count --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A redirect from a legacy-only workspace to a missing target warns at each of upstream's lookups up to the
# rewrite, once each.
use_legacy_config_with_broken_redirect() {
	use_legacy_config "$1"
	printf 'missing/.beads\n' >"$1/work/.beads/redirect"
}
legacy_missing_warning='Warning: redirect target does not exist or is not a directory: <work>/missing/.beads'
candidate_only_setup=use_legacy_config_with_broken_redirect
expect_candidate_failure legacy-config-broken-redirect-count-unported "" \
	"$(printf '%s\n' "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning")"$'\n'"Error: $(legacy_config_refusal count)" "" \
	count
expect_candidate_failure legacy-config-broken-redirect-where-unported "" \
	"$(printf '%s\n' "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning" "$legacy_missing_warning")"$'\n'"Error: $(legacy_config_refusal where)" "" \
	where
# A BEADS_DB or BD_DB path that names a legacy-only workspace, and a db setting that does, make upstream
# rewrite the file while it derives the workspace from the path; this build refuses before.
move_legacy_workspace_to_db() {
	mkdir "$1/work/db"
	mv -f "$1/work/.beads" "$1/work/db/.beads"
	mv -f "$1/work/db/.beads/metadata.json" "$1/work/db/.beads/config.json"
}
candidate_only_setup=move_legacy_workspace_to_db
real_database_extra_env=(BEADS_DB=db/.beads)
expect_candidate_failure legacy-config-beads-db-count-unported "" \
	"Error: count is not available yet when BEADS_DB names this path in this build" "" count
expect_candidate_failure legacy-config-beads-db-where-unported "" \
	"Error: where is not available yet when BEADS_DB names this path in this build" "" where
real_database_extra_env=(BD_DB=db/.beads/embeddeddolt)
expect_candidate_failure legacy-config-bd-db-where-unported "" \
	"Error: where is not available yet when BD_DB names this path in this build" "" where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
legacy_workspace_with_setting() {
	mkdir "$1/work/other"
	copy_fixture_tree "$1/work/.beads" "$1/work/other/.beads"
	mv -f "$1/work/other/.beads/metadata.json" "$1/work/other/.beads/config.json"
	printf 'db: other/.beads/beads.db\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=legacy_workspace_with_setting
expect_candidate_failure legacy-config-db-setting-where-unported "" "Error: $(legacy_config_refusal where)" "" where
expect_candidate_failure legacy-config-db-setting-count-unported "" \
	"Error: count is not available yet when the db setting names a database in this build" "" count
candidate_only_setup=""
# Upstream's legacy-workspace guard runs after one setup, before the rewrite of the legacy config.json. So a
# legacy-only workspace that it refuses stops there, where too, after the warnings and the notice of that setup.
legacy_config_with_legacy_dolt_directory_and_broken_yaml() {
	legacy_config_with_legacy_dolt_directory "$1"
	printf '[a, b\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=legacy_config_with_legacy_dolt_directory_and_broken_yaml
compare_real_database legacy-config-legacy-dolt-broken-yaml-where exact where
compare_real_database legacy-config-legacy-dolt-broken-yaml-count exact count
real_database_setup=legacy_config_with_removed_backend
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database legacy-config-removed-backend-shared-server-where exact where
compare_real_database legacy-config-removed-backend-shared-server-count-json exact count --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=""
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
# Upstream's store open refuses a database name that is not an identifier (letters, digits and `_`, not
# starting with a digit) before it reads or creates anything. A plain read opens the store through
# its schema initialization, which names itself and adds a hint for a hyphen; strict read-only mode
# (--readonly, BD_READONLY or the readonly setting) refuses without either. Every mode prints the error
# as text, also under --json. `where` still runs and prints no prefix from the database.
compare_real_database_metadata invalid-db-name-hyphen-show exact '.dolt_database = "te-st"' show "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-hyphen-show-json exact '.dolt_database = "te-st"' show "$real_database_issue_id" --json
compare_real_database_metadata invalid-db-name-hyphen-comments exact '.dolt_database = "te-st"' comments "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-hyphen-dep-tree exact '.dolt_database = "te-st"' dep tree "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-hyphen-types exact '.dolt_database = "te-st"' types
compare_real_database_metadata invalid-db-name-hyphen-types-json exact '.dolt_database = "te-st"' types --json
compare_real_database_metadata invalid-db-name-hyphen-where exact '.dolt_database = "te-st"' where
compare_real_database_metadata invalid-db-name-hyphen-list exact '.dolt_database = "te-st"' list
compare_real_database_metadata invalid-db-name-hyphen-count-json exact '.dolt_database = "te-st"' count --json
compare_real_database_metadata invalid-db-name-hyphen-config-get exact '.dolt_database = "te-st"' config get issue_prefix
compare_real_database_metadata invalid-db-name-hyphen-config-validate exact '.dolt_database = "te-st"' config validate
compare_real_database_metadata invalid-db-name-dot-show-json exact '.dolt_database = "te.st"' show "$real_database_issue_id" --json
compare_real_database_metadata invalid-db-name-dot-comments exact '.dolt_database = "te.st"' comments "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-dot-dep-tree exact '.dolt_database = "te.st"' dep tree "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-dot-types exact '.dolt_database = "te.st"' types
compare_real_database_metadata invalid-db-name-dot-where-json exact '.dolt_database = "te.st"' where --json
compare_real_database_metadata invalid-db-name-dot-list-json exact '.dolt_database = "te.st"' list --json
compare_real_database_metadata invalid-db-name-dot-count exact '.dolt_database = "te.st"' count
compare_real_database_metadata invalid-db-name-leading-digit-ready exact '.dolt_database = "1test"' ready
compare_real_database_metadata invalid-db-name-quoted-count exact '.dolt_database = "te\"sté"' count
compare_real_database_metadata invalid-db-name-hyphen-readonly-show exact '.dolt_database = "te-st"' --readonly show "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-hyphen-readonly-types-json exact '.dolt_database = "te-st"' --readonly types --json
compare_real_database_metadata invalid-db-name-dot-readonly-comments exact '.dolt_database = "te.st"' --readonly comments "$real_database_issue_id"
compare_real_database_metadata invalid-db-name-dot-readonly-dep-tree exact '.dolt_database = "te.st"' --readonly dep tree "$real_database_issue_id"
real_database_extra_env=(BD_READONLY=1)
compare_real_database_metadata invalid-db-name-hyphen-readonly-variable-list exact '.dolt_database = "te-st"' list
real_database_extra_env=(BEADS_DOLT_SERVER_DATABASE=te-st)
compare_real_database invalid-db-name-server-database-variable-count exact count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='readonly: true'
compare_real_database_metadata invalid-db-name-dot-readonly-setting-where exact '.dolt_database = "te.st"' where
compare_real_database_metadata invalid-db-name-dot-readonly-setting-count exact '.dolt_database = "te.st"' count
real_database_extra_config=""
# Upstream keeps a redirecting workspace's dolt_database across the redirect, so a name there that is
# not an identifier refuses the open, although the target names its own database.
redirect_with_invalid_source_database() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	printf '{"dolt_database":"te-st"}' >"$1/work/.beads/metadata.json"
}
real_database_setup=redirect_with_invalid_source_database
compare_real_database invalid-db-name-redirect-source-count exact count
compare_real_database invalid-db-name-redirect-source-readonly-show-json exact --readonly show "$real_database_issue_id" --json
real_database_setup=""
# The snapshot extension refuses as upstream's export does, which opens the store for a plain read.
invalid_database_name_metadata() {
	jq '.dolt_database = "te-st"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
candidate_only_setup=invalid_database_name_metadata
expect_candidate_failure invalid-db-name-hyphen-snapshot "" \
	"Error: failed to open database: embeddeddolt: init schema: embeddeddolt: invalid database name: \"te-st\"; hyphens are not allowed in embedded mode — replace with underscores in .beads/metadata.json dolt_database field, or run 'bd doctor'" "" \
	snapshot
expect_candidate_failure invalid-db-name-hyphen-readonly-snapshot "" \
	'Error: failed to open database: embeddeddolt: invalid database name: "te-st"' "" --readonly snapshot
candidate_only_setup=""
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
# The command body checks its arguments, and reads BEADS_MAX_ROWS, after the pre-run's warning.
compare_real_database no-metadata-default-list-bad-sort exact list --sort bogus
compare_real_database no-metadata-default-list-bad-sort-json exact list --sort bogus --json
compare_real_database no-metadata-default-ready-bad-sort exact ready --sort bogus
compare_real_database no-metadata-default-ready-bad-sort-json exact ready --sort bogus --json
compare_real_database no-metadata-default-list-negative-offset exact list --offset -1
compare_real_database no-metadata-default-query-negative-offset-json exact query status=open --offset -1 --json
compare_real_database no-metadata-default-list-pinned-conflict-json exact list --pinned --no-pinned --json
compare_real_database no-metadata-default-list-bad-priority exact list --priority bogus
compare_real_database no-metadata-default-list-bad-priority-min exact list --priority-min high
compare_real_database no-metadata-default-list-bad-mol-type-json exact list --mol-type bogus --json
compare_real_database no-metadata-default-list-bad-wisp-type exact list --wisp-type bogus
compare_real_database no-metadata-default-list-bad-defer-after exact list --defer-after bogus
compare_real_database no-metadata-default-list-bad-metadata-field-json exact list --metadata-field 'bad$key=x' --json
compare_real_database no-metadata-default-list-bad-has-metadata-key exact list --has-metadata-key 1bad
compare_real_database no-metadata-default-list-negative-max-rows-json exact list --max-rows -1 --json
compare_real_database no-metadata-default-list-brief-format exact list --brief --format '{{.ID}}'
compare_real_database no-metadata-default-ready-brief exact ready --brief
compare_real_database no-metadata-default-ready-brief-explain-json exact ready --brief --explain --json
compare_real_database no-metadata-default-ready-bad-mol-type exact ready --mol-type bogus
compare_real_database no-metadata-default-ready-bad-has-metadata-key-json exact ready --has-metadata-key 1bad --json
compare_real_database no-metadata-default-ready-negative-max-rows-json exact ready --max-rows -1 --json
compare_real_database no-metadata-default-readonly-ready-claim exact --readonly ready --claim
compare_real_database no-metadata-default-readonly-ready-claim-assignee exact --readonly ready --claim --assignee fixture
compare_real_database no-metadata-default-count-by-conflict exact count --by-status --by-priority
compare_real_database no-metadata-default-count-by-conflict-json exact count --by-status --by-priority --json
compare_real_database no-metadata-default-count-bad-updated-after-json exact count --updated-after bogus --json
real_database_extra_env=(BEADS_MAX_ROWS=bogus)
compare_real_database no-metadata-default-max-rows-list exact list
compare_real_database no-metadata-default-max-rows-ready-bad-sort exact ready --sort bogus
# The warning prints when the command reads BEADS_MAX_ROWS: after list's checks and ready's mol-type
# check, before ready's metadata checks.
compare_real_database no-metadata-default-max-rows-list-bad-wisp-type exact list --wisp-type bogus
compare_real_database no-metadata-default-max-rows-ready-bad-mol-type exact ready --mol-type bogus
compare_real_database no-metadata-default-max-rows-ready-bad-metadata-field exact ready --metadata-field bad
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
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
compare_real_database deprecated-port-list-bad-sort exact list --sort bogus
compare_real_database deprecated-port-ready-bad-sort-json exact ready --sort bogus --json
compare_real_database deprecated-port-list-negative-offset-json exact list --offset -1 --json
compare_real_database deprecated-port-query-negative-offset exact query status=open --offset -1
compare_real_database deprecated-port-list-pinned-conflict exact list --pinned --no-pinned
compare_real_database deprecated-port-list-bad-priority-max-json exact list --priority-max P9 --json
compare_real_database deprecated-port-list-bad-wisp-type exact list --wisp-type bogus
compare_real_database deprecated-port-list-bad-updated-before-json exact list --updated-before bogus --json
compare_real_database deprecated-port-list-bad-has-metadata-key-json exact list --has-metadata-key 1bad --json
compare_real_database deprecated-port-list-negative-max-rows exact list --max-rows -1
compare_real_database deprecated-port-list-brief-parent exact list --brief --parent "$real_database_epic_id"
compare_real_database deprecated-port-ready-brief-claim-json exact ready --brief --claim --json
compare_real_database deprecated-port-ready-bad-metadata-field-json exact ready --metadata-field '1bad=x' --json
compare_real_database deprecated-port-ready-negative-max-rows exact ready --max-rows -1
compare_real_database deprecated-port-readonly-ready-claim-mol-type exact --readonly ready --claim --mol-type bogus
compare_real_database deprecated-port-count-by-conflict exact count --by-type --by-label
compare_real_database deprecated-port-count-bad-closed-before exact count --closed-before bogus
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
# Upstream reads the Dolt directory's config.yaml with Dolt's servercfg: it expands ${VAR}
# placeholders, then decodes the file strictly. A file that decodes stops the walk with its
# listener port, which is 3306 when the file sets none. A file that does not read or decode, or
# that sets the port to 0 or less, does not stop the walk, so the metadata.json port still warns.
dolt_config_yaml=$'log_level: info\n'
write_dolt_config_yaml() {
	mkdir -p "$1/work/.beads/dolt"
	printf '%s' "$dolt_config_yaml" >"$1/work/.beads/dolt/config.yaml"
}
real_database_setup=write_dolt_config_yaml
compare_real_database deprecated-port-dolt-config exact count
dolt_config_yaml=""
compare_real_database deprecated-port-dolt-config-empty exact count
dolt_config_yaml=$'listener:\n  port: 3307\n'
compare_real_database deprecated-port-dolt-config-port exact count
dolt_config_yaml=$'listener:\n  port: 0\n'
compare_real_database deprecated-port-dolt-config-port-zero exact count
dolt_config_yaml=$'listener:\n  port: -1\n'
compare_real_database deprecated-port-dolt-config-port-negative exact count
dolt_config_yaml=$'listener:\n  port: abc\n'
compare_real_database deprecated-port-dolt-config-port-text exact count
# Strict decoding refuses a key that Dolt does not know.
dolt_config_yaml=$'log_level: info\nunknown_key: 1\n'
compare_real_database deprecated-port-dolt-config-unknown-key exact count
dolt_config_yaml=$'listener: [\n'
compare_real_database deprecated-port-dolt-config-bad-syntax exact count
dolt_config_yaml=$'listener:\n  port: ${BEADSHX_PARITY_DOLT_PORT}\n'
compare_real_database deprecated-port-dolt-config-unset-placeholder exact count
real_database_extra_env=(BEADSHX_PARITY_DOLT_PORT=3307)
compare_real_database deprecated-port-dolt-config-placeholder exact count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A config.yaml directory passes upstream's stat check, but Dolt cannot read it.
make_dolt_config_directory() {
	mkdir -p "$1/work/.beads/dolt/config.yaml"
}
real_database_setup=make_dolt_config_directory
compare_real_database deprecated-port-dolt-config-directory exact count
real_database_setup=""
real_database_extra_metadata=""
compare_real_database_metadata deprecated-port-zero exact '.dolt_server_port = 0' count
compare_real_database_metadata deprecated-port-negative exact '.dolt_server_port = -1' count
compare_real_database_metadata deprecated-port-readonly-missing-db exact \
	'.dolt_server_port = 3307 | .dolt_database = "other"' --readonly count
# A server workspace warns too before the --global check, which fails outside shared-server mode
# before upstream dials a server. A proxied-server workspace warns the same way, and its --global
# check fails with the same error.
real_database_extra_metadata='.dolt_mode = "server" | .dolt_server_port = 3307'
compare_real_database deprecated-port-server-global exact count --global
compare_real_database deprecated-port-server-global-list-json exact list --global --json
compare_real_database deprecated-port-server-global-info exact info --global
real_database_extra_metadata='.dolt_mode = "proxied-server" | .dolt_server_port = 3307'
compare_real_database deprecated-port-proxied-global exact count --global
compare_real_database deprecated-port-proxied-global-show-json exact show "$real_database_issue_id" --global --json
compare_real_database deprecated-port-proxied-global-types exact types --global
real_database_extra_metadata=""
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
candidate_only_setup=""
# where, version and help pages set up the directory that upstream derives from the path, which prints the load
# warning there, and where stops with the load error (beadshx-m08-01.12).
real_database_setup=break_metadata
compare_real_database metadata-db-flag-where-json exact --db .beads/embeddeddolt where --json
compare_real_database metadata-db-flag-version stderr-only --db .beads/embeddeddolt version
compare_real_database metadata-db-flag-help-command exact --db .beads/embeddeddolt help count
real_database_setup=""
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
# here. This build opens `other` too, and refuses because the store lacks it.
redirect_with_source_database() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	printf '{"dolt_database":"other"}' >"$1/work/.beads/metadata.json"
}
candidate_only_setup=redirect_with_source_database
expect_candidate_failure missing-db-redirect-source-count-unported "" \
	'Error: count is not available yet when the embedded store has no database named "other" in this build' "" count
candidate_only_setup=""
real_database_read_only=1
# pflag reads --readonly as a bool, before or after the command: every strconv.ParseBool form, and the
# last value counts. A true value opens the store strictly, so a missing database gives the open error.
# A false value turns strict mode off also when the readonly setting or BD_READONLY turns it on, so an
# invalid name gives the plain open's words.
compare_real_database_metadata readonly-flag-true-missing-db exact '.dolt_database = "other"' --readonly=true count
compare_real_database_metadata readonly-flag-one-missing-db-list-json exact '.dolt_database = "other"' --readonly=1 list --json
compare_real_database_metadata readonly-flag-t-missing-db-comments exact '.dolt_database = "other"' --readonly=t comments "$real_database_issue_id"
compare_real_database_metadata readonly-flag-upper-true-after-command exact '.dolt_database = "other"' types --readonly=TRUE
compare_real_database_metadata readonly-flag-title-true-missing-db exact '.dolt_database = "other"' --readonly=True count
compare_real_database_metadata readonly-flag-capital-t-missing-db exact '.dolt_database = "other"' dep tree "$real_database_issue_id" --readonly=T
compare_real_database readonly-flag-false-count exact --readonly=false count
compare_real_database readonly-flag-zero-list-json exact list --readonly=0 --json
compare_real_database_metadata readonly-flag-false-then-true exact '.dolt_database = "other"' --readonly=false --readonly count
compare_real_database_metadata readonly-flag-true-then-false exact '.dolt_database = "te-st"' --readonly --readonly=false count
real_database_extra_config='readonly: true'
compare_real_database_metadata readonly-flag-false-over-setting exact '.dolt_database = "te-st"' --readonly=false count
compare_real_database_metadata readonly-flag-f-over-setting-comments exact '.dolt_database = "te-st"' --readonly=f comments "$real_database_issue_id"
compare_real_database_metadata readonly-flag-upper-false-over-setting exact '.dolt_database = "te.st"' --readonly=FALSE types
compare_real_database_metadata readonly-flag-capital-f-over-setting exact '.dolt_database = "te.st"' --readonly=F list --json
compare_real_database_metadata readonly-flag-title-false-over-setting exact '.dolt_database = "te.st"' --readonly=False count
compare_real_database_metadata readonly-flag-true-with-setting exact '.dolt_database = "te.st"' --readonly=true count
real_database_extra_config=""
real_database_extra_env=(BD_READONLY=1)
compare_real_database_metadata readonly-flag-zero-over-variable-show-json exact '.dolt_database = "te-st"' --readonly=0 show "$real_database_issue_id" --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A value that strconv.ParseBool rejects fails before the pre-run, as text also under --json.
compare_real_database readonly-flag-bad-value exact --readonly=maybe count
compare_real_database readonly-flag-empty-value exact --readonly= count
compare_real_database readonly-flag-bad-value-after-command exact count --readonly=yes
compare_real_database readonly-flag-bad-value-json exact --readonly=maybe list --json
compare_real_database readonly-flag-bad-value-version exact --readonly=maybe version
compare_real_database readonly-flag-bad-value-where exact --readonly=maybe where
compare_real_database readonly-flag-bad-value-help-command exact --readonly=maybe help count
# A --db path that selects a workspace whose database name is not an identifier refuses it the same way.
compare_real_database_metadata invalid-db-name-db-flag-store exact '.dolt_database = "te-st"' --db .beads/embeddeddolt count
compare_real_database_metadata invalid-db-name-db-flag-workspace-readonly-json exact '.dolt_database = "te.st"' --db .beads --readonly list --json
# A directory or a file named like a missing database makes upstream's create fail without a write; in
# strict read-only mode the open fails first.
missing_database_directory() {
	mkdir "$1/work/.beads/embeddeddolt/other"
}
real_database_setup=missing_database_directory
compare_real_database_metadata missing-db-directory-count exact '.dolt_database = "other"' count
compare_real_database_metadata missing-db-directory-show-json exact '.dolt_database = "other"' show "$real_database_issue_id" --json
compare_real_database_metadata missing-db-directory-where exact '.dolt_database = "other"' where
compare_real_database_metadata missing-db-directory-readonly exact '.dolt_database = "other"' --readonly count
missing_database_file() {
	: >"$1/work/.beads/embeddeddolt/other"
}
real_database_setup=missing_database_file
compare_real_database_metadata missing-db-file-count exact '.dolt_database = "other"' count
compare_real_database_metadata missing-db-file-types-json exact '.dolt_database = "other"' types --json
compare_real_database_metadata missing-db-file-readonly-comments exact '.dolt_database = "other"' --readonly comments "$real_database_issue_id"
replace_database_with_directory() {
	rm -rf "$1/work/.beads/embeddeddolt/test"
	mkdir "$1/work/.beads/embeddeddolt/test"
}
real_database_setup=replace_database_with_directory
compare_real_database missing-db-replaced-by-directory-list exact list
replace_database_with_file() {
	rm -rf "$1/work/.beads/embeddeddolt/test"
	: >"$1/work/.beads/embeddeddolt/test"
}
real_database_setup=replace_database_with_file
compare_real_database missing-db-replaced-by-file-dep-tree exact dep tree "$real_database_issue_id"
# A directory that a create left unfinished, with Dolt's in-progress marker or a .dolt without its
# repo_state.json, is no database. Upstream's plain open then refuses to create one there, and its strict
# open finds none; neither writes. Dolt warns through logrus for each marked directory when it opens the store,
# also beside a database that it opens.
set_other_database() {
	jq '.dolt_database = "other"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
marked_unfinished_database() {
	set_other_database "$1"
	copy_fixture_tree "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/other"
	: >"$1/work/.beads/embeddeddolt/other/.dolt_safe_to_ignore"
}
unstarted_database() {
	set_other_database "$1"
	mkdir -p "$1/work/.beads/embeddeddolt/other/.dolt"
}
marked_database_beside() {
	copy_fixture_tree "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/other"
	: >"$1/work/.beads/embeddeddolt/other/.dolt_safe_to_ignore"
}
real_database_setup=marked_unfinished_database
compare_real_database unfinished-marked-database-count exact count
compare_real_database unfinished-marked-database-readonly-count exact --readonly count
real_database_setup=unstarted_database
compare_real_database unfinished-unstarted-database-list-json exact list --json
compare_real_database unfinished-unstarted-database-readonly-count exact --readonly count
real_database_setup=marked_database_beside
compare_real_database unfinished-marked-database-beside-count exact count
# Dolt warns at each store open: upstream's pre-run opens the store, then each store call opens it again.
# A grouped count asks for the buckets and then the total, and --include-infra first loads the custom
# statuses, the custom types and the infra types. query and ping make one store call.
compare_real_database unfinished-marked-database-beside-count-by-status exact count --by-status
compare_real_database unfinished-marked-database-beside-count-infra-json exact count --include-infra --by-type --json
compare_real_database unfinished-marked-database-beside-query exact query status=open
compare_real_database unfinished-marked-database-beside-ping ping-human ping
real_database_setup=""
# A --db path that names a .beads directory with only a redirect selects the directory above it, which
# has no metadata.json and no store. The strict open stops at the missing store directory without a write;
# the plain open would create it.
redirect_only_beads_directory() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
}
# Upstream also takes a workspace gate lock beside that store directory, which bdhx does not take.
real_database_setup=redirect_only_beads_directory
real_database_read_only=""
compare_real_database db-flag-redirect-only-readonly-list exact --db .beads --readonly list
compare_real_database db-flag-redirect-only-readonly-count-json exact --db .beads --readonly count --json
real_database_read_only=1
real_database_setup=""
# Upstream refuses strict read-only mode in a proxied-server workspace before it starts the proxy, also for a
# --db value that names a database and with the readonly setting.
real_database_extra_metadata='.dolt_mode = "proxied-server"'
compare_real_database proxied-readonly-count exact --readonly count
compare_real_database proxied-readonly-list-json exact --readonly list --json
compare_real_database proxied-readonly-database-name-count exact --db other --readonly count
compare_real_database proxied-readonly-config-get exact --readonly config get issue_prefix
real_database_extra_config='readonly: true'
compare_real_database proxied-readonly-setting-count exact count
real_database_extra_config=""
real_database_extra_metadata=""
no_metadata_default_database_file() {
	remove_metadata "$1"
	: >"$1/work/.beads/embeddeddolt/beads"
}
real_database_setup=no_metadata_default_database_file
compare_real_database no-metadata-default-file-count exact count
real_database_setup=""
# With DOLT_DBNAME_REPLACE set, Dolt names a database after its directory with each run of spaces and
# hyphens as one `_`. Without it, the directory keeps its own name.
hyphenated_database_directory() {
	mv -f "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/te--st"
}
spaced_database_directory() {
	mv -f "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/ te st"
}
real_database_setup=hyphenated_database_directory
real_database_extra_env=(DOLT_DBNAME_REPLACE=1)
compare_real_database_metadata dbname-replace-hyphen-count exact '.dolt_database = "te_st"' count
compare_real_database_metadata dbname-replace-hyphen-readonly-list-json exact '.dolt_database = "te_st"' --readonly list --json
compare_real_database_metadata dbname-replace-hyphen-comments exact '.dolt_database = "TE_ST"' comments "$real_database_issue_id"
compare_real_database_metadata dbname-replace-hyphen-where exact '.dolt_database = "te_st"' where
real_database_setup=spaced_database_directory
compare_real_database_metadata dbname-replace-space-dep-tree exact '.dolt_database = "te_st"' dep tree "$real_database_issue_id"
compare_real_database_metadata dbname-replace-space-types exact '.dolt_database = "te_st"' types
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=hyphenated_database_directory
compare_real_database_metadata dbname-no-replace-readonly exact '.dolt_database = "te_st"' --readonly count
real_database_setup=""
# Upstream keeps the dolt_database of the workspace that GetRedirectInfo names: the .beads directory of
# the Git repository root, also when -C or BEADS_DIR selects another workspace; outside a repository,
# BEADS_DIR, which -C sets, and only without it the first .beads directory above the current directory.
# A redirect is kept when upstream follows it. Here `other` is a copy of `test` from before the target's
# copy of the issue was renamed, so each read shows which database it opened. Each side runs the rename
# at its own time, so the rename keeps the seed's updated_at, which the JSON reads print.
redirect_with_existing_source_database() {
	copy_fixture_tree "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/other"
	printf "UPDATE issues SET title = 'Target database title', updated_at = updated_at WHERE id = '%s'\n" \
		"$real_database_issue_id" |
		"$fixture_sql" "$1/work" >/dev/null
	redirect_with_source_database "$1"
}
real_database_setup=redirect_with_existing_source_database
compare_real_database redirect-source-existing-list-json exact list --json
compare_real_database redirect-source-existing-readonly-dep-tree exact --readonly dep tree "$real_database_issue_id"
compare_real_database redirect-source-existing-where exact where
real_database_directory=sub
compare_real_database redirect-source-existing-target-directory-list exact list
real_database_directory=""
redirect_beside_another_workspace() {
	redirect_with_existing_source_database "$1"
	mkdir "$1/elsewhere"
	copy_fixture_tree "$1/work/sub/.beads" "$1/elsewhere/.beads"
}
real_database_setup=redirect_beside_another_workspace
compare_real_database redirect-source-change-directory-list-json exact -C ../elsewhere list --json
real_database_extra_env=('BEADS_DIR=<work>/../elsewhere/.beads')
compare_real_database redirect-source-beads-dir-dep-tree exact dep tree "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A --db path skips that check: upstream reads the target's own database.
compare_real_database redirect-source-db-flag-list exact --db sub/.beads/embeddeddolt list
# Outside a repository upstream's `list` also warns that beads.role is not set, so these read with dep tree.
redirect_outside_git_repository() {
	redirect_beside_another_workspace "$1"
	mv -f "$1/work/.git" "$1/work-git"
}
real_database_setup=redirect_outside_git_repository
compare_real_database redirect-source-no-git-dep-tree exact dep tree "$real_database_issue_id"
compare_real_database redirect-source-no-git-change-directory-dep-tree-json exact -C ../elsewhere dep tree "$real_database_issue_id" --json
real_database_extra_env=('BEADS_DIR=<work>/../elsewhere/.beads')
compare_real_database redirect-source-no-git-beads-dir-dep-tree exact dep tree "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_directory=sub
compare_real_database redirect-source-no-git-target-directory-dep-tree exact --readonly dep tree "$real_database_issue_id"
real_database_directory=""
real_database_setup=""
real_database_read_only=""
# Upstream follows a redirect at each of its workspace lookups, and FollowRedirect warns on every call: for a
# target that does not exist, for a redirect chain, and with BD_DEBUG_ROUTING for each redirect it follows.
# How often depends on the command and its selection: a broken redirect warns 9 times for `where` and 11 times
# for `count`, and twice more when the workspace is inside upstream's safe boundary, where its post-run
# GetRepoContext also runs GetRedirectInfo. A redirecting directory that names a database keeps it, and the
# later lookups skip its redirect.
redirect_to_missing_target() {
	printf 'missing/.beads\n' >"$1/work/.beads/redirect"
}
redirect_to_sub() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
}
redirect_chain_to_missing_target() {
	redirect_to_sub "$1"
	printf 'missing/.beads\n' >"$1/work/sub/.beads/redirect"
}
redirect_to_directory_without_database() {
	mkdir -p "$1/work/empty/.beads"
	printf 'empty/.beads\n' >"$1/work/.beads/redirect"
}
redirect_only_to_missing_target() {
	rm -rf "$1/work/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'missing/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=redirect_to_missing_target
compare_real_database broken-redirect-where exact where
compare_real_database broken-redirect-list exact list
compare_real_database broken-redirect-show exact show "$real_database_issue_id"
compare_real_database broken-redirect-count exact count
compare_real_database broken-redirect-info exact info
compare_real_database broken-redirect-config-get exact config get issue_prefix
compare_real_database broken-redirect-version stderr-only version
compare_real_database broken-redirect-db-flag-count exact --db .beads/embeddeddolt count
real_database_extra_env=('BEADS_DB=<work>/.beads/embeddeddolt')
compare_real_database broken-redirect-beads-db-count exact count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database broken-redirect-change-directory-where exact -C . where
compare_real_database broken-redirect-show-json exact show "$real_database_issue_id" --json
compare_real_database broken-redirect-help-command exact help count
# A strict read-only run skips the version tracking and post-run lookups. The read-only check gives each side
# its own TMPDIR, which leaves the workspace outside upstream's safe boundary on macOS, so the post-run
# GetRepoContext there skips its GetRedirectInfo.
real_database_read_only=1
compare_real_database broken-redirect-readonly-flag-count exact --readonly count
compare_real_database broken-redirect-readonly-where exact where
real_database_read_only=""
real_database_setup=redirect_chain_to_missing_target
compare_real_database chained-redirect-where exact where
compare_real_database chained-redirect-list exact list
compare_real_database chained-redirect-show exact show "$real_database_issue_id"
compare_real_database chained-redirect-count exact count
compare_real_database chained-redirect-info exact info
compare_real_database chained-redirect-config-get exact config get issue_prefix
compare_real_database chained-redirect-version stderr-only version
compare_real_database chained-redirect-db-flag-count exact --db sub/.beads/embeddeddolt count
real_database_extra_env=('BEADS_DB=<work>/sub/.beads/embeddeddolt')
compare_real_database chained-redirect-beads-db-count exact count
real_database_extra_env=(BD_DEBUG_ROUTING=1)
real_database_setup=redirect_to_sub
compare_real_database routed-redirect-where exact where
compare_real_database routed-redirect-list exact list
compare_real_database routed-redirect-show exact show "$real_database_issue_id"
compare_real_database routed-redirect-count exact count
compare_real_database routed-redirect-info exact info
compare_real_database routed-redirect-config-get exact config get issue_prefix
compare_real_database routed-redirect-version stderr-only version
compare_real_database routed-redirect-db-flag-count exact --db sub/.beads/embeddeddolt count
real_database_extra_env=(BD_DEBUG_ROUTING=1 'BEADS_DB=<work>/sub/.beads/embeddeddolt')
compare_real_database routed-redirect-beads-db-count exact count
real_database_extra_env=(BD_DEBUG_ROUTING=1)
real_database_setup=redirect_chain_to_missing_target
compare_real_database routed-chained-redirect-count exact count
real_database_setup=redirect_with_existing_source_database
compare_real_database routed-redirect-source-database-count exact count
compare_real_database routed-redirect-source-database-where exact where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A target without project files warns once for each redirecting directory.
real_database_setup=redirect_to_directory_without_database
compare_real_database redirect-without-database-count exact count
compare_real_database redirect-without-database-where exact where
# A .beads directory that only redirects to a missing target selects no workspace; each lookup still warns.
real_database_setup=redirect_only_to_missing_target
compare_real_database redirect-only-broken-count exact count
compare_real_database redirect-only-broken-where exact where
compare_real_database redirect-only-broken-version stderr-only version
# When the redirect target has its own redirect to a workspace, FindBeadsDir warns that it ignores that chain
# and finds the first target. But once the pre-run sets BEADS_DIR to it, the later lookups follow its redirect:
# a command that opens a store binds and reads the second target's database, and the body of where reports
# the workspace that it finds through the second target. With -C, BEADS_DIR names the first target before the
# pre-run looks up, so both setups take the second target. A --db path selects the first target. Each copy of
# the issue has its own title, so each read shows which database it opened.
rename_parity_issue() {
	printf "UPDATE issues SET title = '%s', updated_at = updated_at WHERE id = '%s'\n" "$2" "$real_database_issue_id" |
		"$fixture_sql" "$1/work" >/dev/null
}
# Rewrites the dolt_database of the metadata.json file $2 in place, so the file keeps its mode.
set_fixture_database() {
	jq --arg name "$3" '.dolt_database = $name' "$2" >"$1/metadata.json"
	cat "$1/metadata.json" >"$2"
	rm -f "$1/metadata.json"
}
# The workspace moves to the first target, sub, after a copy of it went to the second target, final.
copy_first_redirect_target() {
	mkdir "$1/work/sub" "$1/work/final"
	copy_fixture_tree "$1/work/.beads" "$1/work/sub/.beads"
}
link_redirect_chain() {
	mv -f "$1/work/.beads" "$1/work/final/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	printf '../final/.beads\n' >"$1/work/sub/.beads/redirect"
}
redirect_chain_to_workspace() {
	copy_first_redirect_target "$1"
	rename_parity_issue "$1" 'Second target title'
	link_redirect_chain "$1"
}
# The first target names the database `other`, which upstream keeps across its redirect: it reads the
# second target's `other`, whose copy of the issue has a third title.
redirect_chain_with_source_database() {
	copy_fixture_tree "$1/work/.beads/embeddeddolt/test" "$1/work/.beads/embeddeddolt/other"
	copy_first_redirect_target "$1"
	rename_parity_issue "$1" 'Second target title'
	set_fixture_database "$1" "$1/work/.beads/metadata.json" other
	rename_parity_issue "$1" 'Source database title'
	set_fixture_database "$1" "$1/work/.beads/metadata.json" test
	link_redirect_chain "$1"
	set_fixture_database "$1" "$1/work/sub/.beads/metadata.json" other
}
# The second target redirects again, to a third workspace: a command that opens a store reads the second
# target's database, and where reports the third workspace.
redirect_chain_of_three() {
	mkdir "$1/work/sub" "$1/work/final" "$1/work/third"
	copy_fixture_tree "$1/work/.beads" "$1/work/sub/.beads"
	rename_parity_issue "$1" 'Second target title'
	copy_fixture_tree "$1/work/.beads" "$1/work/final/.beads"
	rename_parity_issue "$1" 'Third target title'
	mv -f "$1/work/.beads" "$1/work/third/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
	printf '../final/.beads\n' >"$1/work/sub/.beads/redirect"
	printf '../third/.beads\n' >"$1/work/final/.beads/redirect"
}
real_database_setup=redirect_chain_to_workspace
compare_real_database chain-to-workspace-where exact where
compare_real_database chain-to-workspace-where-json exact where --json
compare_real_database chain-to-workspace-info-json exact info --json
compare_real_database chain-to-workspace-count exact count
compare_real_database chain-to-workspace-list-json exact list --json
compare_real_database chain-to-workspace-show exact show "$real_database_issue_id"
compare_real_database chain-to-workspace-config-get exact config get issue_prefix
compare_real_database chain-to-workspace-version stderr-only version
compare_real_database chain-to-workspace-change-directory-where exact -C . where
compare_real_database chain-to-workspace-change-directory-list-json exact -C . list --json
compare_real_database chain-to-workspace-db-flag-list-json exact --db sub/.beads/embeddeddolt list --json
real_database_extra_env=('BEADS_DIR=<work>/.beads')
compare_real_database chain-to-workspace-beads-dir-where exact where
compare_real_database chain-to-workspace-beads-dir-list-json exact list --json
real_database_extra_env=('BEADS_DIR=<work>/sub/.beads')
compare_real_database chain-to-workspace-first-target-beads-dir-where exact where
real_database_extra_env=(BD_DEBUG_ROUTING=1)
compare_real_database routed-chain-to-workspace-where exact where
compare_real_database routed-chain-to-workspace-count exact count
compare_real_database routed-chain-to-workspace-info-json exact info --json
compare_real_database routed-chain-to-workspace-change-directory-where exact -C . where
real_database_setup=redirect_chain_with_source_database
compare_real_database routed-chain-source-database-list-json exact list --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database chain-source-database-show-json exact show "$real_database_issue_id" --json
compare_real_database chain-source-database-where exact where
real_database_setup=redirect_chain_of_three
compare_real_database chain-of-three-where exact where
compare_real_database chain-of-three-list-json exact list --json
compare_real_database chain-of-three-info-json exact info --json
# A chain of four: the body of where finds the third target through the second, and FindDatabasePath there
# follows one redirect only, so where prints the third target's database, not the fourth's.
redirect_chain_of_four() {
	redirect_chain_of_three "$1"
	mkdir "$1/work/fourth"
	copy_fixture_tree "$1/work/third/.beads" "$1/work/fourth/.beads"
	printf '../fourth/.beads\n' >"$1/work/third/.beads/redirect"
}
real_database_setup=redirect_chain_of_four
compare_real_database chain-of-four-where exact where
compare_real_database chain-of-four-where-json exact where --json
compare_real_database chain-of-four-info-json exact info --json
compare_real_database chain-of-four-list-json exact list --json
compare_real_database chain-of-four-change-directory-where exact -C . where
real_database_setup=""
# On macOS upstream's FollowRedirect canonicalizes a redirect target with utils.CanonicalizePath, which takes
# each name's case from the file system, and so does its lookup of a BEADS_DIR path. A redirect file or a
# BEADS_DIR that names a directory in another case then prints the directory as stored, in the routing lines
# and the warnings (beadshx-m08.52). These cases need a case-insensitive file system.
if [[ -d "$real_database_seed/WORK" ]]; then
	redirect_to_sub_in_other_case() {
		redirect_to_sub "$1"
		printf 'SUB/.BEADS\n' >"$1/work/.beads/redirect"
	}
	# An absolute target that names the work directory in another case too.
	redirect_to_absolute_sub_in_other_case() {
		redirect_to_sub "$1"
		printf '%s/WORK/Sub/.Beads\n' "$(cd "$1" && pwd -P)" >"$1/work/.beads/redirect"
	}
	redirect_chain_in_other_case() {
		redirect_chain_to_workspace "$1"
		printf 'SUB/.BEADS\n' >"$1/work/.beads/redirect"
		printf '../FINAL/.Beads\n' >"$1/work/sub/.beads/redirect"
	}
	redirect_in_other_case_to_directory_without_database() {
		mkdir -p "$1/work/empty/.beads"
		printf 'EMPTY/.BEADS\n' >"$1/work/.beads/redirect"
	}
	real_database_extra_env=(BD_DEBUG_ROUTING=1)
	real_database_setup=redirect_to_sub_in_other_case
	compare_real_database routed-case-redirect-count exact count
	compare_real_database routed-case-redirect-where exact where
	compare_real_database routed-case-redirect-list-json exact list --json
	compare_real_database routed-case-redirect-change-directory-where exact -C . where
	real_database_extra_env=(BD_DEBUG_ROUTING=1 'BEADS_DIR=<work>/.BEADS')
	compare_real_database routed-case-redirect-beads-dir-count exact count
	compare_real_database routed-case-redirect-beads-dir-where exact where
	real_database_extra_env=(BD_DEBUG_ROUTING=1)
	real_database_setup=redirect_to_absolute_sub_in_other_case
	compare_real_database routed-case-absolute-redirect-count exact count
	real_database_setup=redirect_chain_in_other_case
	compare_real_database routed-case-chain-count exact count
	compare_real_database routed-case-chain-change-directory-where exact -C . where
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
	compare_real_database case-chain-where exact where
	real_database_setup=redirect_in_other_case_to_directory_without_database
	compare_real_database case-redirect-without-database-count exact count
	real_database_setup=""
fi
# Upstream's canonicalizeBeadsDirPath (internal/beads/beads.go:205-275) replaces a redirect target or a BEADS_DIR
# path in a detached commit worktree, a path with /refs/commits/, with the .beads directory of a branch worktree of
# the same repository that has the same commit checked out. It takes the first such worktree, those outside
# /refs/commits/ first and then by path, and only when its .beads is a directory. Here refs/commits/snapshot is a
# detached worktree of the seed's first commit, and the workspace moves to the branch worktree feature-wt at that
# commit; the main worktree has a later commit (beadshx-m08.51). A worktree checks out the tracked metadata.json and
# config.yaml of the seed's .beads, without its database.
detached_commit_worktrees() {
	: "${1:?}"
	git -C "$1/work" worktree add -q --detach refs/commits/snapshot HEAD~1
	git -C "$1/work" worktree add -q -b feature feature-wt HEAD~1
	rm -rf "$1/work/feature-wt/.beads"
	mv -f "$1/work/.beads" "$1/work/feature-wt/.beads"
	mkdir -m 700 "$1/work/.beads"
}
redirect_to_detached_commit_worktree() {
	detached_commit_worktrees "$1"
	printf 'refs/commits/snapshot/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=redirect_to_detached_commit_worktree
compare_real_database detached-worktree-target-where exact where
compare_real_database detached-worktree-target-count exact count
compare_real_database detached-worktree-target-list-json exact list --json
real_database_extra_env=(BD_DEBUG_ROUTING=1)
compare_real_database routed-detached-worktree-target-count exact count
compare_real_database routed-detached-worktree-target-where exact where
# The detached worktree's own redirect, to a directory inside it, names the branch worktree's .beads too; so does
# BEADS_DIR when it names the detached worktree's .beads, and then upstream follows no redirect.
redirect_inside_detached_commit_worktree() {
	detached_commit_worktrees "$1"
	mkdir "$1/work/refs/commits/snapshot/sub"
	copy_fixture_tree "$1/work/feature-wt/.beads" "$1/work/refs/commits/snapshot/sub/.beads"
	printf 'sub/.beads\n' >"$1/work/refs/commits/snapshot/.beads/redirect"
}
real_database_setup=redirect_inside_detached_commit_worktree
compare_real_database routed-detached-worktree-change-directory-count exact -C refs/commits/snapshot count
real_database_extra_env=(BD_DEBUG_ROUTING=1 'BEADS_DIR=<work>/refs/commits/snapshot/.beads')
compare_real_database routed-detached-worktree-beads-dir-count exact count
compare_real_database routed-detached-worktree-beads-dir-where exact where
real_database_extra_env=(BD_DEBUG_ROUTING=1)
real_database_directory=refs/commits/snapshot
compare_real_database routed-inside-detached-worktree-count exact count
compare_real_database routed-inside-detached-worktree-where exact where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database inside-detached-worktree-list-json exact list --json
real_database_directory=""
# Without a .beads directory in that branch worktree, upstream keeps the detached worktree's.
redirect_to_detached_commit_worktree_only() {
	redirect_to_detached_commit_worktree "$1"
	rm -rf "$1/work/refs/commits/snapshot/.beads"
	mv -f "$1/work/feature-wt/.beads" "$1/work/refs/commits/snapshot/.beads"
}
real_database_setup=redirect_to_detached_commit_worktree_only
real_database_extra_env=(BD_DEBUG_ROUTING=1)
compare_real_database routed-detached-worktree-only-count exact count
compare_real_database routed-detached-worktree-only-where exact where
# Upstream checks only the first branch worktree: a-wt sorts before feature-wt and has no .beads, so the target
# stays the detached worktree's .beads, which has no database.
redirect_to_detached_commit_worktree_beside_branch_without_beads() {
	redirect_to_detached_commit_worktree "$1"
	git -C "$1/work" worktree add -q -b alpha a-wt HEAD~1
	rm -rf "$1/work/a-wt/.beads"
}
real_database_setup=redirect_to_detached_commit_worktree_beside_branch_without_beads
compare_real_database routed-detached-worktree-first-branch-without-beads-count exact count
compare_real_database routed-detached-worktree-first-branch-without-beads-where exact where
# A branch worktree under /refs/commits/ comes after one outside it, although its path sorts first.
redirect_to_detached_commit_worktree_beside_branch_under_refs() {
	: "${1:?}"
	git -C "$1/work" worktree add -q --detach refs/commits/snapshot HEAD~1
	git -C "$1/work" worktree add -q -b pinned refs/commits/pinned HEAD~1
	git -C "$1/work" worktree add -q -b zebra zebra-wt HEAD~1
	rm -rf "$1/work/zebra-wt/.beads"
	mv -f "$1/work/.beads" "$1/work/zebra-wt/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'refs/commits/snapshot/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=redirect_to_detached_commit_worktree_beside_branch_under_refs
compare_real_database routed-detached-worktree-stable-branch-first-count exact count
# A detached worktree of the main worktree's commit makes the main worktree the first candidate. The redirect then
# names its own directory, which has no database, and upstream ignores it with a warning.
redirect_to_detached_commit_worktree_of_head() {
	: "${1:?}"
	git -C "$1/work" worktree add -q --detach refs/commits/snapshot HEAD
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'refs/commits/snapshot/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=redirect_to_detached_commit_worktree_of_head
compare_real_database routed-detached-worktree-of-head-count exact count
compare_real_database routed-detached-worktree-of-head-where exact where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=""
# Each setup reloads the config of its own directory and checks that directory's metadata.json: a command
# that opens a store sets up the first target and then the second, and so does where. So a config.yaml that
# does not parse warns in the setup of its own target, and the shared-server notice comes from the first
# setup whose target pins dolt_mode embedded.
chain_broken_config_target=""
redirect_chain_with_broken_config() {
	redirect_chain_to_workspace "$1"
	printf '[a, b\n' >>"$1/work/$chain_broken_config_target/.beads/config.yaml"
}
real_database_setup=redirect_chain_with_broken_config
chain_broken_config_target=sub
compare_real_database chain-first-target-broken-config-count exact count
compare_real_database chain-first-target-broken-config-list-json exact list --json
compare_real_database chain-first-target-broken-config-where exact where
chain_broken_config_target=final
compare_real_database chain-second-target-broken-config-count exact count
compare_real_database chain-second-target-broken-config-where exact where
chain_broken_config_target=""
real_database_setup=""
# Upstream's legacy-workspace guard runs again after the second setup (cmd/bd/main.go:1319), so a legacy layout in
# the second target stops a command that opens a store, after the first target's setup and guard. where guards only
# its pre-run setup, the first target (beadshx-m08.54). With -C, both setups and the first guard take the second
# target, also for where, so a legacy first target no longer counts. A metadata.json there that does not load makes
# FindDatabasePath find no database, so upstream reports that, except with -C, where the first setup loads it, and
# where's second setup warns.
chain_second_target_layout=""
redirect_chain_with_second_target_layout() {
	redirect_chain_to_workspace "$1"
	case "$chain_second_target_layout" in
	legacy-dolt) mv -f "$1/work/final/.beads/embeddeddolt" "$1/work/final/.beads/dolt" ;;
	first-target-legacy-dolt) mv -f "$1/work/sub/.beads/embeddeddolt" "$1/work/sub/.beads/dolt" ;;
	legacy-server)
		jq '.dolt_mode = "server"' "$1/work/final/.beads/metadata.json" >"$1/metadata.json"
		cat "$1/metadata.json" >"$1/work/final/.beads/metadata.json"
		rm -f "$1/metadata.json"
		printf '0.58.0\n' >"$1/work/final/.beads/.local_version"
		;;
	broken-metadata) printf '{bad' >"$1/work/final/.beads/metadata.json" ;;
	esac
}
real_database_setup=redirect_chain_with_second_target_layout
chain_second_target_layout=legacy-dolt
compare_real_database chain-second-target-legacy-dolt-count exact count
compare_real_database chain-second-target-legacy-dolt-list-json exact list --json
compare_real_database chain-second-target-legacy-dolt-config-get exact config get issue_prefix
compare_real_database chain-second-target-legacy-dolt-change-directory-count exact -C . count
compare_real_database chain-second-target-legacy-dolt-where exact where
compare_real_database chain-second-target-legacy-dolt-change-directory-where exact -C . where
compare_real_database chain-second-target-legacy-dolt-change-directory-where-json exact -C . where --json
chain_second_target_layout=first-target-legacy-dolt
compare_real_database chain-first-target-legacy-dolt-count exact count
compare_real_database chain-first-target-legacy-dolt-change-directory-count exact -C . count
compare_real_database chain-first-target-legacy-dolt-change-directory-list-json exact -C . list --json
compare_real_database chain-first-target-legacy-dolt-change-directory-where exact -C . where
chain_second_target_layout=legacy-server
compare_real_database chain-second-target-legacy-server-show exact show "$real_database_issue_id"
chain_second_target_layout=broken-metadata
compare_real_database chain-second-target-broken-metadata-count exact count
compare_real_database chain-second-target-broken-metadata-config-get exact config get issue_prefix
compare_real_database chain-second-target-broken-metadata-change-directory-count exact -C . count
compare_real_database chain-second-target-broken-metadata-where exact where
chain_second_target_layout=""
real_database_setup=""
# Upstream then reaches for the shared server, which creates files under HOME and TMPDIR; this build refuses
# after the same warnings and the notice for the first target.
redirect_chain_first_target_pins_embedded() {
	redirect_chain_to_workspace "$1"
	jq 'del(.dolt_mode)' "$1/work/final/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/final/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
chain_warning='Warning: redirect chains not allowed, ignoring redirect in <work>/sub/.beads'
candidate_only_setup=redirect_chain_first_target_pins_embedded
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure chain-first-target-notice-shared-server-count-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$shared_server_notice"$'\n''Error: count is not available yet in shared-server mode in this build' "" \
	count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
# When the second target is legacy-only, upstream's FindDatabasePath rewrites its config.json as metadata.json:
# a command that opens a store after its first setup, where in its body. This build refuses there instead.
redirect_chain_to_legacy_workspace() {
	redirect_chain_to_workspace "$1"
	mv -f "$1/work/final/.beads/metadata.json" "$1/work/final/.beads/config.json"
}
candidate_only_setup=redirect_chain_to_legacy_workspace
expect_candidate_failure chain-legacy-second-target-count-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"Error: $(legacy_config_refusal count)" "" count
expect_candidate_failure chain-legacy-second-target-list-json-unported \
	"{\"error\":\"$(legacy_config_refusal list)\",\"schema_version\":1}" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning" "" list --json
expect_candidate_failure chain-legacy-second-target-where-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"Error: $(legacy_config_refusal where)" "" where
expect_candidate_failure chain-legacy-second-target-change-directory-count-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"Error: $(legacy_config_refusal count)" "" -C . count
candidate_only_setup=""
# Upstream's guard reads the first target before FindDatabasePath follows its redirect, so a legacy Dolt first
# target refuses before the rewrite of the second. With -C, the first setup and the guard already take the second
# target, which the guard accepts, so this build refuses the rewrite there.
redirect_chain_to_legacy_workspace_from_legacy_dolt() {
	redirect_chain_to_legacy_workspace "$1"
	mv -f "$1/work/sub/.beads/embeddeddolt" "$1/work/sub/.beads/dolt"
}
real_database_setup=redirect_chain_to_legacy_workspace_from_legacy_dolt
compare_real_database chain-legacy-dolt-first-target-count exact count
compare_real_database chain-legacy-dolt-first-target-where exact where
real_database_setup=""
candidate_only_setup=redirect_chain_to_legacy_workspace_from_legacy_dolt
expect_candidate_failure chain-legacy-dolt-first-target-change-directory-count-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"Error: $(legacy_config_refusal count)" "" -C . count
candidate_only_setup=""
# The second setup loads the second target's .env file for each variable that is not set yet, after the
# first target's. A command that opens a store then reads its JSON switch again (refreshBoundCommandConfig),
# also from the second target's config.yaml; the body of where does not. With -C, both setups take the second
# target, so the first target's .env file stays unread. The first target's dolt_database is kept before the
# second target's file loads, so a BEADS_DOLT_SERVER_DATABASE there applies only without one.
chain_first_dotenv=""
chain_second_dotenv=""
redirect_chain_with_dotenv() {
	redirect_chain_to_workspace "$1"
	if [[ -n "$chain_first_dotenv" ]]; then
		printf '%s\n' "$chain_first_dotenv" >"$1/work/sub/.beads/.env"
	fi
	if [[ -n "$chain_second_dotenv" ]]; then
		printf '%s\n' "$chain_second_dotenv" >"$1/work/final/.beads/.env"
	fi
}
redirect_chain_with_json_setting() {
	redirect_chain_to_workspace "$1"
	printf 'json: true\n' >>"$1/work/final/.beads/config.yaml"
}
redirect_chain_source_database_with_dotenv() {
	redirect_chain_with_source_database "$1"
	printf 'BEADS_DOLT_SERVER_DATABASE=test\n' >"$1/work/final/.beads/.env"
}
redirect_chain_without_source_database_with_dotenv() {
	redirect_chain_with_source_database "$1"
	jq 'del(.dolt_database)' "$1/work/sub/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/sub/.beads/metadata.json"
	rm -f "$1/metadata.json"
	printf 'BEADS_DOLT_SERVER_DATABASE=other\n' >"$1/work/final/.beads/.env"
}
real_database_setup=redirect_chain_with_dotenv
chain_second_dotenv='BD_JSON=1'
compare_real_database chain-second-dotenv-count exact count
compare_real_database chain-second-dotenv-list exact list
compare_real_database chain-second-dotenv-change-directory-count exact -C . count
compare_real_database chain-second-dotenv-where exact where
compare_real_database chain-second-dotenv-change-directory-where exact -C . where
chain_first_dotenv='BD_JSON=false'
compare_real_database chain-first-dotenv-wins-count exact count
chain_second_dotenv=""
chain_first_dotenv='BD_JSON=1'
compare_real_database chain-first-dotenv-change-directory-count exact -C . count
chain_first_dotenv=""
chain_second_dotenv='BEADS_DOLT_SHARED_SERVER=1'
compare_real_database chain-second-dotenv-shared-server-where exact where
chain_second_dotenv=""
real_database_setup=redirect_chain_with_json_setting
compare_real_database chain-second-json-setting-count exact count
compare_real_database chain-second-json-setting-where exact where
compare_real_database chain-second-json-setting-change-directory-where exact -C . where
real_database_setup=redirect_chain_source_database_with_dotenv
compare_real_database chain-source-database-second-dotenv-show-json exact show "$real_database_issue_id" --json
real_database_setup=redirect_chain_without_source_database_with_dotenv
compare_real_database chain-second-dotenv-database-show-json exact show "$real_database_issue_id" --json
real_database_setup=""
# With BEADS_DOLT_SHARED_SERVER in the second target's .env file, upstream reaches for the shared server,
# which creates files under HOME and TMPDIR; this build refuses after the same warnings and notice.
chain_shared_server_dotenv() {
	chain_second_dotenv='BEADS_DOLT_SHARED_SERVER=1'
	redirect_chain_with_dotenv "$1"
	chain_second_dotenv=""
}
candidate_only_setup=chain_shared_server_dotenv
expect_candidate_failure chain-second-dotenv-shared-server-count-unported "" \
	"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$chain_warning"$'\n'"$shared_server_notice"$'\n''Error: count is not available yet in shared-server mode in this build' "" \
	count
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
# Group and others can read the work directory, so upstream's setup also warns about `.`.
expect_candidate_failure no-metadata-missing-db-flag-unported "" \
	'Warning: . has permissions 0755 (recommended: 0700). Run: chmod 700 .'$'\n''warning: no beads configuration found in .; using default database name "beads"'$'\n''Error: count is not available yet when the embedded store has no database named "beads" in this build' "" \
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
# For a --db path that no workspace claims, upstream takes the first .beads directory beside the path's
# directory or one of its ancestors (resolveCommandBeadsDir), and so does this build. Upstream then
# creates `beads` in that directory's embedded store, which this build refuses. Group and others can
# read that directory, so its setup first warns about its permissions.
no_metadata_nested_directories() {
	no_metadata_default_database "$1"
	mkdir -p "$1/work/sub/.beads" "$1/work/sub/data"
}
candidate_only_setup=no_metadata_nested_directories
expect_candidate_failure no-metadata-db-flag-ancestor-unported "" \
	'Warning: sub/.beads has permissions 0755 (recommended: 0700). Run: chmod 700 sub/.beads'$'\n''warning: no beads configuration found in sub/.beads; using default database name "beads"'$'\n''Error: count is not available yet when the embedded store has no database named "beads" in this build' "" \
	--db sub/data/x count
candidate_only_setup=""
# `where` names that directory, warns twice about its permissions, and writes nothing.
nested_directories() {
	mkdir -p "$1/work/sub/.beads" "$1/work/sub/data"
}
nested_directories_without_metadata() {
	no_metadata_default_database "$1"
	nested_directories "$1"
}
real_database_read_only=1
real_database_setup=nested_directories_without_metadata
compare_real_database db-flag-ancestor-where exact where --db sub/data/x
compare_real_database db-flag-ancestor-where-json exact where --db sub/data/x --json
real_database_setup=nested_directories
compare_real_database db-flag-ancestor-metadata-where exact where --db sub/data/x
real_database_read_only=""
# With a `beads` database in that directory's embedded store, upstream warns and reads it, and so does
# this build.
nested_database_without_metadata() {
	nested_directories_without_metadata "$1"
	mkdir "$1/work/sub/.beads/embeddeddolt"
	copy_fixture_tree "$1/work/.beads/embeddeddolt/beads" "$1/work/sub/.beads/embeddeddolt/beads"
}
real_database_setup=nested_database_without_metadata
compare_real_database db-flag-ancestor-database-count exact --db sub/data/x count
compare_real_database db-flag-ancestor-database-list-json exact --db sub/data/x list --json
real_database_setup=""
# Without metadata.json and without a database directory, upstream finds no database. It prints only
# `no beads database found`, before its --global and --database checks, and writes nothing.
real_database_read_only=1
real_database_setup=remove_database_and_metadata
compare_real_database no-database-no-metadata-count exact count
compare_real_database no-database-no-metadata-list-json exact list --json
compare_real_database no-database-no-metadata-readonly-ready exact --readonly ready
compare_real_database no-database-no-metadata-show exact show "$real_database_issue_id"
compare_real_database no-database-no-metadata-info-json exact info --json
compare_real_database no-database-no-metadata-types exact types
compare_real_database no-database-no-metadata-config-get exact config get issue_prefix
compare_real_database no-database-no-metadata-global exact count --global
compare_real_database no-database-no-metadata-database-flag exact count --database other
compare_real_database no-database-no-metadata-db-name-json exact --db other count --json
compare_real_database no-database-no-metadata-where exact where
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database no-database-no-metadata-shared-server-list exact list
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A config.yaml that does not parse: upstream sets the workspace up once, then finds no database.
compare_real_database_config no-database-no-metadata-broken-config exact "$malformed_yaml" count
compare_real_database_config no-database-no-metadata-broken-config-list-json exact "$malformed_yaml" list --json
# With metadata.json and no embedded store, the --database checks also come after the missing database.
real_database_setup=remove_embedded_database
compare_real_database no-database-database-flag-json exact count --database other --json
compare_real_database no-database-db-name exact --db other list
real_database_setup=""
# A --db value that names a database finds the workspace as without --db, so upstream sets it up twice.
compare_real_database_config db-name-broken-config exact "$malformed_yaml" --db other count

# Workspace gates. Before it opens the store, upstream's pre-run takes the workspace gate,
# .beads.gate.lock beside the .beads directory, and the gate beside the data directory, such as
# .beads/embeddeddolt.gate.lock: a shared flock, tried once without a wait (cmd/bd/main.go:1332,
# cmd/bd/workspace_gate.go:174). A maintenance command (bd init, bd migrate, bd backup restore)
# holds them exclusively, and then upstream refuses with the first held gate in path order. bdhx
# takes the same locks on the files that exist, which it opens read-only. Here a helper process
# holds a gate on each side, and the cases leave both fixtures unchanged.
gate_lock_python='
import fcntl
import signal
import sys

action, path, mode = sys.argv[1:4]
operation = fcntl.LOCK_EX if mode == "exclusive" else fcntl.LOCK_SH
with open(path, "rb") as handle:
    if action == "hold":
        fcntl.flock(handle, operation)
        print("locked", flush=True)
        signal.pause()
    else:
        try:
            fcntl.flock(handle, operation | fcntl.LOCK_NB)
        except BlockingIOError:
            print("held")
        else:
            print("free")
'
# Starts a helper that holds a `mode` (exclusive or shared) flock on the file `lock` below the work
# directory of the state root `root` until release_gate_holders. Its pid file ends in .watch.pid, so
# the exit trap stops it too.
hold_gate_lock() {
	local root="$1" lock="$2" mode="$3"
	python3 -I -c "$gate_lock_python" hold "$root/work/$lock" "$mode" >"$root.gate-holder.ready" &
	printf '%s\n' "$!" >"$root.gate-holder.watch.pid"
	for _ in {1..200}; do
		if grep -qx locked "$root.gate-holder.ready"; then
			return 0
		fi
		sleep 0.05
	done
	printf 'gate helper did not lock %s\n' "$root/work/$lock" >&2
	return 1
}
release_gate_holders() {
	local pid_file pid
	while IFS= read -r pid_file; do
		pid="$(cat "$pid_file")"
		kill -TERM "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
		rm -f "$pid_file" "${pid_file%.watch.pid}.ready"
	done < <(find "$test_root" -name '*.gate-holder.watch.pid' -type f)
}
compare_real_database_gate() {
	compare_real_database "$@"
	release_gate_holders
}
hold_workspace_gate() { hold_gate_lock "$1" .beads.gate.lock exclusive; }
hold_root_gate() { hold_gate_lock "$1" .beads/embeddeddolt.gate.lock exclusive; }
share_workspace_gate() { hold_gate_lock "$1" .beads.gate.lock shared; }
# The holder record that an exclusive holder writes beside the gate file. Go's json.Unmarshal matches
# the Hostname key without case, and the start time prints in UTC.
record_gate_holder() {
	printf '%s\n' '{"pid": 4242, "Hostname": "fixture-host", "reason": "bd backup restore", "started_at": "2026-01-02T03:04:05.123+02:00"}' \
		>"$1/work/.beads.gate.lock.info"
	hold_workspace_gate "$1"
}
gate_refusal_prefix='a maintenance operation is running on this workspace; retry when it completes: workspacegate: <work>'
gate_unrecorded='(shared mode) held by another bd process (no holder info recorded): workspace gate busy'
real_database_read_only=1
real_database_setup=hold_workspace_gate
compare_real_database_gate gate-held-count exact count
compare_real_database_gate gate-held-list-json exact list --json
compare_real_database_gate gate-held-quiet-show exact -q show "$real_database_issue_id"
compare_real_database_gate gate-held-config-get exact config get issue_prefix
compare_real_database_gate gate-held-types-json exact types --json
real_database_extra_env=(BD_JSON_ENVELOPE=1)
compare_real_database_gate gate-held-envelope-count-json exact count --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Commands that open no store take no gate.
compare_real_database_gate gate-held-where exact where
compare_real_database_gate gate-held-version stderr-only version
real_database_setup=hold_root_gate
compare_real_database_gate gate-root-held-ready exact ready
real_database_setup=record_gate_holder
compare_real_database_gate gate-recorded-holder-count exact count
# Another reader holds the gate shared, which never blocks a reader.
real_database_setup=share_workspace_gate
compare_real_database_gate gate-shared-holder-list exact list
real_database_setup=""
compare_real_database gate-free-count-json exact count --json
# Upstream refuses to gate a directory that is a symbolic link: it warns on stderr, unless --quiet,
# and reads without the gates. A --db path names the .beads link itself; discovery without --db names
# the link's target, whose gate it takes.
link_beads_to_target() {
	mv -f "$1/work/.beads" "$1/work/beads-target"
	ln -s beads-target "$1/work/.beads"
}
real_database_setup=link_beads_to_target
compare_real_database gate-link-db-count exact --db .beads count
compare_real_database gate-link-db-embedded-list-json exact --db .beads/embeddeddolt list --json
compare_real_database gate-link-db-quiet-count exact -q --db .beads count
compare_real_database gate-link-db-config-get exact --db .beads config get issue_prefix
hold_linked_target_gate() {
	link_beads_to_target "$1"
	: >"$1/work/beads-target.gate.lock"
	hold_gate_lock "$1" beads-target.gate.lock exclusive
}
real_database_setup=hold_linked_target_gate
compare_real_database_gate gate-link-target-held-count exact count
link_embedded_root() {
	mv -f "$1/work/.beads/embeddeddolt" "$1/work/.beads/embedded-target"
	ln -s embedded-target "$1/work/.beads/embeddeddolt"
}
real_database_setup=link_embedded_root
compare_real_database gate-root-link-count exact count
# Upstream opens a gate file for writing, which fails for a directory: it warns and reads ungated.
make_gate_directory() {
	rm -f "$1/work/.beads/embeddeddolt.gate.lock"
	mkdir "$1/work/.beads/embeddeddolt.gate.lock"
}
real_database_setup=make_gate_directory
compare_real_database gate-directory-count exact count
real_database_setup=""
real_database_read_only=""
# Upstream creates a missing gate file, an empty file with mode 0600, and locks it. bdhx writes nothing,
# so it reads without a lock on that file, and takes the gates whose files exist.
remove_embedded_gate_lock() {
	rm -f "$1/work/.beads/embeddeddolt.gate.lock"
}
real_database_setup=remove_embedded_gate_lock
compare_real_database missing-gate-lock-count exact count
compare_real_database missing-gate-lock-readonly-list-json exact --readonly list --json
real_database_setup=""
remove_gate_locks() {
	rm -f "$1/work/.beads.gate.lock" "$1/work/.beads/embeddeddolt.gate.lock"
}
candidate_only_setup=remove_gate_locks
candidate_only_exit=0
expect_candidate_failure gate-missing-locks-config-get test "" "" config get issue_prefix
# Upstream cannot open a gate file that it may read but not write, so it warns and reads ungated.
# bdhx opens the file read-only, takes the lock and prints no warning.
make_gate_read_only() {
	chmod 0400 "$1/work/.beads.gate.lock"
}
candidate_only_setup=make_gate_read_only
expect_candidate_failure gate-read-only-lock-config-get test "" "" config get issue_prefix
candidate_only_exit=1
remove_workspace_gate_hold_root() {
	rm -f "$1/work/.beads.gate.lock"
	hold_root_gate "$1"
}
candidate_only_setup=remove_workspace_gate_hold_root
expect_candidate_failure gate-missing-workspace-lock-root-held "" \
	"Error: $gate_refusal_prefix/.beads/embeddeddolt.gate.lock $gate_unrecorded" "" count
release_gate_holders
candidate_only_setup=""
# BEADS_DOLT_DATA_DIR names the Dolt directory that `where` reports when the embedded store is missing.
make_custom_data_directory() {
	remove_embedded_database "$1"
	mkdir "$1/work/.beads/data"
}
real_database_read_only=1
real_database_setup=make_custom_data_directory
real_database_extra_env=(BEADS_DOLT_DATA_DIR=data)
compare_real_database data-dir-variable-where exact where
# Upstream finds the database there, but its embedded open still uses .beads/embeddeddolt. In strict
# read-only mode that open fails before it writes, after its check of the database name, with the same
# plain error in every output mode (beadshx-m08-03.13).
compare_real_database data-dir-variable-readonly-count exact --readonly count
compare_real_database data-dir-variable-readonly-list-json exact --readonly list --json
compare_real_database data-dir-variable-readonly-show exact --readonly show "$real_database_issue_id"
compare_real_database data-dir-variable-readonly-info-json exact --readonly info --json
compare_real_database data-dir-variable-readonly-config-get exact --readonly config get routing.mode
compare_real_database_config data-dir-variable-readonly-setting-ready exact 'readonly: true' ready
compare_real_database_metadata data-dir-variable-readonly-invalid-name exact '.dolt_database = "te-st"' --readonly count
real_database_extra_env=("BEADS_DOLT_DATA_DIR=<work>/.beads/data")
compare_real_database data-dir-absolute-variable-readonly-stale exact --readonly stale
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database_metadata data-dir-metadata-readonly-count exact '.dolt_data_dir = "data"' --readonly count
# A file in place of .beads/embeddeddolt fails both opens before they write: the strict read-only open in the Dolt
# driver's directory check, and a plain open when it creates the directory, before its name check (beadshx-m08.54).
make_custom_data_directory_beside_store_file() {
	make_custom_data_directory "$1"
	printf 'not a directory\n' >"$1/work/.beads/embeddeddolt"
}
real_database_setup=make_custom_data_directory_beside_store_file
real_database_extra_env=(BEADS_DOLT_DATA_DIR=data)
compare_real_database data-dir-store-file-readonly-count exact --readonly count
compare_real_database data-dir-store-file-readonly-list-json exact --readonly list --json
compare_real_database data-dir-store-file-count exact count
compare_real_database data-dir-store-file-show-json exact show "$real_database_issue_id" --json
compare_real_database_metadata data-dir-store-file-readonly-invalid-name exact '.dolt_database = "te-st"' --readonly count
compare_real_database_metadata data-dir-store-file-invalid-name exact '.dolt_database = "te-st"' count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=make_custom_data_directory
# A .beads/dolt link is no legacy Dolt directory, so upstream opens the store the same way.
link_legacy_dolt_directory() {
	remove_embedded_database "$1"
	mkdir "$1/work/linked-dolt"
	ln -s ../linked-dolt "$1/work/.beads/dolt"
}
real_database_setup=link_legacy_dolt_directory
compare_real_database legacy-dolt-link-readonly-count exact --readonly count
real_database_setup=""
real_database_read_only=""
# A plain open creates .beads/embeddeddolt and the database there, also for a name that is no
# identifier, so this build refuses before it opens anything.
candidate_only_setup=make_custom_data_directory
real_database_extra_env=(BEADS_DOLT_DATA_DIR=data)
expect_candidate_failure data-dir-variable-count-unported "" \
	"Error: count is not available yet for an embedded workspace without .beads/embeddeddolt in this build" "" count
expect_candidate_failure data-dir-variable-list-json-unported \
	'{"error":"list is not available yet for an embedded workspace without .beads/embeddeddolt in this build","schema_version":1}' "" "" \
	list --json
expect_candidate_failure data-dir-variable-config-get-unported "" \
	"Error: config get is not available yet for an embedded workspace without .beads/embeddeddolt in this build" "" \
	config get routing.mode
make_custom_data_directory_with_invalid_name() {
	make_custom_data_directory "$1"
	jq '.dolt_database = "te-st"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
}
candidate_only_setup=make_custom_data_directory_with_invalid_name
expect_candidate_failure data-dir-variable-invalid-name-unported "" \
	"Error: show is not available yet for an embedded workspace without .beads/embeddeddolt in this build" "" \
	show "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
# Upstream's pre-run also refuses older workspace shapes before it tracks a version or opens a store
# (guardLegacyUpgradeWorkspace, cmd/bd/legacy_upgrade_guard.go:24), so `where` and every command that
# opens a store stop with its error after the setup of that workspace, as text even under --json, and
# write nothing. version and help pages run. A .beads/dolt directory without an embedded repository is a
# legacy Dolt workspace, named after the version in .beads/.local_version when that is 0.x.y.
move_database_to_legacy_dolt_directory() {
	: "${1:?state root}"
	mv -f "$1/work/.beads/embeddeddolt" "$1/work/.beads/dolt"
}
real_database_read_only=1
real_database_setup=move_database_to_legacy_dolt_directory
compare_real_database legacy-dolt-count exact count
compare_real_database legacy-dolt-list-json exact list --json
compare_real_database legacy-dolt-readonly-show exact --readonly show "$real_database_issue_id"
compare_real_database legacy-dolt-info-json exact info --json
compare_real_database legacy-dolt-config-get exact config get routing.mode
compare_real_database legacy-dolt-where exact where
compare_real_database legacy-dolt-where-json exact where --json
compare_real_database legacy-dolt-db-path-count exact --db .beads count
compare_real_database legacy-dolt-version stderr-only version
compare_real_database legacy-dolt-help-command exact help count
compare_real_database_config legacy-dolt-broken-config-count exact "$malformed_yaml" count
compare_real_database_config legacy-dolt-broken-config-where exact "$malformed_yaml" where
legacy_dolt_directory_beside_empty_store() {
	move_database_to_legacy_dolt_directory "$1"
	mkdir "$1/work/.beads/embeddeddolt"
}
real_database_setup=legacy_dolt_directory_beside_empty_store
compare_real_database legacy-dolt-empty-store-count exact count
legacy_dolt_directory_without_metadata() {
	move_database_to_legacy_dolt_directory "$1"
	rm -f "$1/work/.beads/metadata.json"
}
real_database_setup=legacy_dolt_directory_without_metadata
compare_real_database legacy-dolt-no-metadata-ready exact ready
legacy_version_witness=""
legacy_dolt_directory_with_version() {
	move_database_to_legacy_dolt_directory "$1"
	printf '%s\n' "$legacy_version_witness" >"$1/work/.beads/.local_version"
}
real_database_setup=legacy_dolt_directory_with_version
legacy_version_witness=0.50.1
compare_real_database legacy-dolt-version-witness-count exact count
legacy_version_witness=v0.58.2
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database legacy-dolt-server-version-shared-server-count exact count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
legacy_version_witness=0.x.1
compare_real_database legacy-dolt-invalid-version-witness-where exact where
legacy_version_witness=""
# A server workspace is a legacy one when .beads/.local_version names a 0.55 to 0.62 release, or when it
# has a .beads/dolt directory and no version witness from 1.0 or later.
server_workspace_with_version() {
	jq '.dolt_mode = "server"' "$1/work/.beads/metadata.json" >"$1/metadata.json"
	cat "$1/metadata.json" >"$1/work/.beads/metadata.json"
	rm -f "$1/metadata.json"
	printf '%s\n' "$legacy_version_witness" >"$1/work/.beads/.local_version"
}
real_database_setup=server_workspace_with_version
legacy_version_witness=0.58.0
compare_real_database legacy-server-version-count exact count
compare_real_database legacy-server-version-where exact where
server_workspace_with_dolt_directory() {
	server_workspace_with_version "$1"
	mkdir "$1/work/.beads/dolt"
}
real_database_setup=server_workspace_with_dolt_directory
legacy_version_witness=0.9.9
compare_real_database legacy-server-dolt-count exact count
legacy_version_witness=""
# A workspace whose metadata.json names no Dolt setting and whose database is a SQLite file, or one with
# only a SQLite file, is a historical SQLite workspace; a removed or unknown backend stops the command too.
configured_sqlite_workspace() {
	remove_embedded_database "$1"
	printf '{"database":"beads.db"}' >"$1/work/.beads/metadata.json"
	printf 'SQLite format 3\0parity' >"$1/work/.beads/beads.db"
}
real_database_setup=configured_sqlite_workspace
compare_real_database historical-sqlite-configured-count exact count
compare_real_database historical-sqlite-configured-where-json exact where --json
discovered_sqlite_workspace() {
	: "${1:?state root}"
	find "$1/work/.beads" -mindepth 1 -delete
	printf 'SQLite format 3\0parity' >"$1/work/.beads/beads.db"
}
real_database_setup=discovered_sqlite_workspace
compare_real_database historical-sqlite-discovered-list exact list
# Discovery skips a .beads directory that holds only a vc.db, a backup database or a legacy config.json. When
# upstream finds no workspace, guardUndiscoveredLegacyWorkspace (cmd/bd/legacy_upgrade_guard.go:177) checks
# BEADS_DIR's directory, or each .beads from the current directory up to the repository root, for where and every
# command that opens a store, before FindDatabasePath reads BEADS_DB (beadshx-m08.54, beadshx-m08-01.12). Outside
# a repository it checks only the current directory's. version runs.
undiscovered_legacy_file=""
# printf's %b turns \0 into the NUL byte of the SQLite header.
undiscovered_legacy_content='SQLite format 3\0parity'
undiscovered_legacy_workspace() {
	: "${1:?state root}"
	find "$1/work/.beads" -mindepth 1 -delete
	printf '%b' "$undiscovered_legacy_content" >"$1/work/.beads/$undiscovered_legacy_file"
	mkdir -p "$1/work/sub/dir"
}
real_database_setup=undiscovered_legacy_workspace
undiscovered_legacy_file=vc.db
compare_real_database undiscovered-vc-db-count exact count
compare_real_database undiscovered-vc-db-where-json exact where --json
compare_real_database undiscovered-vc-db-config-get exact config get issue_prefix
compare_real_database undiscovered-vc-db-version stderr-only version
real_database_directory=sub/dir
compare_real_database undiscovered-vc-db-subdirectory-list exact list
real_database_directory=""
real_database_extra_env=('BEADS_DIR=<work>/.beads')
compare_real_database undiscovered-vc-db-beads-dir-show exact show "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
undiscovered_legacy_file=beads.backup.db
compare_real_database undiscovered-backup-db-ready exact ready
undiscovered_legacy_file=config.json
undiscovered_legacy_content='{"backend":"postgres"}'
compare_real_database undiscovered-legacy-config-removed-backend-count exact count
undiscovered_legacy_content='{bad'
compare_real_database undiscovered-legacy-config-broken-where exact where
undiscovered_legacy_content='SQLite format 3\0parity'
undiscovered_legacy_without_repository() {
	undiscovered_legacy_workspace "$1"
	rm -rf "$1/work/.git"
}
real_database_setup=undiscovered_legacy_without_repository
undiscovered_legacy_file=vc.db
compare_real_database undiscovered-vc-db-outside-repository-count exact count
real_database_directory=sub/dir
compare_real_database undiscovered-vc-db-outside-repository-subdirectory-count exact count
real_database_directory=""
# The walk comes before a BEADS_DB path selects the workspace: for a path that this build follows, and for one
# that it refuses. where takes the BEADS_DB directory instead and runs no walk.
undiscovered_vc_db_beside_workspace() {
	mkdir "$1/work/db"
	mv -f "$1/work/.beads" "$1/work/db/.beads"
	mkdir -m 700 "$1/work/.beads"
	printf 'SQLite format 3\0parity' >"$1/work/.beads/vc.db"
}
real_database_setup=undiscovered_vc_db_beside_workspace
real_database_extra_env=(BEADS_DB=db/.beads)
compare_real_database beads-db-undiscovered-vc-db-count exact count
compare_real_database beads-db-undiscovered-vc-db-info-json exact info --json
compare_real_database beads-db-undiscovered-vc-db-where exact where
real_database_extra_env=(BEADS_DB=db/.beads/missing/beads.db)
compare_real_database beads-db-undiscovered-vc-db-deeper-path-list-json exact list --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# With BEADS_DIR naming a directory without project files, the guard follows its redirect once more, and the
# selection of where looks that directory up twice in the pre-run and in each of its two lookups, so a broken
# redirect warns that often.
beads_dir_with_broken_redirect() {
	: "${1:?state root}"
	rm -rf "$1/work/.beads"
	mkdir -p "$1/work/elsewhere/.beads"
	printf '../missing/.beads\n' >"$1/work/elsewhere/.beads/redirect"
}
real_database_setup=beads_dir_with_broken_redirect
real_database_extra_env=('BEADS_DIR=<work>/elsewhere/.beads')
compare_real_database undiscovered-beads-dir-broken-redirect-count exact count
compare_real_database undiscovered-beads-dir-broken-redirect-where exact where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
undiscovered_legacy_file=""
real_database_setup=""
compare_real_database_metadata removed-backend-sqlite-count exact '.backend = "sqlite"' count
compare_real_database_metadata removed-backend-postgres-where-json exact '.backend = "postgres"' where --json
compare_real_database_metadata removed-backend-mysql-config-get exact '.backend = "mysql"' config get routing.mode
compare_real_database_metadata unknown-backend-show exact '.backend = "Dolt"' show "$real_database_issue_id"
compare_real_database_metadata unknown-backend-version stderr-only '.backend = "bogus"' version
real_database_read_only=""
# In shared-server mode a legacy Dolt workspace from another release goes on to the shared server, which
# writes, so this build refuses as there.
candidate_only_setup=move_database_to_legacy_dolt_directory
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure legacy-dolt-shared-server-count-unported "" \
	"$shared_server_notice"$'\n''Error: count is not available yet in shared-server mode in this build' "" count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
# In shared-server mode upstream prints its warning for the missing metadata.json, then reaches the
# shared server, which writes. This build prints the same warning before it refuses.
candidate_only_setup=no_metadata_default_database
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
expect_candidate_failure no-metadata-shared-server-count-unported "" \
	"$no_metadata_warning"$'\n''Error: count is not available yet in shared-server mode in this build' "" count
expect_candidate_failure no-metadata-shared-server-list-json-unported \
	'{"error":"list is not available yet in shared-server mode in this build","schema_version":1}' "$no_metadata_warning" "" \
	list --json
expect_candidate_failure no-metadata-shared-server-types-unported "" \
	"$no_metadata_warning"$'\n''Error: types is not available yet in shared-server mode in this build' "" types
expect_candidate_failure no-metadata-shared-server-config-validate-unported "" \
	"$no_metadata_warning"$'\n''Error: config validate is not available yet in shared-server mode in this build' "" \
	config validate
expect_candidate_failure no-metadata-shared-server-db-flag-unported "" \
	'warning: no beads configuration found in .beads; using default database name "beads"'$'\n''Error: count is not available yet in shared-server mode in this build' "" \
	--db .beads/embeddeddolt count
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""
# Upstream compares the dolt.mode setting with `server`, and metadata.json's dolt_mode with
# `proxied-server` when it infers server mode from a host, with strings.EqualFold: ſ (U+017F) matches s.
real_database_read_only=1
real_database_extra_metadata='del(.dolt_mode)'
real_database_extra_config=$'dolt:\n  mode: ſerver'
compare_real_database folded-server-mode-setting-where exact where
compare_real_database folded-server-mode-setting-where-json exact where --json
real_database_extra_config=""
real_database_extra_metadata='.dolt_mode = "proxied-ſerver"'
real_database_extra_env=(BEADS_DOLT_SERVER_HOST=db.example.invalid)
compare_real_database folded-proxied-mode-host-where exact where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_metadata=""
real_database_read_only=""
# Without metadata.json upstream ignores that setting, but the native store open would take server mode.
no_metadata_folded_server_mode_setting() {
	no_metadata_default_database "$1"
	printf 'dolt.mode: ſerver\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=no_metadata_folded_server_mode_setting
expect_candidate_failure no-metadata-default-folded-server-mode-setting-unported "" \
	"$no_metadata_warning"$'\n''Error: count is not available yet when server mode is configured and the workspace has no .beads/metadata.json in this build' "" \
	count
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
# A grouped count with no bucket keeps the grouped shape: upstream prints "Total: 0" and an empty
# line, or a total and an empty groups list (executeCount, cmd/bd/count.go:175-225).
compare_real_database count-by-status-none-json exact count --by-status --assignee nobody --json
compare_real_database count-by-label-none-human exact count --by-label --assignee nobody
# The command body checks the --by-* flags, then the date filters in a fixed order, and only the last
# value of each flag counts. Cobra's own errors come first.
compare_real_database count-by-conflict exact count --by-status --by-type
compare_real_database count-by-conflict-json exact count --by-status --by-type --json
compare_real_database count-by-conflict-before-date exact count --created-after bogus --by-status --by-type
compare_real_database count-by-status-reset-json exact count --by-status --by-status=false --by-type --json
compare_real_database count-bad-created-after-json exact count --created-after bogus --json
compare_real_database count-dates-in-order exact count --closed-before bogus --updated-after bogus
compare_real_database count-date-last-value-json exact count --created-after bogus --created-after 2000-01-01 --json
compare_real_database count-by-conflict-unknown-flag exact count --by-status --by-type --mol-type bogus
compare_real_database count-by-conflict-bad-boolean exact count --by-status --by-type --by-label=maybe
compare_real_database count-by-conflict-help exact count --by-status --by-type --help
# count's --priority, --priority-min and --priority-max are int flags: any integer filters.
compare_real_database count-priority-json exact count --priority 1 --json
compare_real_database count-priority-outside-json exact count -p 9 --json
compare_real_database count-priority-range exact count --priority-min 1 --priority-max 0x2
compare_real_database count-priority-negative-min-json exact count --priority-min -1 --by-priority --json
compare_real_database ready-human exact ready
compare_real_database ready-plain exact ready --plain
compare_real_database ready-json exact ready --json
compare_real_database ready-limit-human exact ready --limit 2
compare_real_database ready-limit-json exact ready --limit 2 --json
compare_real_database ready-limit-attached-json exact ready -n1 --json
# The filters of the ready query: the descendants of --parent, labels, assignee, the deferred and
# excluded types, metadata, an unbounded page, which reads the counts query in its predicate form, and
# the brief rows.
compare_real_database ready-parent-json exact ready --parent "$real_database_epic_id" --json
compare_real_database ready-label-json exact ready --label smoke --json
compare_real_database ready-label-any-exclude-json exact ready --label-any parity,alpha --exclude-label beta --json
compare_real_database ready-label-pattern-json exact ready --label-pattern 'sm*' --json
compare_real_database ready-label-regex-json exact ready --label-regex '^al' --json
compare_real_database ready-assignee-json exact ready --assignee fixture --json
compare_real_database ready-include-deferred-exclude-type-json exact ready --include-deferred --exclude-type bug,epic --json
compare_real_database ready-metadata-json exact ready --has-metadata-key team --metadata-field team=port --json
compare_real_database ready-unbounded-json exact ready --limit 0 --sort oldest --json
compare_real_database ready-brief-json exact ready --brief --sort priority -n 3 --json
compare_real_database list-limit-binary-json exact list --all -n 0b1 --json
compare_real_database ready-molecule-human exact ready --mol "$real_database_molecule_id"
compare_real_database ready-molecule-json molecule-ready-json ready --mol "$real_database_molecule_id" --json
compare_real_database ready-explain-human exact ready --explain
compare_real_database ready-explain-json exact ready --explain --json
# BuildReadyExplanation makes both lists, so upstream prints an empty one as []
# (internal/types/types.go:1727 and 1767). Without blocking edges and stored is_blocked flags nothing
# is blocked; with every issue closed nothing is ready either.
no_blocking_edges_sql="DELETE FROM dependencies WHERE type IN ('blocks', 'conditional-blocks', 'waits-for')
UPDATE issues SET is_blocked = 0, updated_at = updated_at"
all_closed_sql="UPDATE issues SET status = 'closed', closed_at = '2026-08-21 13:00:00', updated_at = updated_at WHERE status <> 'closed'
UPDATE wisps SET status = 'closed', closed_at = '2026-08-21 13:00:00', updated_at = updated_at WHERE status <> 'closed'"
compare_real_database_sql ready-explain-none-blocked-json exact "$no_blocking_edges_sql" ready --explain --json
compare_real_database_sql ready-explain-none-json exact "$all_closed_sql" ready --explain --json
compare_real_database_sql ready-explain-none-human exact "$all_closed_sql" ready --explain
compare_real_database ready-gated-human exact ready --gated
compare_real_database ready-gated-json exact ready --gated --json
# With the gate open again, no molecule is ready for gate-resume dispatch.
reopen_gate_sql="UPDATE issues SET status = 'open', closed_at = NULL, updated_at = updated_at WHERE issue_type = 'gate'"
compare_real_database_sql ready-gated-none-human exact "$reopen_gate_sql" ready --gated
compare_real_database_sql ready-gated-none-json exact "$reopen_gate_sql" ready --gated --json
compare_real_database search-human exact search parity
compare_real_database search-long exact search parity --long
compare_real_database search-json exact search parity --json
compare_real_database search-missing exact search
compare_real_database search-missing-json exact search --json
compare_real_database search-query-flag exact search --query parity
# The search takes --title as the value of --all and finds list; pflag gives list the title ready.
compare_real_database search-flag-value-names-command exact --all --title list ready
compare_real_database search-flag-value-names-command-json exact --all --title list --json
# The search takes -- as the value of --all; for list, pflag reads it as the end of the flags.
compare_real_database search-dashes-as-flag-value exact --all -- list
compare_real_database search-dashes-as-title exact --title -- list
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
# A negative --offset fails after the missing expression, and as JSON under --json.
compare_real_database query-negative-offset exact query status=open --offset -1
compare_real_database query-negative-offset-json exact query status=open --offset -1 --json
compare_real_database query-negative-offset-no-expression exact query --offset -1
# An expression that the filter answers alone is ordered and bounded in SQL: by priority without
# --sort or with a --sort that upstream does not know, which --reverse reverses, then by the newest
# and the id. Rows that tie on a --sort key stay in id order, and the limit keeps the first rows in
# that order before the display sort. A predicate expression keeps the default order.
compare_real_database query-reverse-default exact query 'priority>=0' --reverse
compare_real_database query-reverse-default-json exact query status=open --reverse --json
compare_real_database query-reverse-default-limit exact query 'priority>=0' --all --reverse --limit 4
compare_real_database query-reverse-unknown-sort exact query 'priority>=0' --sort bogus --reverse
compare_real_database query-sort-status-ties exact query 'priority>=0' --all --sort status
compare_real_database query-sort-type-reverse-limit exact query 'priority>=0' --sort type --reverse --limit 4
compare_real_database query-sort-assignee exact query 'priority>=0' --sort assignee
compare_real_database query-sort-id-reverse-limit exact query "id=${real_database_molecule_id}*" --sort id --reverse --limit 1
compare_real_database query-sort-id-limit-json exact query "id=${real_database_molecule_id}*" --sort id --limit 3 --json
compare_real_database query-predicate-reverse exact query 'status=open OR status=in_progress' --reverse
compare_real_database search-id-prefix exact search test-abcd
compare_real_database search-status exact search parity --status open
compare_real_database search-label exact search parity --label smoke
compare_real_database search-label-any exact search parity --label-any alpha,smoke
compare_real_database search-priority-range exact search parity --priority-min P0 --priority-max P1
# search checks the date filters, then the priority range, then the metadata filters.
compare_real_database search-bad-priority-min exact search parity --priority-min bogus
compare_real_database search-date-before-priority exact search parity --priority-max 9 --closed-before bogus
compare_real_database search-priority-before-metadata exact search parity --has-metadata-key 1bad --priority-min high
compare_real_database search-description exact search issue --desc-contains 'Description body'
compare_real_database search-notes exact search issue --notes-contains 'Notes body'
compare_real_database search-external exact search issue --external-contains gh-42
compare_real_database search-metadata exact search issue --metadata-field team=port --has-metadata-key rank
compare_real_database search-sort-reverse exact search parity --sort title --reverse
# search takes any --sort value; one it does not know keeps the storage order.
compare_real_database search-unknown-sort exact search parity --sort bogus
compare_real_database search-unknown-sort-json exact search parity --sort bogus --reverse --json
# search asks for the query, then checks --status, before its date, priority and metadata checks.
compare_real_database search-missing-before-date exact search --created-after bogus
compare_real_database search-status-before-date exact search parity --status bogus --created-after bogus
compare_real_database search-status-before-metadata-json exact search parity --status open,all --metadata-field bad --json
compare_real_database search-valid-status-then-priority exact search parity --status open --priority-min 9
compare_real_database search-no-match exact search absent-search-token
compare_real_database stale-default exact stale
compare_real_database stale-human exact stale --days 1
compare_real_database stale-json exact stale --days 1 --json
# Upstream prints an empty stale result as [] (renderStale, cmd/bd/stale.go:59-64): no fixture
# issue is 100000 days old.
compare_real_database stale-none-json exact stale --days 100000 --json
compare_real_database stale-none-human exact stale --days 100000
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
# Issue prefix. Workspace discovery reads only config.yaml; each command that needs the prefix takes
# it from upstream's own source, and only when it needs it. where prints config.yaml's issue-prefix
# or issue_prefix, or else the stored issue_prefix, or no prefix line; it ignores BD_ISSUE_PREFIX.
# After an exact miss, partial-ID lookup takes the stored issue_prefix, also when config.yaml names
# another prefix (upstream ResolvePartialID). orphans takes the issue-prefix setting, which
# BD_ISSUE_PREFIX sets and the issue_prefix spelling does not, then the stored one, then bd.
lazy_prefix_no_stored="DELETE FROM config WHERE \`key\` = 'issue_prefix'"
compare_real_database lazy-prefix-where-stored exact where
compare_real_database lazy-prefix-where-stored-json exact where --json
compare_real_database_config lazy-prefix-where-yaml exact 'issue-prefix: yaml-prefix' where
compare_real_database_config lazy-prefix-where-yaml-json exact 'issue-prefix: yaml-prefix' where --json
compare_real_database_config lazy-prefix-where-yaml-underscore-json exact 'issue_prefix: yaml_prefix' where --json
compare_real_database_env lazy-prefix-where-ignores-env exact BD_ISSUE_PREFIX=other where
compare_real_database_sql lazy-prefix-where-none exact "$lazy_prefix_no_stored" where
compare_real_database_sql lazy-prefix-where-none-json exact "$lazy_prefix_no_stored" where --json
compare_real_database lazy-prefix-show-prefixless exact show "${real_database_issue_id#test-}"
compare_real_database_config lazy-prefix-show-prefixless-yaml exact 'issue-prefix: test' \
	show "${real_database_issue_id#test-}" --json
compare_real_database_config lazy-prefix-show-prefixless-other-yaml exact 'issue-prefix: other' \
	show "${real_database_issue_id#test-}" --short
compare_real_database_config lazy-prefix-show-abbreviated-other-yaml exact 'issue-prefix: other' show abcd1 --short
real_database_extra_config='issue-prefix: test'
real_database_extra_sql="$lazy_prefix_no_stored"
compare_real_database lazy-prefix-show-prefixless-yaml-no-stored exact show "${real_database_issue_id#test-}" --short
real_database_extra_config=""
real_database_extra_sql=""
compare_real_database_config lazy-prefix-orphans-yaml exact 'issue-prefix: other' orphans
compare_real_database_config lazy-prefix-orphans-yaml-underscore exact 'issue_prefix: other' orphans
compare_real_database_env lazy-prefix-orphans-env exact BD_ISSUE_PREFIX=other orphans --json
compare_real_database_sql lazy-prefix-orphans-none exact "$lazy_prefix_no_stored" orphans
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
# Only the default view checks the sort policy, after --offset and the BEADS_MAX_ROWS warning.
compare_real_database ready-invalid-sort exact ready --sort invalid
compare_real_database ready-invalid-sort-offset exact ready --sort invalid --offset 1
compare_real_database ready-invalid-sort-explain exact ready --explain --sort invalid
compare_real_database ready-invalid-sort-gated-json exact ready --gated --sort invalid --json
compare_real_database_env ready-invalid-sort-max-rows-malformed exact BEADS_MAX_ROWS=bogus ready --sort invalid
compare_real_database_env ready-explain-max-rows-malformed exact BEADS_MAX_ROWS=bogus ready --explain
compare_real_database ready-invalid-mol-type-json exact ready --mol-type invalid --json
compare_real_database ready-invalid-metadata-json exact ready --metadata-field missing-equals --json
compare_real_database ready-offset-direct-json exact ready --offset 1 --json
compare_real_database ready-max-rows exact ready --max-rows 1 --limit 0 --json
compare_real_database ready-claim-readonly exact --readonly ready --claim
# The command body checks the --brief rules first, then --offset, then picks --gated, --mol or
# --explain, which never check the rest. The default view then checks --mol-type and --claim, reads
# --max-rows and BEADS_MAX_ROWS, checks the metadata filters and the sort, and only then refuses
# --claim under --readonly. Cobra's own errors come first.
compare_real_database ready-brief-human exact ready --brief
compare_real_database ready-brief-gated exact ready --brief --gated
compare_real_database ready-brief-mol-json exact ready --brief --mol "$real_database_molecule_id" --json
compare_real_database ready-brief-before-offset exact ready --brief --offset 1
compare_real_database ready-offset-before-mol-type exact ready --offset 1 --mol-type bogus
compare_real_database ready-gated-ignores-mol-type exact ready --gated --mol-type bogus
compare_real_database ready-explain-ignores-metadata-json exact ready --explain --metadata-field bad --json
compare_real_database ready-gated-ignores-negative-max-rows-json exact ready --gated --max-rows -1 --json
compare_real_database ready-molecule-ignores-has-metadata-key exact ready --mol "$real_database_molecule_id" --has-metadata-key 1bad
compare_real_database ready-invalid-mol-type exact ready --mol-type invalid
compare_real_database ready-mol-type-empty-json exact ready --mol-type '' --json
compare_real_database ready-mol-type-last-value-json exact ready --mol-type bogus --mol-type swarm --json
compare_real_database ready-mol-type-before-max-rows exact ready --mol-type bogus --max-rows -1
compare_real_database ready-negative-max-rows-json exact ready --max-rows -1 --json
compare_real_database ready-max-rows-before-metadata exact ready --metadata-field bad --max-rows -1
compare_real_database ready-metadata-before-sort-json exact ready --sort bogus --has-metadata-key 1bad --json
compare_real_database ready-mol-type-bad-boolean exact ready --mol-type bogus --plain=maybe
compare_real_database ready-brief-unknown-flag exact ready --brief --wisp-type bogus
compare_real_database ready-brief-help exact ready --brief --help
compare_real_database_env ready-mol-type-max-rows-malformed exact BEADS_MAX_ROWS=bogus ready --mol-type bogus
compare_real_database_env ready-metadata-max-rows-malformed-json exact BEADS_MAX_ROWS=bogus ready --metadata-field bad --json
compare_real_database_env ready-gated-max-rows-malformed exact BEADS_MAX_ROWS=bogus ready --gated
compare_real_database ready-claim-readonly-json exact --readonly ready --claim --json
compare_real_database ready-claim-brief-readonly-json exact --readonly ready --claim --brief --json
compare_real_database ready-claim-gated-readonly exact --readonly ready --claim --gated
compare_real_database ready-claim-mol-readonly-json exact --readonly ready --claim --mol "$real_database_molecule_id" --json
compare_real_database ready-claim-explain-readonly exact --readonly ready --claim --explain
compare_real_database ready-claim-assignee-readonly exact --readonly ready --claim --assignee fixture
compare_real_database ready-claim-mol-type-readonly exact --readonly ready --claim --mol-type bogus
compare_real_database ready-claim-sort-readonly exact --readonly ready --claim --sort bogus
# The human ready view reads the bare GetReadyWork (cmd/bd/ready.go:220), not the counted query of
# --json: wisps come from their own search, which leaves out --label-pattern and --label-regex but
# applies --mol-type, joins the label tables for --label and --label-any, and then drops wisps that
# are deferred, blocked or pinned in Go; a page of --limit N reads wisps in pages of max(N, 100).
# The view then reads each issue's dependency rows and each parent, for the parent epic titles.
ready_wisp_records="$(jq -nc --arg epic "$real_database_epic_id" --arg bug "$real_database_bug_id" \
	--arg gated "$real_database_gated_molecule_id" '
	def wisp($id; $title; $priority): {id: $id, title: $title, status: "open", priority: $priority, issue_type: "task",
		created_at: "2026-08-20T10:00:00Z", updated_at: "2026-08-21T13:00:00Z", ephemeral: true};
	wisp("test-rw-plain"; "Ready wisp without labels"; 2),
	(wisp("test-rw-label"; "Ready wisp with a zz label"; 1) + {labels: ["zz-top"], assignee: "fixture", estimated_minutes: 15,
		created_at: "2026-08-20T09:00:00Z"}),
	(wisp("test-rw-swarm"; "Ready swarm wisp"; 3) + {mol_type: "swarm", created_at: "2026-08-20T11:00:00Z"}),
	(wisp("test-rw-child"; "Ready wisp under the epic"; 2) + {created_at: "2026-08-20T12:00:00Z",
		dependencies: [{issue_id: "test-rw-child", depends_on_id: $epic, type: "parent-child",
			created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]}),
	(wisp("test-rw-deferred"; "Deferred wisp"; 0) + {defer_until: "2099-01-01T00:00:00Z"}),
	(wisp("test-rw-pinned"; "Pinned wisp"; 0) + {pinned: true}),
	(wisp("test-rw-blocked"; "Blocked wisp"; 0) + {dependencies: [{issue_id: "test-rw-blocked", depends_on_id: $bug,
		type: "blocks", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]}),
	(wisp("test-rw-durable"; "Durable wisp"; 1) + {created_at: "2026-08-20T08:00:00Z"}),
	(wisp("test-rw-heartbeat"; "Heartbeat wisp"; 2) + {wisp_type: "heartbeat", created_at: "2026-08-20T13:00:00Z"}),
	# An issue under two epics: the view titles it with its last parent-child row, in depends_on_id order.
	(wisp("test-rw-two-parents"; "Issue under two epics"; 3) + {ephemeral: false, created_at: "2026-08-20T14:00:00Z",
		dependencies: [($epic, $gated) | {issue_id: "test-rw-two-parents", depends_on_id: ., type: "parent-child",
			created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]})')"
real_database_extra_import="$ready_wisp_records"
# Import marks the wisp that an open issue blocks. A wisp kept without being ephemeral stays in the wisps
# table; Dolt ignores the wisp tables, so the title change gives fixture-sql's commit something to record.
real_database_extra_sql="UPDATE wisps SET ephemeral = 0, updated_at = updated_at WHERE id = 'test-rw-durable'
UPDATE issues SET title = 'Retitled bug', updated_at = updated_at WHERE id = '$real_database_bug_id'"
compare_real_database ready-wisps-label-pattern exact ready --include-ephemeral --label-pattern 'zz*'
compare_real_database ready-wisps-label-pattern-plain exact ready --include-ephemeral --label-pattern 'zz*' --plain
compare_real_database ready-wisps-label-pattern-json exact ready --include-ephemeral --label-pattern 'zz*' --json
compare_real_database ready-wisps-label-regex-plain exact ready --include-ephemeral --label-regex '^zz' --plain
compare_real_database ready-wisps-label exact ready --include-ephemeral --label zz-top
compare_real_database ready-wisps-label-any-plain exact ready --include-ephemeral --label-any zz-top,parity --plain
compare_real_database ready-wisps-exclude-label-plain exact ready --include-ephemeral --exclude-label zz-top --plain
compare_real_database ready-wisps-mol-type exact ready --include-ephemeral --mol-type swarm
compare_real_database ready-wisps-mol-type-plain exact ready --include-ephemeral --mol-type swarm --plain
compare_real_database ready-wisps-include-deferred-plain exact ready --include-ephemeral --include-deferred --plain
compare_real_database ready-wisps-without-ephemeral-plain exact ready --plain
compare_real_database ready-wisps-pretty exact ready --include-ephemeral
compare_real_database ready-wisps-parent exact ready --include-ephemeral --parent "$real_database_epic_id"
compare_real_database ready-wisps-unassigned-plain exact ready --include-ephemeral --unassigned --plain
compare_real_database ready-wisps-assignee-plain exact ready --include-ephemeral --assignee fixture --plain
compare_real_database ready-wisps-type-priority-plain exact ready --include-ephemeral --type task --priority 2 --plain
compare_real_database ready-wisps-sort-oldest-plain exact ready --include-ephemeral --sort oldest --plain
compare_real_database ready-wisps-sort-priority exact ready --include-ephemeral --sort priority
compare_real_database ready-wisps-limit-plain exact ready --include-ephemeral --limit 3 --plain
compare_real_database ready-wisps-limit-pattern exact ready --include-ephemeral --label-pattern 'zz*' --limit 2
compare_real_database ready-wisps-unlimited-plain exact ready --include-ephemeral --limit 0 --plain
compare_real_database ready-wisps-unlimited-pattern-plain exact ready --include-ephemeral --label-pattern 'zz*' --limit 0 --plain
compare_real_database ready-wisps-max-rows exact ready --include-ephemeral --max-rows 2 --limit 0
compare_real_database ready-wisps-max-rows-pattern exact ready --include-ephemeral --label-pattern 'zz*' --max-rows 2
compare_real_database ready-wisps-max-rows-enough-plain exact ready --include-ephemeral --max-rows 40 --limit 0 --plain
compare_real_database_env ready-wisps-max-rows-env exact BEADS_MAX_ROWS=2 ready --include-ephemeral --label-regex '^zz'
real_database_extra_import=""
real_database_extra_sql=""
compare_real_database list-human exact list
compare_real_database list-json exact list --json
compare_real_database list-positional exact list parity
compare_real_database list-positional-hint-json exact list all --json
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
# --ready reads open issues whatever --status says, keeps pinned issues out, and refuses the list
# flags that the ready query cannot carry, in upstream's order.
compare_real_database list-ready-status-json exact list --ready --status closed --json
compare_real_database list-ready-status-all-json exact list --ready --status all --json
compare_real_database list-ready-sort-id-limit exact list --ready --sort id -n 2 --flat
compare_real_database list-ready-parent-brief-json exact list --ready --parent "$real_database_epic_id" --brief --json
compare_real_database list-ready-unsupported exact list --ready --title x --priority-min 1
compare_real_database list-ready-unsupported-json exact list --ready --priority-max 3 --created-after 2020-01-01 --no-labels --json
compare_real_database list-priority-min-json exact list --priority-min P1 --json
compare_real_database list-priority-max-json exact list --priority-max 1 --json
compare_real_database list-no-assignee-json exact list --no-assignee --json
compare_real_database list-no-labels-json exact list --no-labels --json
compare_real_database list-brief-json exact list --brief --json
compare_real_database list-pinned-json exact list --pinned --json
compare_real_database list-all-no-pinned-json exact list --all --no-pinned --json
compare_real_database list-no-parent-json exact list --no-parent --json
compare_real_database list-parent-human exact list --parent "$real_database_epic_id"
# Only the tree view walks every level below --parent and adds the parent as its root. --flat,
# --long --flat and --json list the direct children: rows with a parent-child edge to the
# parent, plus dotted IDs below it that have no parent-child edge. They print nothing and
# exit 0 when the parent has no children or does not exist. --pretty still wins over --flat.
compare_real_database list-parent-flat-human exact list --parent "$real_database_epic_id" --flat
compare_real_database list-parent-flat-json exact list --parent "$real_database_epic_id" --flat --json
compare_real_database list-parent-json exact list --parent "$real_database_epic_id" --json
compare_real_database list-parent-flat-long-human exact list --parent "$real_database_epic_id" --flat --long
compare_real_database list-parent-flat-long-brief-human exact list --parent "$real_database_epic_id" --flat --long --brief
compare_real_database list-parent-tree-flat-human exact list --parent "$real_database_epic_id" --tree --flat
compare_real_database list-parent-pretty-flat-human exact list --parent "$real_database_epic_id" --pretty --flat
compare_real_database list-parent-flat-middle-human exact list --parent "$real_database_child_id" --flat
compare_real_database list-parent-flat-all-human exact list --parent "$real_database_gated_molecule_id" --flat --all --include-gates
compare_real_database list-parent-flat-all-json exact list --parent "$real_database_gated_molecule_id" --flat --all --include-gates --json
compare_real_database list-parent-flat-closed-human exact list --parent "$real_database_gated_molecule_id" --flat --status closed --include-gates
compare_real_database list-parent-flat-fallback-human exact list --parent "$real_database_molecule_id" --flat
compare_real_database list-parent-flat-leaf-human exact list --parent "$real_database_grandchild_id" --flat
compare_real_database list-parent-flat-missing-human exact list --parent test-missing --flat
compare_real_database list-parent-missing-json exact list --parent test-missing --json
compare_real_database list-parent-missing-human exact list --parent test-missing
# The tree view prints a closed issue as "✓ ID P1 type Title": the plain type for every type,
# custom types too, and never the [epic] or [bug] badge that open issues get. The flat view
# keeps its own format. The records add an open epic with a closed child of each built-in
# type, a closed gate, an open bug, and a closed grandchild below the closed epic.
closed_tree_record() {
	local id="$1" title="$2" state="$3" priority="$4" type="$5" parent="$6"
	jq -nc --arg id "$id" --arg title "$title" --arg status "$state" --argjson priority "$priority" \
		--arg type "$type" --arg parent "$parent" '{
		id: $id, title: $title, status: $status, priority: $priority, issue_type: $type,
		created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z"}
		+ (if $status == "closed" then {closed_at: "2026-08-21T13:00:00Z", close_reason: "done"} else {} end)
		+ (if $parent == "" then {} else {dependencies: [{issue_id: $id, depends_on_id: $parent,
			type: "parent-child", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"}]} end)'
}
closed_tree_records="$(
	closed_tree_record test-tc "Closed types parent" open 1 epic ""
	closed_tree_record test-tc-task "Closed task child" closed 1 task test-tc
	closed_tree_record test-tc-bug "Closed bug child" closed 0 bug test-tc
	closed_tree_record test-tc-epic "Closed epic child" closed 2 epic test-tc
	closed_tree_record test-tc-feature "Closed feature child" closed 3 feature test-tc
	closed_tree_record test-tc-chore "Closed chore child" closed 4 chore test-tc
	closed_tree_record test-tc-decision "Closed decision child" closed 2 decision test-tc
	closed_tree_record test-tc-gate "Closed gate child" closed 2 gate test-tc
	closed_tree_record test-tc-open "Open bug child" open 2 bug test-tc
	closed_tree_record test-tc-grand "Closed grandchild" closed 2 task test-tc-epic
)"
compare_real_database_import list-tree-closed-types-human exact "$closed_tree_records" list --parent test-tc --all --include-gates
compare_real_database_import list-tree-closed-status-human exact "$closed_tree_records" list --parent test-tc --status closed
compare_real_database_import list-tree-closed-long-human exact "$closed_tree_records" list --parent test-tc --all --long
compare_real_database_import list-tree-closed-deps-human exact "$closed_tree_records" list --parent test-tc --all --deps=all
compare_real_database_import list-tree-closed-flat-human exact "$closed_tree_records" list --parent test-tc --all --flat --include-gates
compare_real_database_import list-tree-closed-long-flat-human exact "$closed_tree_records" list --parent test-tc --all --long --flat
compare_real_database_import list-tree-closed-all-pretty-human exact "$closed_tree_records" list --all --pretty
# Upstream's internal/ui decides once, when the process starts, whether to color (ShouldUseColor):
# BD_GIT_HOOK=1, a non-empty NO_COLOR or CLICOLOR=0 turn colors off; then any non-empty CLICOLOR_FORCE
# turns them on, also 0 and also with TERM=dumb; then TERM=dumb turns them off; otherwise stdout must
# be a terminal. --no-color turns them off again in the pre-run. A color is always 24-bit, whatever
# TERM says, from the dark palette when stdin or stdout is no terminal. These cases empty the
# harness's NO_COLOR=1 (upstream treats an empty value as unset) and add the assignments in $3. The
# records give one --parent tree each built-in status, each priority and the bug and epic types, a
# closed title with a tab (a lipgloss style turns it into four spaces, colors on or off), a
# dependency inside the view and one outside it. An eighth argument `pinned` sets the pinned flag.
color_list_record() {
	local id="$1" title="$2" state="$3" priority="$4" type="$5" parent="$6" blocker="$7" pinned="${8:-}"
	jq -nc --arg id "$id" --arg title "$title" --arg status "$state" --argjson priority "$priority" \
		--arg type "$type" --arg parent "$parent" --arg blocker "$blocker" --arg pinned "$pinned" '{
		id: $id, title: $title, status: $status, priority: $priority, issue_type: $type,
		assignee: "fixture", labels: ["colour"], description: "First line\nSecond line",
		created_at: "2026-08-20T12:00:00Z", updated_at: "2026-08-21T13:00:00Z"}
		+ (if $status == "closed" then {closed_at: "2026-08-21T13:00:00Z", close_reason: "done"} else {} end)
		+ (if $pinned == "pinned" then {pinned: true} else {} end)
		+ {dependencies: ([if $parent == "" then empty else {issue_id: $id, depends_on_id: $parent,
			type: "parent-child", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"} end]
			+ [if $blocker == "" then empty else {issue_id: $id, depends_on_id: $blocker,
			type: "blocks", created_at: "2026-08-21T10:00:00Z", created_by: "fixture"} end])}'
}
color_list_records="$(
	color_list_record test-cl "Colour parent" open 2 epic "" ""
	color_list_record test-cl-p0 "Critical bug" open 0 bug test-cl ""
	color_list_record test-cl-p1 "Active task" in_progress 1 task test-cl ""
	color_list_record test-cl-blocked "Blocked feature" blocked 3 feature test-cl ""
	color_list_record test-cl-deferred "Deferred chore" deferred 4 chore test-cl ""
	color_list_record test-cl-pinned "Pinned task" pinned 2 task test-cl ""
	color_list_record test-cl-hooked "Hooked task" hooked 2 task test-cl ""
	color_list_record test-cl-closed $'Closed\ttabbed task' closed 1 task test-cl ""
	color_list_record test-cl-closed-epic "Closed epic" closed 0 epic test-cl ""
	color_list_record test-cl-waiting "Waiting task" open 2 task test-cl test-cl-p0
	color_list_record test-cl-outside "Outside dependency" open 3 bug test-cl test-abcd11
)"
# Records that some color cases import after color_list_records.
color_list_extra_records=""
compare_real_database_colors() {
	local name="$1" comparison="$2" assignments
	read -r -a assignments <<<"NO_COLOR= $3"
	shift 3
	real_database_extra_env=("${assignments[@]}")
	real_database_extra_import="$color_list_records"
	if [[ -n "$color_list_extra_records" ]]; then
		real_database_extra_import+=$'\n'"$color_list_extra_records"
	fi
	compare_real_database "$name" "$comparison" "$@"
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
	real_database_extra_import=""
}
write_color_dotenv() {
	printf 'CLICOLOR_FORCE=1\n' >"$1/work/.beads/.env"
}
compare_real_database_colors list-color-tree-all exact CLICOLOR_FORCE=1 list --all
compare_real_database_colors list-color-parent-deps exact CLICOLOR_FORCE=1 list --parent test-cl --all --deps=all
compare_real_database_colors list-color-flat exact CLICOLOR_FORCE=1 list --parent test-cl --all --flat
compare_real_database_colors list-color-long exact CLICOLOR_FORCE=1 list --parent test-cl --all --long --flat
compare_real_database_colors children-color exact CLICOLOR_FORCE=1 children test-cl
compare_real_database_colors list-color-force-zero exact CLICOLOR_FORCE=0 list --parent test-cl --all
compare_real_database_colors list-color-term-dumb exact "CLICOLOR_FORCE=1 TERM=dumb" list --parent test-cl --all
compare_real_database_colors list-color-term-xterm exact "CLICOLOR_FORCE=1 TERM=xterm" list --parent test-cl --all --flat
compare_real_database_colors list-color-no-color-flag-false exact CLICOLOR_FORCE=1 list --parent test-cl --all --no-color=false
compare_real_database_colors list-color-no-color-flag-bad exact CLICOLOR_FORCE=1 list --parent test-cl --all --no-color=maybe
# ready's pretty and plain views, its empty and truncated notes, and query's compact view share the styles.
compare_real_database_colors ready-color exact CLICOLOR_FORCE=1 ready
compare_real_database_colors ready-color-plain exact CLICOLOR_FORCE=1 ready --plain
compare_real_database_colors ready-color-limit exact CLICOLOR_FORCE=1 ready --limit 1
compare_real_database_colors ready-color-empty exact CLICOLOR_FORCE=1 ready --assignee nobody
compare_real_database_colors query-color exact CLICOLOR_FORCE=1 query --all assignee=fixture
# Colors stay off: stdout is no terminal, NO_COLOR, CLICOLOR=0 or BD_GIT_HOOK=1 wins over CLICOLOR_FORCE,
# --no-color, agent mode and JSON print no style, and .beads/.env loads after the decision.
compare_real_database_colors list-color-pipe exact "" list --parent test-cl --all
compare_real_database_colors list-color-no-color exact "CLICOLOR_FORCE=1 NO_COLOR=1" list --parent test-cl --all
compare_real_database_colors list-color-clicolor-zero exact "CLICOLOR_FORCE=1 CLICOLOR=0" list --parent test-cl --all --flat
compare_real_database_colors list-color-git-hook exact "CLICOLOR_FORCE=1 BD_GIT_HOOK=1" list --parent test-cl --all
compare_real_database_colors list-color-no-color-flag exact CLICOLOR_FORCE=1 list --parent test-cl --all --long --flat --no-color
compare_real_database_colors list-color-agent-flat exact "CLICOLOR_FORCE=1 CLAUDE_CODE=1" list --parent test-cl --all --flat
compare_real_database_colors list-color-json exact CLICOLOR_FORCE=1 list --parent test-cl --all --json
real_database_setup=write_color_dotenv
compare_real_database_colors list-color-dotenv-force exact "" list --parent test-cl --all
real_database_setup=""
# show styles its header, metadata notes, bold headings and dependency lines: a closed dependency is
# muted without its badge, and another one has its ID in its status's style. The --short, --children,
# --refs and --thread views, the separator between issues and the long sections are styled too. The
# Markdown text is the renderer's own. The last two cases keep colors off.
compare_real_database_colors show-color-epic exact CLICOLOR_FORCE=1 show test-cl
compare_real_database_colors show-color-many exact CLICOLOR_FORCE=1 show test-cl-p0 test-cl-closed test-cl-waiting test-cl-deferred test-cl-hooked test-cl-pinned test-cl-p1 test-cl-blocked
compare_real_database_colors show-color-closed-epic exact CLICOLOR_FORCE=1 show test-cl-closed-epic --long
compare_real_database_colors show-color-seed exact CLICOLOR_FORCE=1 show "$real_database_issue_id" --long
compare_real_database_colors show-color-short exact CLICOLOR_FORCE=1 show --short test-cl test-cl-p0 test-cl-closed test-cl-closed-epic test-cl-deferred test-cl-pinned test-cl-hooked
compare_real_database_colors show-color-children exact CLICOLOR_FORCE=1 show --children test-cl
compare_real_database_colors show-color-children-short exact CLICOLOR_FORCE=1 show --children --short test-cl
compare_real_database_colors show-color-children-none exact CLICOLOR_FORCE=1 show --children test-cl-p0
compare_real_database_colors show-color-refs exact CLICOLOR_FORCE=1 show --refs test-cl
# Upstream prints one block per issue from a Go map (cmd/bd/show_refs.go:54), so compare the lines as a multiset.
compare_real_database_colors show-color-refs-blocker show-grouped-multi CLICOLOR_FORCE=1 show --refs test-cl-p0 test-cl-waiting
compare_real_database_colors show-color-thread exact CLICOLOR_FORCE=1 show --thread test-msg-reply
compare_real_database_colors show-color-pipe exact "" show test-cl test-cl-closed
compare_real_database_colors show-color-no-color-flag exact CLICOLOR_FORCE=1 show test-cl --no-color
# The Markdown renderer keeps OSC 8 hyperlinks only when upstream's ShouldUseHyperlinks allows them,
# which it decides apart from colors: BD_GIT_HOOK=1, NO_COLOR, CLICOLOR=0 and TERM=dumb forbid them,
# then a FORCE_HYPERLINK other than 0 forces them, and on a pipe nothing else allows them. With
# hyperlinks and no colors, the renderer's plain style keeps its link escapes.
color_list_extra_records='{"id":"test-cl-link","title":"Linked task","description":"See [the docs](https://example.com/docs), <https://example.org> and **bold** a<b>c.","status":"open","priority":2,"issue_type":"task","created_at":"2026-08-20T12:00:00Z","updated_at":"2026-08-21T13:00:00Z"}'
compare_real_database_colors show-color-hyperlink-forced exact "CLICOLOR_FORCE=1 FORCE_HYPERLINK=1" show test-cl-link
compare_real_database_colors show-hyperlink-forced-plain exact FORCE_HYPERLINK=yes show test-cl-link
compare_real_database_colors show-color-hyperlink-zero exact "CLICOLOR_FORCE=1 FORCE_HYPERLINK=0" show test-cl-link
compare_real_database_colors show-color-hyperlink-pipe exact "CLICOLOR_FORCE=1 TERM_PROGRAM=vscode" show test-cl-link
compare_real_database_colors show-hyperlink-no-color exact "FORCE_HYPERLINK=1 NO_COLOR=1" show test-cl-link
compare_real_database_colors show-hyperlink-clicolor-zero exact "FORCE_HYPERLINK=1 CLICOLOR=0" show test-cl-link
compare_real_database_colors show-hyperlink-term-dumb exact "FORCE_HYPERLINK=1 TERM=dumb" show test-cl-link
compare_real_database_colors show-hyperlink-git-hook exact "FORCE_HYPERLINK=1 BD_GIT_HOOK=1" show test-cl-link
color_list_extra_records=""
# dep list prints each related ID in its status style and an accented heading over each anchor's
# edges; dep tree accents its heading, mutes edge types and repeated nodes, warns at the depth limit
# and prints the root's [READY] or [BLOCKED] in bold pass or fail, also with colors off; dep cycles
# marks its result and mutes a member without a record.
compare_real_database_colors dep-list-color-up exact CLICOLOR_FORCE=1 dep list test-cl --direction up
compare_real_database_colors dep-list-color-down exact CLICOLOR_FORCE=1 dep list test-cl-waiting
compare_real_database_colors dep-list-color-batch exact CLICOLOR_FORCE=1 dep list test-cl-waiting test-cl test-cl-outside
compare_real_database_colors dep-tree-color-blocked exact CLICOLOR_FORCE=1 dep tree test-cl-waiting
compare_real_database_colors dep-tree-color-up exact CLICOLOR_FORCE=1 dep tree test-cl --direction up
compare_real_database_colors dep-tree-color-depth exact CLICOLOR_FORCE=1 dep tree test-cl-waiting --max-depth 1
compare_real_database_colors dep-tree-color-both exact CLICOLOR_FORCE=1 dep tree test-cl-p0 --direction both
compare_real_database_colors dep-tree-color-empty exact CLICOLOR_FORCE=1 dep tree test-cl-closed --direction up
compare_real_database_colors dep-cycles-color-none exact CLICOLOR_FORCE=1 dep cycles
# One cycle between two colour records, and one through a member without a record (one statement a line).
color_dependency_row="INSERT INTO dependencies (id, issue_id, depends_on_issue_id, type, created_at, created_by) VALUES"
color_cycle_sql="SET FOREIGN_KEY_CHECKS = 0
$color_dependency_row ('fixture-colour-cycle', 'test-cl-p0', 'test-cl-waiting', 'blocks', '2026-08-21 10:00:00', 'fixture')
$color_dependency_row ('fixture-colour-ghost-1', 'test-cl-p1', 'test-ghost', 'blocks', '2026-08-21 10:00:00', 'fixture')
$color_dependency_row ('fixture-colour-ghost-2', 'test-ghost', 'test-cl-p1', 'blocks', '2026-08-21 10:00:00', 'fixture')"
real_database_extra_sql="$color_cycle_sql"
compare_real_database_colors dep-cycles-color exact CLICOLOR_FORCE=1 dep cycles
compare_real_database_colors dep-cycles-color-pipe exact "" dep cycles
real_database_extra_sql=""
compare_real_database_colors dep-list-color-pipe exact "" dep list test-cl-waiting test-cl
compare_real_database_colors dep-tree-color-pipe exact "" dep tree test-cl --direction up
# The --explain, --mol and --gated views of ready mark their headings and style each priority and
# ID (blocked follows its own cases below). --gated renders an empty text in the warning or accent style, which still prints
# the style's escape sequences. Upstream lists a molecule's ready steps in Go map order, so only the
# seed molecule, with one ready step, is compared.
compare_real_database_colors ready-color-explain exact CLICOLOR_FORCE=1 ready --explain
real_database_extra_sql="UPDATE issues SET status = 'closed', closed_at = '2026-08-21 13:00:00' WHERE status IN ('open', 'in_progress')"
compare_real_database_colors ready-color-explain-none exact CLICOLOR_FORCE=1 ready --explain
real_database_extra_sql=""
compare_real_database_colors ready-color-mol exact CLICOLOR_FORCE=1 ready --mol "$real_database_molecule_id"
compare_real_database_colors ready-color-mol-none exact CLICOLOR_FORCE=1 ready --mol test-cl-closed-epic
compare_real_database_colors ready-color-gated exact CLICOLOR_FORCE=1 ready --gated
real_database_extra_sql="UPDATE issues SET status = 'open', closed_at = NULL, updated_at = updated_at WHERE issue_type = 'gate'"
compare_real_database_colors ready-color-gated-none exact CLICOLOR_FORCE=1 ready --gated
real_database_extra_sql=""
compare_real_database_colors ready-color-explain-pipe exact "" ready --explain
# ready --explain lists what upstream's GetBlockedIssues lists (cmd/bd/ready.go:464,
# internal/storage/issueops/blocked.go:240-370): the issues whose stored is_blocked flag is set,
# not the issues that have an open blocker. An issue with the flag and no open blocker names its
# parent; an open blocker without the flag lists nothing (one statement a line).
real_database_extra_sql="UPDATE issues SET is_blocked = 1, updated_at = updated_at WHERE id = 'test-cl-p1'
UPDATE issues SET is_blocked = 0, updated_at = updated_at WHERE id = 'test-cl-waiting'"
compare_real_database_colors ready-explain-stored-flag exact "" ready --explain
compare_real_database_colors ready-explain-stored-flag-json exact "" ready --explain --json
real_database_extra_sql=""
# Its cycles are upstream's DetectCycles walk (internal/storage/issueops/cycles.go:14-77) over the
# blocking edges of both dependency tables, which leaves out a member without a record. The walk
# starts from each node in Go map order, so a cycle of two records can start at either one; these
# cases use one cycle through a member without a record, which cannot differ.
real_database_extra_sql="SET FOREIGN_KEY_CHECKS = 0
$color_dependency_row ('fixture-colour-ghost-1', 'test-cl-p1', 'test-ghost', 'blocks', '2026-08-21 10:00:00', 'fixture')
$color_dependency_row ('fixture-colour-ghost-2', 'test-ghost', 'test-cl-p1', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database_colors ready-explain-cycle-ghost exact "" ready --explain
compare_real_database_colors ready-explain-cycle-ghost-json exact "" ready --explain --json
compare_real_database_colors ready-color-explain-cycle exact CLICOLOR_FORCE=1 ready --explain
real_database_extra_sql=""
# graph accents its heading marks and layer headings, styles each status icon, mutes each ID line,
# prints a title that is not open in its status style and the box view's counts in the blocked and
# muted styles. graph check marks its result. The cycle case uses one cycle through a member without
# a record, so the cycle order cannot differ.
compare_real_database_colors graph-color-visual exact CLICOLOR_FORCE=1 graph test-cl
compare_real_database_colors graph-color-box exact CLICOLOR_FORCE=1 graph test-cl --box
compare_real_database_colors graph-color-compact exact CLICOLOR_FORCE=1 graph test-cl --compact
compare_real_database_colors graph-color-open exact CLICOLOR_FORCE=1 graph test-cl --open
compare_real_database_colors graph-color-blockers-box exact CLICOLOR_FORCE=1 graph test-cl-waiting --box
compare_real_database_colors graph-color-blockers-visual exact CLICOLOR_FORCE=1 graph test-cl-waiting
compare_real_database_colors graph-check-color exact CLICOLOR_FORCE=1 graph check
real_database_extra_sql="SET FOREIGN_KEY_CHECKS = 0
$color_dependency_row ('fixture-colour-ghost-1', 'test-cl-p1', 'test-ghost', 'blocks', '2026-08-21 10:00:00', 'fixture')
$color_dependency_row ('fixture-colour-ghost-2', 'test-ghost', 'test-cl-p1', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database_colors graph-check-color-cycles exact CLICOLOR_FORCE=1 graph check
compare_real_database_colors graph-check-color-pipe exact "" graph check
real_database_extra_sql=""
compare_real_database_colors graph-color-pipe exact "" graph test-cl --box
compare_real_database_colors graph-color-compact-pipe exact "" graph test-cl --compact
# history mutes each commit's hash and date, or each event's time; label list and list-all, stale,
# orphans, status (also stats), statuses and ping mark their headings and results and style each
# priority, ID, status and count as upstream does. The history cases leave out the colour records:
# importing them adds a commit on each side, whose hash and date differ.
real_database_extra_env=(NO_COLOR= CLICOLOR_FORCE=1)
compare_real_database history-color exact history "$real_database_issue_id" --limit 2
compare_real_database history-color-events exact history "$real_database_issue_id" --events
compare_real_database history-color-none exact history test-nope
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database_colors label-list-color exact CLICOLOR_FORCE=1 label list test-cl-p0
compare_real_database_colors label-list-color-none exact CLICOLOR_FORCE=1 label list "$real_database_bug_id"
compare_real_database_colors label-list-all-color exact CLICOLOR_FORCE=1 label list-all
compare_real_database_colors stale-color exact CLICOLOR_FORCE=1 stale --days 1
compare_real_database_colors stale-color-none exact CLICOLOR_FORCE=1 stale --days 100000
compare_real_database_colors orphans-color exact CLICOLOR_FORCE=1 orphans --details
compare_real_database_colors orphans-color-none exact CLICOLOR_FORCE=1 orphans --label nothing
compare_real_database_colors status-color exact CLICOLOR_FORCE=1 status
compare_real_database_colors status-color-no-blocked exact CLICOLOR_FORCE=1 status --no-blocked
compare_real_database_colors stats-color exact CLICOLOR_FORCE=1 stats
compare_real_database_colors statuses-color exact CLICOLOR_FORCE=1 statuses
real_database_extra_sql="$custom_statuses_sql"
compare_real_database_colors statuses-color-custom exact CLICOLOR_FORCE=1 statuses
real_database_extra_sql=""
compare_real_database_colors ping-color ping-human CLICOLOR_FORCE=1 ping
compare_real_database_colors stale-color-pipe exact "" stale --days 1
compare_real_database_colors status-color-pipe exact "" status
# Upstream prints "📌 " before the ID of an issue with the pinned flag in the flat and long views of
# list (pinIndicator, cmd/bd/list_format.go:24-29), inside the closed style for a closed issue. The
# tree view, the agent view and the status icon of the pinned status print no such prefix.
pin_list_records="$(
	color_list_record test-cl-pin "Pinned flag task" open 1 task test-cl "" pinned
	color_list_record test-cl-pin-closed "Pinned flag closed bug" closed 2 bug test-cl "" pinned
	color_list_record test-cl-pin-waiting "Pinned waiting task" open 3 task test-cl test-cl-p0 pinned
)"
color_list_extra_records="$pin_list_records"
compare_real_database_colors list-pin-flat exact "" list --parent test-cl --all --flat
compare_real_database_colors list-pin-flat-color exact CLICOLOR_FORCE=1 list --parent test-cl --all --flat
compare_real_database_colors list-pin-long exact "" list --parent test-cl --all --long --flat
compare_real_database_colors list-pin-long-color exact CLICOLOR_FORCE=1 list --parent test-cl --all --long --flat
compare_real_database_colors list-pin-tree exact "" list --parent test-cl --all
compare_real_database_colors list-pin-tree-color exact CLICOLOR_FORCE=1 list --parent test-cl --all
compare_real_database_colors list-pin-agent-flat exact "CLICOLOR_FORCE=1 CLAUDE_CODE=1" list --parent test-cl --all --flat
color_list_extra_records=""
compare_real_database list-parent-gated-all-human exact list --parent "$real_database_gated_molecule_id" --all --include-gates
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
# blocked marks its heading and styles each priority and ID, also with colors on (see the color cases).
real_database_extra_sql="$distinct_created_sql"
compare_real_database_colors blocked-color exact CLICOLOR_FORCE=1 blocked
compare_real_database_colors blocked-color-parent exact CLICOLOR_FORCE=1 blocked --parent test-cl
compare_real_database_colors blocked-color-none exact CLICOLOR_FORCE=1 blocked --parent test-cl-p0
compare_real_database_colors blocked-color-pipe exact "" blocked
real_database_extra_sql=""
# dep tree walks parent-child chains (grandchild -> child -> epic), a molecule whose second step
# blocks on the first, and a gated step whose gate is closed. Cycles come from dep_cycle_sql.
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
compare_real_database_env dep-tree-max-rows-env-out-of-range exact BEADS_MAX_ROWS=99999999999999999999 dep tree test-missing
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
# The search for --all asks for one row more than the cap. A cap of 2147483647 must ask for
# LIMIT 2147483648; test/graph proves that arithmetic (SqlRowCap). It is not run here: Dolt
# reserves memory in proportion to the limit, so upstream bd itself needs about 1.8 GB and
# runs out of memory on CI runners.
compare_real_database_env graph-all-max-rows-env-plus-sign exact BEADS_MAX_ROWS=+1 graph --all --dot
compare_real_database graph-all-two-args exact graph --all "$real_database_epic_id" "$real_database_child_id"
compare_real_database graph-check-all-flag exact graph check --all
# An external:<project>:<id> row whose <id> names no issue in the graph: upstream looks the <id> up as
# resolveAndGetIssueWithRouting does (cmd/bd/graph.go:437-458, cmd/bd/routed.go:70-96). It first resolves
# the <id> in this database as it resolves a partial ID, so a full ID, an ID without the prefix or a
# unique abbreviation adds that issue to the graph, also a closed one, and an <id> that resolves to an
# issue already in the graph lists that issue twice. The rows of an added issue are not read. When no
# issue matches, upstream tries the routes.jsonl prefix routes and then contributor auto-routing,
# which asks for the user's role, and leaves the row out. An ambiguous <id> fails before the routes,
# so its row is left out without the role warning.
graph_external_ids_sql="$graph_external_row ('fixture-graph-ext-1', '$real_database_issue_id', 'external:other:$real_database_bug_id', 'blocks', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-2', '$real_database_issue_id', 'external:other:abcd1', 'blocks', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-3', '$real_database_issue_id', 'external:other:${real_database_labeled_relation_id#test-}', 'blocks', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-4', '$real_database_issue_id', 'external:other:abcd', 'blocks', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-5', '$real_database_issue_id', 'external:other:test-elsewhere', 'blocks', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-6', '$real_database_issue_id', 'external:other:$real_database_closed_id', 'relates-to', '2026-08-21 10:00:00', 'fixture')
$graph_external_row ('fixture-graph-ext-7', '$real_database_labeled_relation_id', 'external:other:test-elsewhere', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_real_database_sql graph-external-ids-json exact "$graph_external_ids_sql" graph "$real_database_issue_id" --json
compare_real_database_sql graph-external-ids-visual exact "$graph_external_ids_sql" graph "$real_database_issue_id"
compare_real_database_sql graph-external-ids-compact exact "$graph_external_ids_sql" graph "$real_database_issue_id" --compact
compare_real_database_sql graph-external-ids-box exact "$graph_external_ids_sql" graph "$real_database_issue_id" --box
compare_real_database_sql graph-external-ids-dot exact "$graph_external_ids_sql" graph "$real_database_issue_id" --dot
compare_real_database_sql graph-external-ids-html graph-html "$graph_external_ids_sql" graph "$real_database_issue_id" --html
compare_real_database_sql graph-external-ids-open-json graph-open-json "$graph_external_ids_sql" graph "$real_database_issue_id" --open --json
# The row cap counts the issue that is listed twice two times.
compare_real_database_sql graph-external-ids-max-rows exact "$graph_external_ids_sql" graph "$real_database_issue_id" --max-rows 5
compare_real_database_sql graph-all-external-ids-json exact "$graph_external_ids_sql" graph --all --json
compare_real_database_sql graph-all-external-ids-compact exact "$graph_external_ids_sql" graph --all --compact
compare_real_database_sql graph-all-external-ids-open-json exact "$graph_external_ids_sql" graph --all --open --json
compare_real_database_sql graph-check-external-ids exact "$graph_external_ids_sql" graph check
real_database_setup=remove_git_checkout
compare_real_database_sql graph-external-ids-role-warning exact "$graph_external_ids_sql" graph "$real_database_issue_id" --compact
compare_real_database_sql graph-all-external-ids-role-warning-json exact "$graph_external_ids_sql" graph --all --json
real_database_setup=""
# In --all, an added issue joins the group of the row's issue, and a later row to that issue is kept
# too. --open then leaves the added closed issue out of that group.
graph_all_external_sql="$graph_all_sql
$graph_external_row ('fixture-ga-3', 'test-ga-s6', 'external:other:test-ga-closed', 'blocks', '2026-08-21 10:00:00', 'fixture')"
compare_graph_all_external() {
	local name="$1" comparison="$2"
	shift 2
	real_database_extra_sql="$graph_all_external_sql"
	compare_real_database_import "$name" "$comparison" "$graph_all_records" "$@"
	real_database_extra_sql=""
}
compare_graph_all_external graph-all-external-closed-json exact graph --all --json
compare_graph_all_external graph-all-external-closed-visual exact graph --all
compare_graph_all_external graph-all-external-closed-open exact graph --all --open
compare_graph_all_external graph-all-external-closed-open-json exact graph --all --open --json
compare_graph_all_external graph-all-external-closed-html graph-html graph --all --html
# The prefix routes come from routes.jsonl in the workspace. Upstream takes the first route whose prefix
# is the <id> up to its first hyphen, and skips a route to ".". It follows the redirect of the route's
# workspace, and opens that workspace only when its metadata.json names a dolt_database; otherwise it
# goes on to auto-routing. Lines that are blank, comments or not a route object are skipped.
graph_route_sql="$graph_external_row ('fixture-graph-route-1', '$real_database_issue_id', 'external:other:other-f1', 'blocks', '2026-08-21 10:00:00', 'fixture')"
graph_routes=""
graph_rig_metadata=""
graph_rig_redirect=""
write_graph_routes() {
	printf '%s' "$graph_routes" >"$1/work/.beads/routes.jsonl"
	if [[ -n "$graph_rig_metadata" || -n "$graph_rig_redirect" ]]; then
		mkdir -p "$1/work/rig/.beads"
	fi
	if [[ -n "$graph_rig_metadata" ]]; then
		printf '%s\n' "$graph_rig_metadata" >"$1/work/rig/.beads/metadata.json"
	fi
	if [[ -n "$graph_rig_redirect" ]]; then
		printf '%s\n' "$graph_rig_redirect" >"$1/work/rig/.beads/redirect"
	fi
}
real_database_setup=write_graph_routes
graph_routes=$'# routes\n\nnot a route\n{"prefix":7,"path":"rig"}\n{"Prefix":"zzz-","path":"rig"}\n{"prefix":"other","path":"rig"}\n{"prefix":"other-","path":"."}\n{"prefix":"other-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"rig"}'
compare_real_database_sql graph-route-to-current-json exact "$graph_route_sql" graph "$real_database_issue_id" --json
graph_routes=$'{"prefix":"other-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded"}'
compare_real_database_sql graph-route-without-database exact "$graph_route_sql" graph "$real_database_issue_id" --compact
graph_rig_metadata='{"dolt_database":7}'
compare_real_database_sql graph-route-undecodable-metadata exact "$graph_route_sql" graph --all --compact
graph_rig_metadata=""
graph_rig_redirect="../missing/.beads"
compare_real_database_sql graph-route-broken-redirect exact "$graph_route_sql" graph "$real_database_issue_id" --compact
graph_rig_redirect=""
graph_routes=$'{"prefix":"other-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"rig"}'
real_database_setup=""
candidate_only_setup=write_graph_routes
expect_candidate_failure graph-route-other-repository-unported "" \
	"Error: loading graph: graph of an issue with a dependency on another repository is not available yet in this build" \
	"$graph_route_sql" graph "$real_database_issue_id"
expect_candidate_failure graph-all-route-other-repository-json-unported \
	'{"error":"loading all issues: graph of an issue with a dependency on another repository is not available yet in this build","schema_version":1}' "" \
	"$graph_route_sql" graph --all --json
candidate_only_setup=""
graph_routes=""
graph_rig_metadata=""
# Contributor auto-routing takes each routing setting from config.yaml or the environment, or else
# from the database. routing.mode auto, or contributor.auto_route true, sends a maintainer to
# routing.maintainer and a contributor to routing.contributor (or contributor.planning_repo);
# routing.default applies to both. Upstream opens the store there unless that is ".". Without
# beads.role, the origin and upstream remotes decide the role. A Git remote also turns on upstream's
# auto-backup after the command, which writes .beads/backup, so the cases with a remote turn it off.
real_database_extra_sql="$graph_route_sql"
real_database_extra_config=$'routing:\n  mode: auto\n  contributor: ../planning'
compare_real_database graph-auto-route-maintainer exact graph "$real_database_issue_id" --compact
real_database_extra_config=$'routing:\n  default: "."'
compare_real_database graph-auto-route-default-current exact graph --all --compact
real_database_extra_config=$'contributor:\n  auto_route: true\n  planning_repo: ../planning'
real_database_setup=remove_git_checkout
compare_real_database graph-auto-route-without-remote exact graph "$real_database_issue_id" --compact
graph_route_remote_setup() {
	printf 'backup:\n  enabled: false\n' >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config --unset beads.role
	git -C "$1/work" remote add origin git@example.invalid:team/project.git
	git -C "$1/work" remote add upstream ssh://git@example.invalid/team/project
}
real_database_setup=graph_route_remote_setup
compare_real_database graph-auto-route-ssh-remote exact graph "$real_database_issue_id" --compact
real_database_setup=""
real_database_extra_config=""
real_database_extra_sql=""
graph_role_warning=$'warning: beads.role not configured (GH#2950).\n  Fix: git config beads.role maintainer\n  Or:  git config beads.role contributor'
graph_route_contributor_setup() {
	printf 'contributor:\n  auto_route: true\n  planning_repo: ../planning\nbackup:\n  enabled: false\n' >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config --unset beads.role
	git -C "$1/work" remote add origin https://example.invalid/team/project.git
}
candidate_only_setup=graph_route_contributor_setup
expect_candidate_failure graph-auto-route-contributor-unported "" \
	"$graph_role_warning"$'\n'"Error: loading graph: graph of an issue with a dependency on another repository is not available yet in this build" \
	"$graph_route_sql" graph "$real_database_issue_id"
candidate_only_setup=""
expect_candidate_failure graph-auto-route-database-default-unported \
	'{"error":"loading all issues: graph of an issue with a dependency on another repository is not available yet in this build","schema_version":1}' "" \
	"$graph_route_sql
INSERT INTO config (\`key\`, value) VALUES ('routing.default', '../planning')" graph --all --json
# show (also --short, --refs, --children, --thread and --watch), comments, dep list and dep tree look
# an ID up as graph does (resolveAndGetIssueWithRouting, cmd/bd/routed.go:70-96). An ID that this
# database does not hold tries the routes.jsonl prefix routes and then contributor auto-routing.
# Where upstream would open another repository for the lookup, bdhx refuses the whole command before
# it prints an issue. A route whose path names this workspace again (".", "./" or "../work"), or a
# routed workspace without a dolt_database, reads no other store, so upstream reports the same miss.
routed_lookup_refusal="of an issue in another repository is not available yet in this build"
real_database_setup=write_graph_routes
graph_routes=$'{"prefix":"other-","path":"."}\n{"prefix":"other-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"rig"}'
compare_real_database routed-show-route-to-current exact show other-f1
graph_routes=$'{"prefix":"other-","path":"./"}\n'
compare_real_database routed-show-route-to-same-workspace-json exact show other-f1 --json
graph_routes=$'{"prefix":"other-","path":"../work"}\n'
compare_real_database routed-dep-tree-route-to-same-workspace exact dep tree other-f1
graph_routes=$'{"prefix":"other-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded"}'
compare_real_database routed-comments-route-without-database exact comments other-f1
# A route for this workspace's own prefix: an ID that this database holds is never routed.
graph_routes=$'{"prefix":"test-","path":"rig"}\n'
graph_rig_metadata='{"backend":"dolt","dolt_mode":"embedded","dolt_database":"rig"}'
compare_real_database routed-show-found-locally exact show "$real_database_issue_id" --short
compare_real_database routed-dep-list-found-locally-json exact dep list "$real_database_issue_id" --json
real_database_setup=""
candidate_only_setup=write_graph_routes
expect_candidate_failure routed-show-own-prefix-unported "" "Error: show $routed_lookup_refusal" "" show test-missing
graph_routes=$'{"prefix":"other-","path":"rig"}\n'
expect_candidate_failure routed-show-prefix-route-json-unported \
	"{\"error\":\"show $routed_lookup_refusal\",\"schema_version\":1}" "" "" show other-f1 --json
expect_candidate_failure routed-show-batch-unported "" "Error: show $routed_lookup_refusal" "" \
	show "$real_database_issue_id" other-f1
expect_candidate_failure routed-show-batch-after-miss-unported "" \
	$'Error fetching test-missing: no issue found matching "test-missing"\n'"Error: show $routed_lookup_refusal" "" \
	show test-missing other-f1
expect_candidate_failure routed-show-short-unported "" "Error: show $routed_lookup_refusal" "" show other-f1 --short
expect_candidate_failure routed-show-refs-unported "" "Error: show $routed_lookup_refusal" "" show --refs other-f1
expect_candidate_failure routed-show-children-json-unported \
	"{\"error\":\"show $routed_lookup_refusal\",\"schema_version\":1}" "" "" show --children other-f1 --json
expect_candidate_failure routed-show-thread-unported "" "Error: show $routed_lookup_refusal" "" show --thread other-f1
expect_candidate_failure routed-show-watch-unported "" "Error: show $routed_lookup_refusal" "" show --watch other-f1
expect_candidate_failure routed-comments-unported "" "Error: comments $routed_lookup_refusal" "" comments other-f1
expect_candidate_failure routed-comments-json-unported \
	"{\"error\":\"comments $routed_lookup_refusal\",\"schema_version\":1}" "" "" comments other-f1 --json
expect_candidate_failure routed-dep-list-unported "" "Error: dep list $routed_lookup_refusal" "" dep list other-f1
expect_candidate_failure routed-dep-list-batch-json-unported \
	"{\"error\":\"dep list $routed_lookup_refusal\",\"schema_version\":1}" "" "" \
	dep list "$real_database_issue_id" other-f1 --json
expect_candidate_failure routed-dep-tree-json-unported \
	"{\"error\":\"dep tree $routed_lookup_refusal\",\"schema_version\":1}" "" "" dep tree other-f1 --json
candidate_only_setup=""
graph_routes=""
graph_rig_metadata=""
# list, ready and children read the store that contributor auto-routing selects
# (openRoutedReadStore, cmd/bd/routing_read.go:158-175), and print a note on stderr unless --quiet.
# A lookup that misses tries the same store. Where that store is another repository, bdhx refuses;
# upstream's --gated, --mol and --explain views of ready, and an ID that this database holds, read no
# other store. The planning repository here does not exist: upstream would fail to open it.
routed_list_refusal="of a planning store in another repository is not available yet in this build"
routed_contributor_elsewhere() {
	printf 'routing:\n  mode: auto\n  contributor: ../planning\n' >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config beads.role contributor
}
real_database_setup=routed_contributor_elsewhere
compare_real_database routed-auto-show-found-locally exact show "$real_database_issue_id"
compare_real_database routed-auto-ready-explain exact ready --explain
compare_real_database routed-auto-ready-molecule exact ready --mol "$real_database_molecule_id"
compare_real_database routed-auto-count exact count
real_database_setup=""
candidate_only_setup=routed_contributor_elsewhere
expect_candidate_failure routed-auto-list-unported "" "Error: list $routed_list_refusal" "" list
expect_candidate_failure routed-auto-list-json-unported \
	"{\"error\":\"list $routed_list_refusal\",\"schema_version\":1}" "" "" list --json
expect_candidate_failure routed-auto-ready-unported "" "Error: ready $routed_list_refusal" "" ready
expect_candidate_failure routed-auto-ready-json-unported \
	"{\"error\":\"ready $routed_list_refusal\",\"schema_version\":1}" "" "" ready --json
expect_candidate_failure routed-auto-children-unported "" "Error: children $routed_list_refusal" "" \
	children "$real_database_epic_id"
expect_candidate_failure routed-auto-show-missing-unported "" "Error: show $routed_lookup_refusal" "" show test-missing
expect_candidate_failure routed-auto-show-refs-unported "" "Error: show $routed_lookup_refusal" "" show --refs test-missing
expect_candidate_failure routed-auto-show-watch-unported "" "Error: show $routed_lookup_refusal" "" show --watch test-missing
expect_candidate_failure routed-auto-comments-json-unported \
	"{\"error\":\"comments $routed_lookup_refusal\",\"schema_version\":1}" "" "" comments test-missing --json
expect_candidate_failure routed-auto-dep-list-unported "" "Error: dep list $routed_lookup_refusal" "" dep list test-missing
expect_candidate_failure routed-auto-dep-tree-unported "" "Error: dep tree $routed_lookup_refusal" "" dep tree test-missing
# Without beads.role, an https origin makes the user a contributor, after the role warning.
candidate_only_setup=graph_route_contributor_setup
expect_candidate_failure routed-auto-role-warning-list-unported "" \
	"$graph_role_warning"$'\n'"Error: list $routed_list_refusal" "" list
expect_candidate_failure routed-auto-role-warning-show-unported "" \
	"$graph_role_warning"$'\n'"Error: show $routed_lookup_refusal" "" show test-missing
# A maintainer goes to routing.maintainer; routing.default applies to both roles, also from the database.
routed_maintainer_elsewhere() {
	printf 'routing:\n  mode: auto\n  maintainer: ../planning\n' >>"$1/work/.beads/config.yaml"
}
candidate_only_setup=routed_maintainer_elsewhere
expect_candidate_failure routed-auto-maintainer-ready-unported "" "Error: ready $routed_list_refusal" "" ready
candidate_only_setup=""
expect_candidate_failure routed-auto-database-default-list-json-unported \
	"{\"error\":\"list $routed_list_refusal\",\"schema_version\":1}" "" \
	"INSERT INTO config (\`key\`, value) VALUES ('routing.default', '../planning')" list --json
# A planning repository that is this workspace again, by a relative or absolute path or through a
# symbolic link: upstream opens this store a second time, prints its note with the number of issues
# in this workspace, and reads the same issues. A lookup that misses misses again, and graph leaves
# the external dependency out.
routed_contributor_current() {
	printf 'routing:\n  mode: auto\n  contributor: ../work\n' >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config beads.role contributor
}
real_database_setup=routed_contributor_current
compare_real_database routed-auto-current-list exact list
compare_real_database routed-auto-current-ready-json exact ready --json
compare_real_database routed-auto-current-children exact children "$real_database_epic_id"
compare_real_database routed-auto-current-list-quiet exact list --quiet
compare_real_database routed-auto-current-show-missing exact show test-missing
compare_real_database_sql routed-auto-current-graph exact "$graph_route_sql" graph "$real_database_issue_id" --compact
routed_contributor_absolute() {
	printf 'contributor:\n  auto_route: true\n  planning_repo: %s\n' "$1/work" >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config beads.role contributor
}
real_database_setup=routed_contributor_absolute
compare_real_database routed-auto-current-absolute-ready exact ready
routed_contributor_link() {
	ln -s work "$1/link"
	printf 'routing:\n  mode: auto\n  contributor: ../link\n' >>"$1/work/.beads/config.yaml"
	git -C "$1/work" config beads.role contributor
}
real_database_setup=routed_contributor_link
compare_real_database routed-auto-current-link-list-json exact list --json
routed_maintainer_current() {
	printf 'routing:\n  mode: auto\n  maintainer: ../work\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=routed_maintainer_current
compare_real_database routed-auto-current-maintainer-ready exact ready
real_database_setup=""
compare_real_database_sql routed-auto-current-database-default-list exact \
	"INSERT INTO config (\`key\`, value) VALUES ('routing.default', '../work/')" list
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
# The command body checks --skip-labels, --pinned, --parent, --brief, --deps, --sort and --offset in
# that order, and reads BEADS_MAX_ROWS only when they pass. Cobra's own errors and --help come first.
compare_real_database list-pinned-conflict exact list --pinned --no-pinned
compare_real_database list-pinned-conflict-before-sort exact list --sort bogus --pinned --no-pinned
compare_real_database list-pinned-conflict-before-offset-json exact list --offset -1 --pinned --no-pinned --json
compare_real_database list-skip-labels-before-pinned exact list --pinned --no-pinned --skip-labels --label parity
compare_real_database list-invalid-sort exact list --sort bogus
compare_real_database list-invalid-sort-before-offset exact list --offset -1 --sort bogus
compare_real_database list-negative-offset-sort-id exact list --sort id --offset -1
compare_real_database list-invalid-deps-json exact list --deps=bogus --json
compare_real_database list-invalid-sort-unknown-flag exact list --sort bogus --days 3
compare_real_database list-pinned-conflict-help exact list --pinned --no-pinned --help
compare_real_database_env list-pinned-conflict-max-rows-malformed exact BEADS_MAX_ROWS=bogus list --pinned --no-pinned
# The full order: --skip-labels, --priority, --priority-min, --priority-max, --pinned, --parent,
# --mol-type, --wisp-type, the date filters (in a fixed order), --metadata-field, --has-metadata-key,
# the --brief rules, --deps, --sort, --offset, then --max-rows. Only the last value of a flag counts.
compare_real_database list-bad-priority exact list --priority bogus
compare_real_database list-bad-priority-json exact list --priority high --json
compare_real_database list-priority-empty exact list --priority ''
compare_real_database list-priority-trailing-text-json exact list --priority 1x --json
compare_real_database list-priority-padded-json exact list --priority ' P1 ' --json
compare_real_database list-priority-signed-json exact list --priority +1 --json
compare_real_database list-bad-priority-min exact list --priority-min 5
compare_real_database list-bad-priority-max-json exact list --priority-max -1 --json
compare_real_database list-skip-labels-before-priority exact list --priority bogus --skip-labels --label parity
compare_real_database list-priority-before-priority-min exact list --priority-min bogus --priority bogus
compare_real_database list-priority-max-before-pinned exact list --pinned --no-pinned --priority-max bogus
compare_real_database list-parent-before-mol-type exact list --mol-type bogus --parent x --no-parent
compare_real_database list-mol-type-before-wisp-type exact list --wisp-type bogus --mol-type bogus
compare_real_database list-mol-type-empty-json exact list --mol-type '' --json
compare_real_database list-mol-type-last-value-json exact list --mol-type bogus --mol-type swarm --json
compare_real_database list-wisp-type-before-date exact list --created-after bogus --wisp-type bogus
compare_real_database list-invalid-wisp-type-json exact list --wisp-type invalid --json
compare_real_database list-dates-in-order exact list --due-before bogus --defer-after bogus --closed-before bogus
compare_real_database list-date-last-value-json exact list --created-after bogus --created-after 2000-01-01 --json
compare_real_database list-date-before-metadata exact list --metadata-field bad --updated-before bogus
compare_real_database list-invalid-metadata-syntax-json exact list --metadata-field missing-equals --json
compare_real_database list-invalid-metadata-key-json exact list --metadata-field 'bad$key=value' --json
compare_real_database list-metadata-fields-in-order exact list --metadata-field team=port --metadata-field 'bad$key=x' --metadata-field bad
compare_real_database list-metadata-field-before-has-metadata-key exact list --has-metadata-key 1bad --metadata-field bad
compare_real_database list-invalid-has-metadata-key-json exact list --has-metadata-key 'bad$key' --json
compare_real_database list-has-metadata-key-before-brief exact list --brief --watch --has-metadata-key 1bad
compare_real_database list-brief-format exact list --brief --format '{{.ID}}'
compare_real_database list-brief-parent exact list --brief --parent "$real_database_epic_id"
compare_real_database list-brief-parent-json exact list --brief --parent "$real_database_epic_id" --json
compare_real_database list-brief-watch-before-format exact list --brief --format '{{.ID}}' --watch
compare_real_database list-brief-format-before-deps exact list --brief --format '{{.ID}}' --deps
compare_real_database list-negative-max-rows exact list --max-rows -1
compare_real_database list-negative-max-rows-json exact list --max-rows -1 --json
compare_real_database list-offset-before-negative-max-rows exact list --max-rows -1 --offset -1
compare_real_database list-sort-before-negative-max-rows-json exact list --max-rows -1 --sort bogus --json
compare_real_database list-bad-priority-unknown-flag exact list --priority bogus --days 3
compare_real_database list-bad-mol-type-bad-boolean exact list --mol-type bogus --all=maybe
compare_real_database list-bad-created-after-help exact list --created-after bogus --help
compare_real_database list-negative-max-rows-bad-boolean exact list --max-rows -1 --pinned=maybe
compare_real_database_env list-negative-max-rows-max-rows-malformed exact BEADS_MAX_ROWS=bogus list --max-rows -1
compare_real_database_env list-bad-mol-type-max-rows-malformed exact BEADS_MAX_ROWS=bogus list --mol-type bogus
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
# Upstream renders a Go template with a map of five Go values: IssueID and DependsOnID (string),
# Type (types.DependencyType), Issue (*types.Issue) and Dependency (*types.Dependency). printf, eq
# and len see those Go types, a missing key prints <no value>, and a missing field of Issue fails.
# --json wins before upstream parses the template. dot and digraph are upstream's built-in formats.
compare_real_database list-format-template-fields exact list \
	'--format={{printf "%-14s" .IssueID}}|{{.DependsOnID}}|{{printf "%q" .Type}}|{{eq .Type "blocks"}}|{{.Issue.Title}}|{{.Issue.Status}}|P{{.Issue.Priority}}|{{.Issue.IssueType}}|{{.Dependency.IssueID}}|{{.Issue.IsCompound}}|{{len .}}|{{.Missing}}' \
	--limit 0
compare_real_database list-format-template-bad-field exact list '--format={{.Issue.Bogus}}' --limit 0
compare_real_database list-format-template-empty exact list '--format={{.IssueID}}' --status deferred
compare_real_database list-format-digraph-empty exact list --format digraph --status deferred
compare_real_database list-format-dot-empty exact list --format dot --status deferred
compare_real_database list-format-dot-limit exact list --format dot --limit 3
compare_real_database list-format-invalid-template-json exact list '--format={{.IssueID' --json --limit 2
# Upstream prints each edge's line as soon as it renders, so a template that fails on a later edge
# leaves the lines of the edges before it on stdout. The P3 issue's single label has no index 1.
compare_real_database list-format-template-later-error exact list \
	'--format={{.IssueID}} {{.DependsOnID}}{{if eq .Issue.Priority 3}} {{index .Issue.Labels 1}}{{end}}' --limit 0
compare_real_database list-format-template-first-error exact list '--format={{.IssueID}} {{index .Issue.Labels 9}}' --limit 0
# bdhx renders a template itself when each use of the data agrees with upstream's Go values: every
# types.Issue and types.Dependency field that it gives, printf's verbs for each kind, comparisons,
# and, or, not, len, index, range, with, variables and trim markers. The imported pair adds an edge
# whose issue and dependency fill the rarer fields; --all adds closed issues and --include-infra
# the messages and their replies-to edges.
real_database_extra_import="$(printf '%s\n' \
	'{"id":"test-rich-b","title":"Rich target","status":"open","priority":2,"issue_type":"task","created_at":"2026-08-21T10:00:00Z","updated_at":"2026-08-21T10:00:00Z"}' \
	'{"id":"test-rich-a","title":"Rich source","description":"Line one\nLine two","notes":"Rich notes","status":"in_progress","priority":1,"issue_type":"feature","assignee":"alice","owner":"owner@example.invalid","created_by":"creator","spec_id":"spec-rich","wisp_type":"ping","mol_type":"patrol","work_type":"open_competition","pinned":true,"sender":"bob","await_type":"timer","await_id":"t-1","waiters":["w1@example.invalid","w2@example.invalid"],"event_kind":"patrol.muted","actor":"agent://a","target":"test-rich-b","payload":"{\"k\":1}","source_system":"github","labels":["zeta","alpha"],"created_at":"2026-08-21T11:00:00Z","updated_at":"2026-08-21T12:30:00Z","dependencies":[{"issue_id":"test-rich-a","depends_on_id":"test-rich-b","type":"blocks","created_at":"2026-08-21T11:30:00Z","created_by":"linker","metadata":"{\"weight\":2}","thread_id":"thread-9"}]}')"
list_format_issue_fields='{{.IssueID}}|{{.Issue.ID}}|{{.Issue.Title}}|{{.Issue.Description}}|{{.Issue.Design}}|{{.Issue.AcceptanceCriteria}}|{{.Issue.Notes}}|{{.Issue.SpecID}}|{{.Issue.Status}}|{{.Issue.Priority}}|{{.Issue.IssueType}}|{{.Issue.IsBlocked}}|{{.Issue.Assignee}}|{{.Issue.Owner}}|{{.Issue.CreatedAt}}|{{.Issue.CreatedBy}}|{{.Issue.UpdatedAt}}|{{.Issue.CloseReason}}|{{.Issue.ClosedBySession}}|{{.Issue.LeaseGrantedNode}}|{{.Issue.SourceSystem}}|{{.Issue.CompactionLevel}}|{{.Issue.OriginalSize}}|{{.Issue.Labels}}|{{.Issue.Sender}}|{{.Issue.Ephemeral}}|{{.Issue.NoHistory}}|{{.Issue.WispType}}|{{.Issue.StorageClass}}|{{.Issue.Pinned}}|{{.Issue.IsTemplate}}|{{.Issue.AwaitType}}|{{.Issue.AwaitID}}|{{.Issue.Waiters}}|{{.Issue.SourceFormula}}|{{.Issue.SourceLocation}}|{{.Issue.MolType}}|{{.Issue.WorkType}}|{{.Issue.EventKind}}|{{.Issue.Actor}}|{{.Issue.Target}}|{{.Issue.Payload}}|{{.Issue.IsCompound}}'
list_format_dependency_fields='{{.IssueID}}|{{.DependsOnID}}|{{.Type}}|{{.Dependency.ID}}|{{.Dependency.IssueID}}|{{.Dependency.DependsOnID}}|{{.Dependency.Type}}|{{.Dependency.CreatedAt}}|{{.Dependency.CreatedBy}}|{{.Dependency.Metadata}}|{{.Dependency.ThreadID}}'
compare_real_database list-format-template-issue-fields exact list --all --limit 0 "--format=$list_format_issue_fields"
compare_real_database list-format-template-dependency-fields exact list --all --limit 0 "--format=$list_format_dependency_fields"
compare_real_database list-format-template-message-fields exact list --include-infra --all --limit 0 \
	"--format=$list_format_issue_fields/$list_format_dependency_fields"
compare_real_database list-format-template-printf exact list --all --limit 0 \
	'--format={{printf "%-14s|%5d|%t|%T %T %T %T" .IssueID .Issue.Priority .Issue.Pinned .IssueID .Issue.Priority .Issue.Labels .Issue.IsBlocked}}|{{printf "%q %x %X %8.3s %-8v| %+v %#v" .Type .Issue.Status .Issue.IssueType .Issue.MolType .Dependency.Type .Issue.WorkType .Issue.WispType}}|{{printf "%v|%s|%q|%30s|%x" .Issue.CreatedAt .Issue.UpdatedAt .Dependency.CreatedAt .Issue.CreatedAt .Dependency.CreatedAt}}|{{printf "%v %q %x %d" .Issue.Labels .Issue.Waiters .Issue.Labels .Issue.Labels}}|{{printf "%s %s" .IssueID}}|{{printf "%5%%s" .Type}}|{{.IssueID | printf "<%s>"}}|{{printf "%.1s" .Type | len}}'
compare_real_database list-format-template-logic exact list --all --limit 0 \
	'--format={{if and (eq .Type "blocks") (ne .Issue.Status "closed")}}blocking{{else if eq .Type "parent-child"}}child of {{.DependsOnID}}{{else if not .Issue.Pinned}}{{.Type}}{{else}}pinned{{end}} {{lt .Issue.Priority 2}} {{ge .Type "p"}} {{eq .Issue.Priority 1 2}} {{or .Issue.Assignee "-"}} {{and .Issue.Pinned .Issue.Status}} {{or .Issue.Assignee .Issue.CreatedAt}} {{not .Issue.Labels}} {{eq .Type .Dependency.Type}}'
compare_real_database list-format-template-range exact list --all --limit 0 \
	'--format={{range $i, $label := .Issue.Labels}}{{if $i}},{{end}}{{$.IssueID}}:{{$label}}{{else}}no labels{{end}} {{range .Issue.Waiters}}[{{.}}]{{end}} {{len .Issue.Labels}} {{len .Type}} {{len .}} {{with .Issue.Assignee}}{{.}}{{else}}unassigned{{end}} {{with $owner := .Issue.Owner}}{{$owner}}{{end}} {{$title := .Issue.Title}}{{len $title}} {{index .Issue.Labels}} {{print .IssueID .Type .Issue.Labels .Issue.Priority}} {{println .Issue.Pinned}}'
compare_real_database list-format-template-trim exact list --limit 0 $'--format={{- .IssueID -}}\n {{ .DependsOnID\n}} {{.missing}} {{"literal"}} {{`raw`}} {{3}}'
real_database_extra_import=""
# The native store renders a template that needs upstream's Go types, which bdhx's plain Go
# strings and maps do not have: %T of the named types and of the structs, methods, a field after a
# string, pointer fields, json.RawMessage, and a nil []string's %#v.
compare_real_database list-format-template-native-types exact list --all --limit 0 \
	'--format={{printf "%T %T %T %T %d" .Type .Issue.Status .Issue .Dependency.CreatedAt .Type}} {{.Issue.CreatedAt.Year}} {{.Type.IsValid}} {{printf "%#v" .Issue.Labels}}'
compare_real_database list-format-template-native-fields exact list --all --limit 0 \
	'--format={{.Issue.StartedAt}}|{{.Issue.ClosedAt}}|{{.Issue.DueAt}}|{{.Issue.EstimatedMinutes}}|{{.Issue.ExternalRef}}|{{.Issue.Metadata}}|{{.Issue.Timeout}}|{{.Issue.ContentHash}}|{{.Issue.RowVersion}}|{{.Issue.IsLitePartial}}|{{.Issue.EffectiveStorageClass}}|{{.Issue.CompactedAtCommit}}'
compare_real_database list-format-template-native-error exact list --limit 0 '--format={{.IssueID}} {{.Issue.Title.Foo}}'
compare_real_database list-max-rows-human exact list --limit 0 --max-rows 1
compare_real_database_env list-max-rows-env-human exact BEADS_MAX_ROWS=1 list --limit 0
compare_real_database_env list-max-rows-env-flag-zero exact BEADS_MAX_ROWS=1 list --limit 1 --max-rows 0
compare_real_database_env list-max-rows-env-malformed exact BEADS_MAX_ROWS=banana list --limit 1
# Upstream reads BEADS_MAX_ROWS with strconv.Atoi: a sign is allowed, a value keeps Go's int range,
# and the warning quotes the value as Go's %q does.
compare_real_database_env list-max-rows-env-plus-sign exact BEADS_MAX_ROWS=+1 list --limit 0
compare_real_database_env list-max-rows-env-negative-zero exact BEADS_MAX_ROWS=-0 list --limit 1
compare_real_database_env list-max-rows-env-above-int32 exact BEADS_MAX_ROWS=4294967297 list --limit 0
compare_real_database_env list-max-rows-env-out-of-range exact BEADS_MAX_ROWS=99999999999999999999 list --limit 1
compare_real_database_env list-max-rows-env-space exact 'BEADS_MAX_ROWS= 1' list --limit 1
compare_real_database_env list-max-rows-env-control-quoted exact BEADS_MAX_ROWS=$'\x01' list --limit 1
compare_real_database_env ready-max-rows-env-above-int32 exact BEADS_MAX_ROWS=4294967297 ready
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
# pflag reads a shorthand group one letter at a time. A value shorthand takes the rest of the group,
# after an optional "=", or else the next argument; an error quotes the group from that letter on.
compare_real_database list-type-shorthand-attached exact list -tbug
compare_real_database list-type-shorthand-equals-json exact list -t=bug --json
compare_real_database list-status-shorthand-attached exact list -sopen
compare_real_database list-assignee-shorthand-attached exact list -afixture
compare_real_database list-label-shorthand-attached exact list -lparity
compare_real_database list-reverse-type-group exact list -rtbug
compare_real_database list-reverse-limit-group exact list -rn1
compare_real_database list-reverse-limit-group-missing exact list -rn
compare_real_database list-reverse-unknown-group exact list -rx
compare_real_database list-reverse-bad-value exact list -r=x
compare_real_database list-reverse-long-bad-value exact list --reverse=x
compare_real_database ready-type-shorthand-attached exact ready -tbug
compare_real_database ready-sort-shorthand-attached exact ready -spriority
compare_real_database ready-unassigned-limit-group exact ready -un1
compare_real_database ready-reverse-group-unknown exact ready -rn1
compare_real_database count-type-shorthand-attached exact count -tbug
compare_real_database search-status-shorthand-attached exact search parity -sopen
compare_real_database stale-status-shorthand-attached exact stale -sopen
compare_real_database dep-list-type-shorthand-attached exact dep list "$real_database_issue_id" -tblocks
compare_real_database query-all-reverse-group exact query -ar status=open --sort title
compare_real_database show-watch-unknown-group exact show "$real_database_issue_id" -wx
compare_real_database show-watch-bad-value exact show "$real_database_issue_id" -w=x
compare_real_database type-shorthand-before-command exact -tbug list
compare_real_database directory-shorthand-equals exact -C=. list --json
# Like upstream, an empty --actor is accepted; status --assigned then takes BEADS_ACTOR.
compare_real_database empty-actor-status-assigned exact --actor= status --assigned --json
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
# Upstream trims the close reason and prints it on one metadata line when it has no line break and
# fits the Markdown wrap width: 80 terminal cells when stdout is a pipe. Otherwise a CLOSE REASON
# section after the metadata lines renders it. In agent mode (BD_AGENT_MODE=1, or any CLAUDE_CODE
# value) the width has no limit, and the section prints the reason as stored.
close_reason_record() {
	jq -cn --arg reason "$1" '{id: "test-reason", title: "Close reason parity", status: "closed",
		priority: 2, issue_type: "task", created_at: "2026-08-20T10:00:00Z",
		updated_at: "2026-08-20T11:00:00Z", closed_at: "2026-08-20T11:00:00Z", close_reason: $reason}'
}
close_reason_fits="$(close_reason_record "$(printf '%066d' 0 | tr 0 r)")"
close_reason_long="$(close_reason_record "$(printf '%067d' 0 | tr 0 r)")"
# 34 double-width characters: 48 runes, but 82 cells with the label.
close_reason_wide="$(close_reason_record "$(printf '%034d' 0 | sed 's/0/界/g')")"
close_reason_lines="$(close_reason_record $'Fixed in two steps.\n\n- **storage**: retry the read\n- docs: note the limit')"
compare_real_database_import show-close-reason-fits exact "$close_reason_fits" show test-reason
compare_real_database_import show-close-reason-long exact "$close_reason_long" show test-reason
compare_real_database_import show-close-reason-wide exact "$close_reason_wide" show test-reason
compare_real_database_import show-close-reason-lines exact "$close_reason_lines" show test-reason --long
compare_real_database_import show-close-reason-trailing-newline exact \
	"$(close_reason_record $'  Shipped in v2.\n')" show test-reason
compare_real_database_import show-close-reason-blank exact "$(close_reason_record $' \t\n')" show test-reason
real_database_extra_env=(BD_AGENT_MODE=1)
compare_real_database_import agent-mode-show-close-reason-long exact "$close_reason_long" show test-reason
compare_real_database_import agent-mode-show-close-reason-wide exact "$close_reason_wide" show test-reason
compare_real_database_import agent-mode-show-close-reason-lines exact "$close_reason_lines" show test-reason
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database show-long-pinned exact show "$(jq -er '.id' "$real_database_seed/pinned.json")" --long
compare_real_database show-long-molecule exact show "$(jq -er '.id' "$real_database_seed/molecule.json")" --long
rare_long_record='{"id":"test-rare","title":"Rare long","description":"tiny","status":"open","priority":2,"issue_type":"event","created_at":"2026-08-20T12:00:00Z","updated_at":"2026-08-21T13:00:00Z","compaction_level":1,"compacted_at":"2026-08-21T14:00:00Z","compacted_at_commit":"abc123","original_size":100,"sender":"agent-a","ephemeral":true,"wisp_type":"heartbeat","pinned":true,"is_template":true,"bonded_from":[{"source_id":"proto-a","bond_type":"parallel","bond_point":"root"}],"await_type":"human","await_id":"approval","timeout":60000000000,"waiters":["alpha","beta"],"source_formula":"release","source_location":"steps[0]","mol_type":"swarm","work_type":"open_competition","event_kind":"agent.started","actor":"agent://a","target":"bead://b","payload":"{\"k\":1}"}'
compare_real_database_import show-long-rare exact "$rare_long_record" show test-rare --long
compare_real_database_import show-thread-json-rare exact "$rare_long_record" show test-rare --thread --json
# Every Issue field that an upstream read fills, in each JSON view that prints an issue record.
# Upstream prints types.Issue in struct order (internal/types/types.go:19-190), so labels and
# list's dependencies come after original_size and before sender. A view that embeds the Issue
# adds its own fields after it, and IssueDetails' own labels, dependencies and comments replace
# the Issue fields of the same names at its position (types.go:1146-1152). Import keeps no
# bonded_from, source_formula, source_location or storage_class, and draws row_lock, which show
# prints as revision, at random, so SQL sets the last two on each copy and keeps updated_at.
full_issue_fields='{"description":"Desc","design":"Design","acceptance_criteria":"Accept","notes":"Notes","spec_id":"SPEC-1","assignee":"ann","owner":"owner@example.invalid","estimated_minutes":45,"created_by":"creator","started_at":"2026-08-20T12:00:00Z","due_at":"2030-01-15T00:00:00Z","defer_until":"2026-01-01T00:00:00Z","external_ref":"gh-77","source_system":"jira","metadata":{"team":"port","rank":2},"compaction_level":2,"compacted_at":"2026-08-22T00:00:00Z","compacted_at_commit":"abc123","original_size":4096,"sender":"agent://sender","wisp_type":"heartbeat","pinned":true,"is_template":true,"bonded_from":[{"source_id":"proto-a","bond_type":"parallel","bond_point":"root"}],"await_type":"human","await_id":"approval","timeout":60000000000,"waiters":["alpha@x","beta@x"],"source_formula":"release","source_location":"steps[0]","mol_type":"swarm","work_type":"open_competition","event_kind":"agent.started","actor":"agent://a","target":"bead://b","payload":"{\"k\":1}"}'
# Usage: full_issue_record ID TITLE PRIORITY CREATED_AT [JSON_OVERRIDES]
full_issue_record() {
	local overrides="${5-}"
	[[ -n "$overrides" ]] || overrides='{}'
	jq -cn --arg id "$1" --arg title "$2" --argjson priority "$3" --arg created "$4" \
		--argjson fields "$full_issue_fields" --argjson overrides "$overrides" \
		'$fields + {id: $id, title: $title, status: "open", priority: $priority, issue_type: "task",
			created_at: $created, updated_at: "2026-08-21T11:00:00Z"} + $overrides'
}
full_issue_import="$(
	full_issue_record test-full-a "Full field record" 1 2026-08-20T10:00:00Z \
		'{"labels":["zeta","alpha"],"dependencies":[{"issue_id":"test-full-a","depends_on_id":"test-full-b","type":"blocks","created_at":"2026-08-20T10:00:00Z","created_by":"creator"}]}'
	full_issue_record test-full-b "Full field blocker" 2 2026-08-20T09:00:00Z \
		'{"labels":["target"],"sender":"agent://b","mol_type":"patrol"}'
	full_issue_record test-full-c "Full field child" 3 2026-08-20T08:00:00Z \
		'{"status":"closed","closed_at":"2026-08-21T08:00:00Z","close_reason":"done","closed_by_session":"session-1","is_template":false,"labels":["kid"],"dependencies":[{"issue_id":"test-full-c","depends_on_id":"test-full-a","type":"parent-child","created_at":"2026-08-20T10:00:00Z"}]}'
	# Ready leaves out pinned issues; no_history stores the row in the wisps table.
	full_issue_record test-full-n "Full field no-history wisp" 0 2026-08-20T07:00:00Z \
		'{"labels":["nl"],"no_history":true,"pinned":false}'
	full_issue_record test-full-w "Full field ephemeral wisp" 2 2026-08-20T06:00:00Z \
		'{"labels":["wl"],"ephemeral":true}'
	full_issue_record test-full-msg-root "Full field root message" 2 2026-08-20T05:00:00Z \
		'{"issue_type":"message","labels":["mail","urgent"],"sender":"alice"}'
	full_issue_record test-full-msg-reply "Full field reply" 2 2026-08-20T05:30:00Z \
		'{"issue_type":"message","labels":["mail"],"sender":"bob","dependencies":[{"issue_id":"test-full-msg-reply","depends_on_id":"test-full-msg-root","type":"replies-to","created_at":"2026-08-20T05:30:00Z"}]}'
	# A molecule of one step: a parallel group would list its members in Go map order.
	full_issue_record test-full-mol "Full field molecule" 2 2026-08-20T04:30:00Z '{"issue_type":"molecule","labels":["proto"]}'
	# A closed gate that lets a ready step of its molecule resume.
	full_issue_record test-full-gmol "Full field gated molecule" 2 2026-08-20T04:00:00Z '{"issue_type":"epic","labels":["gm"]}'
	full_issue_record test-full-gate "Full field gate" 2 2026-08-20T04:10:00Z \
		'{"issue_type":"gate","status":"closed","closed_at":"2026-08-21T04:10:00Z","close_reason":"satisfied","labels":["gate"],"dependencies":[{"issue_id":"test-full-gate","depends_on_id":"test-full-gmol","type":"parent-child","created_at":"2026-08-20T04:10:00Z"}]}'
	full_issue_record test-full-gstep "Full field gated step" 2 2026-08-20T04:20:00Z \
		'{"labels":["step"],"pinned":false,"dependencies":[{"issue_id":"test-full-gstep","depends_on_id":"test-full-gmol","type":"parent-child","created_at":"2026-08-20T04:20:00Z"},{"issue_id":"test-full-gstep","depends_on_id":"test-full-gate","type":"blocks","created_at":"2026-08-20T04:20:00Z"}]}'
)"
full_issue_sql="UPDATE issues SET row_lock = 7, storage_class = 'versioned', updated_at = updated_at WHERE id LIKE 'test-full-%'
UPDATE wisps SET row_lock = 7, updated_at = updated_at WHERE id LIKE 'test-full-%'"
real_database_extra_import="$full_issue_import"
real_database_extra_sql="$full_issue_sql"
compare_real_database full-fields-list-json exact list --all --json --include-templates
compare_real_database full-fields-list-skip-labels-json exact list --all --json --include-templates --skip-labels
compare_real_database_env full-fields-list-json-envelope exact BD_JSON_ENVELOPE=1 list --all --json --include-templates
compare_real_database full-fields-children-json exact children test-full-a --json
compare_real_database full-fields-query-json exact query pinned=true --all --json
compare_real_database full-fields-search-json exact search "Full field" --json
compare_real_database full-fields-ready-json exact ready --json
compare_real_database full-fields-ready-explain-json exact ready --explain --json
# Upstream round-trips the ready --explain, --mol and --gated output through a map, which sorts
# every key, unless BD_JSON_ENVELOPE=1 wraps it in struct order (cmd/bd/output.go:36-99).
compare_real_database_env full-fields-ready-explain-json-envelope exact BD_JSON_ENVELOPE=1 ready --explain --json
compare_real_database full-fields-ready-molecule-json exact ready --mol test-full-mol --json
compare_real_database_env full-fields-ready-molecule-json-envelope exact BD_JSON_ENVELOPE=1 ready --mol test-full-mol --json
compare_real_database full-fields-ready-gated-json exact ready --gated --json
compare_real_database_env full-fields-ready-gated-json-envelope exact BD_JSON_ENVELOPE=1 ready --gated --json
compare_real_database full-fields-blocked-json exact blocked --json
compare_real_database full-fields-show-json exact show test-full-a test-full-b test-full-n test-full-w --json
compare_real_database full-fields-show-dependents-json exact show test-full-a test-full-b --include-dependents --json
compare_real_database_env full-fields-show-json-envelope exact BD_JSON_ENVELOPE=1 show test-full-a --json
compare_real_database full-fields-show-children-json exact show test-full-a --children --json
compare_real_database_env full-fields-show-children-json-envelope exact BD_JSON_ENVELOPE=1 show test-full-a --children --json
compare_real_database full-fields-show-refs-json exact show test-full-b --refs --json
compare_real_database full-fields-show-thread-json exact show test-full-msg-reply --thread --json
compare_real_database full-fields-dep-list-json exact dep list test-full-a --json
compare_real_database full-fields-dep-tree-json exact dep tree test-full-a --json
compare_real_database full-fields-graph-json exact graph test-full-a --json
# Upstream's stale read takes the records from GetIssuesByIDsInTx, which adds each issue's labels
# in label order (internal/storage/issueops/stale.go:76, dependencies.go:1065-1083).
real_database_extra_import="$(full_issue_record test-full-s "Full field stale" 2 2026-08-20T04:00:00Z '{"labels":["zeta","alpha"]}')"
compare_real_database full-fields-stale-json exact stale --days 1 --json
real_database_extra_import=""
real_database_extra_sql=""
# Stale lists the issues that were not updated since the cutoff, stalest first, with their labels.
# It leaves out closed issues, and --status and --limit narrow the IDs before the records are read.
labeled_stale_records="$(printf '%s\n' \
	'{"id":"test-ls-old","title":"Oldest labeled","status":"in_progress","priority":1,"issue_type":"task","assignee":"ann","labels":["zulu","alpha","mike"],"created_at":"2026-01-01T10:00:00Z","updated_at":"2026-01-02T10:00:00Z"}' \
	'{"id":"test-ls-mid","title":"Middle labeled","status":"open","priority":2,"issue_type":"bug","labels":["solo"],"created_at":"2026-01-01T10:00:00Z","updated_at":"2026-02-02T10:00:00Z"}' \
	'{"id":"test-ls-closed","title":"Closed labeled","status":"closed","priority":2,"issue_type":"task","labels":["done"],"created_at":"2026-01-01T10:00:00Z","updated_at":"2026-01-01T12:00:00Z","closed_at":"2026-01-01T12:00:00Z"}')"
compare_real_database_import stale-labels-json exact "$labeled_stale_records" stale --days 1 --json
compare_real_database_import stale-labels-limit-json exact "$labeled_stale_records" stale --days 1 --limit 2 --json
compare_real_database_import stale-labels-status-json exact "$labeled_stale_records" stale --days 1 --status in_progress --json
compare_real_database_import stale-labels-human exact "$labeled_stale_records" stale --days 1
compare_real_database show-thread-human exact show test-msg-leaf --thread
compare_real_database show-thread-json exact show test-msg-leaf ignored-second --thread --json
compare_real_database show-thread-disabled exact show test-msg-root --thread=false
# Upstream encodes the thread records as GetIssue and GetDependentsWithMetadata return them, with
# their labels (cmd/bd/show_thread.go:21, 47, 87-91 and 153). The root and the reply have labels; the
# thread is read from its leaf, which finds the root upward, and from its root, which finds the
# replies downward.
labeled_thread_records="$(printf '%s\n' \
	'{"id":"test-lt-root","title":"Labeled root","description":"Root body","status":"open","priority":2,"issue_type":"message","assignee":"bob","sender":"alice","labels":["mail","urgent"],"created_at":"2026-08-20T10:00:00Z","updated_at":"2026-08-20T10:00:00Z"}' \
	'{"id":"test-lt-reply","title":"Re: Labeled root","description":"Reply body","status":"open","priority":2,"issue_type":"message","assignee":"alice","sender":"bob","labels":["mail"],"created_at":"2026-08-20T11:00:00Z","updated_at":"2026-08-20T11:00:00Z","dependencies":[{"issue_id":"test-lt-reply","depends_on_id":"test-lt-root","type":"replies-to","created_at":"2026-08-20T11:00:00Z","created_by":"fixture"}]}' \
	'{"id":"test-lt-leaf","title":"Re: Re: Labeled root","description":"Leaf body","status":"closed","priority":2,"issue_type":"message","assignee":"bob","sender":"alice","created_at":"2026-08-20T12:00:00Z","updated_at":"2026-08-20T12:00:00Z","closed_at":"2026-08-20T13:00:00Z","dependencies":[{"issue_id":"test-lt-leaf","depends_on_id":"test-lt-reply","type":"replies-to","created_at":"2026-08-20T12:00:00Z","created_by":"fixture"}]}')"
compare_real_database_import show-thread-labels-json exact "$labeled_thread_records" show test-lt-leaf --thread --json
compare_real_database_import show-thread-labels-root-json exact "$labeled_thread_records" show test-lt-root --thread --json
compare_real_database_import show-thread-labels-human exact "$labeled_thread_records" show test-lt-reply --thread
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
# An upstream claim sets the status, the assignee and the start time, and writes a row to the
# Dolt-ignored leases table (internal/storage/issueops/lease.go:169-188), which every full issue read
# joins. These cases claim the child issue that way with fixture SQL. The lease times are taken once,
# so both sides read the same ones, and far from the edges of show's relative-time buckets; a
# heartbeat in the future is "just now". Every issue record in the JSON views carries the lease
# fields, and show prints the Lease line for an in-progress issue. That line names the granting
# replica when node_id names another one.
lease_claim_sql() {
	printf '%s\n' \
		"UPDATE issues SET status = 'in_progress', assignee = 'fixture', started_at = '2026-11-01 10:00:00', updated_at = '2026-11-01 10:00:00' WHERE id = '$1'" \
		"INSERT INTO leases (issue_id, holder, granted_at, lease_expires_at, heartbeat_at, granted_node) VALUES ('$1', 'fixture', '2026-11-01 10:00:00', '$2', '$3', '$4')"
}
# The UTC time this many seconds from now, in SQL DATETIME form.
lease_time() {
	jq -nr --argjson offset "$1" 'now + $offset | floor | strftime("%Y-%m-%d %H:%M:%S")'
}
lease_hours_sql="$(lease_claim_sql "$real_database_child_id" "$(lease_time 12600)" "$(lease_time -5400)" '')"
lease_days_sql="$(lease_claim_sql "$real_database_child_id" "$(lease_time 302400)" "$(lease_time -216000)" node-b)"
lease_expired_sql="$(lease_claim_sql "$real_database_child_id" '2026-01-01 00:00:00' '2026-01-01 00:00:00' '')"
lease_own_node_sql="$(lease_claim_sql "$real_database_child_id" "$(lease_time 108000)" "$(lease_time 3600)" node-a)"
lease_labeled_sql="$lease_days_sql"$'\n'"INSERT INTO labels (issue_id, label) VALUES ('$real_database_child_id', 'claimed')"
compare_real_database_sql lease-show-hours exact "$lease_hours_sql" show "$real_database_child_id"
compare_real_database_sql lease-show-long-days exact "$lease_days_sql" show "$real_database_child_id" --long
compare_real_database_sql lease-show-expired exact "$lease_expired_sql" show "$real_database_child_id"
compare_real_database_sql lease-show-json exact "$lease_days_sql" show "$real_database_child_id" --json
compare_real_database_sql lease-show-dependency-json exact "$lease_days_sql" show "$real_database_grandchild_id" --json
compare_real_database_sql lease-show-dependent-json exact "$lease_days_sql" show "$real_database_epic_id" --json
compare_real_database_sql lease-show-children-json exact "$lease_labeled_sql" show "$real_database_epic_id" --children --json
compare_real_database_sql lease-show-refs-json exact "$lease_labeled_sql" show "$real_database_epic_id" --refs --json
compare_real_database_sql lease-children-json exact "$lease_days_sql" children "$real_database_epic_id" --json
compare_real_database_sql lease-list-json exact "$lease_days_sql" list --status in_progress --json
compare_real_database_sql lease-list-all-json exact "$lease_hours_sql" list --all --json
compare_real_database_sql lease-query-json exact "$lease_days_sql" query status=in_progress --json
compare_real_database_sql lease-query-predicate-json exact "$lease_days_sql" query 'status=in_progress OR priority=0' --json
compare_real_database_sql lease-search-json exact "$lease_days_sql" search parity --status in_progress --json
real_database_extra_env=(BD_NODE_ID=node-a)
compare_real_database_sql lease-show-other-replica exact "$lease_days_sql" show "$real_database_child_id"
compare_real_database_sql lease-show-own-replica exact "$lease_own_node_sql" show "$real_database_child_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='node_id: " node-a "'
compare_real_database_sql lease-show-config-replica exact "$lease_days_sql" show "$real_database_child_id"
real_database_extra_config=""
# With colors on, upstream mutes the whole Lease line (show_format.go:147), the granting replica too.
real_database_extra_env=(NO_COLOR= CLICOLOR_FORCE=1 BD_NODE_ID=node-a)
compare_real_database_sql lease-show-color exact "$lease_days_sql" show "$real_database_child_id"
real_database_extra_env=(NO_COLOR= CLICOLOR_FORCE=1)
compare_real_database_sql lease-show-color-long exact "$lease_hours_sql" show "$real_database_child_id" --long
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# A lease row on an issue that is not in progress shows in the JSON fields, but not as a Lease line.
lease_open_sql="INSERT INTO labels (issue_id, label) VALUES ('$real_database_bug_id', 'leased')"$'\n'"INSERT INTO leases (issue_id, holder, granted_at, lease_expires_at, heartbeat_at, granted_node) VALUES ('$real_database_bug_id', 'fixture', '2026-11-01 10:00:00', '$(lease_time 108000)', '2026-11-01 10:00:00', '')"
compare_real_database_sql lease-open-show exact "$lease_open_sql" show "$real_database_bug_id"
compare_real_database_sql lease-open-show-json exact "$lease_open_sql" show "$real_database_bug_id" --json
# Stale leaves out an issue with a lease heartbeat since the cutoff, however old its update
# (internal/storage/issueops/stale.go:26-37). An older heartbeat keeps it, with its lease fields.
compare_real_database_sql stale-lease-recent-heartbeat-json exact "$lease_hours_sql" stale --days 1 --json
compare_real_database_sql stale-lease-old-heartbeat-json exact "$lease_labeled_sql" stale --days 1 --json
compare_real_database_sql stale-lease-heartbeat-in-window-json exact "$lease_days_sql" stale --days 3 --status in_progress --json
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
# Go's encoder prints that float64 in plain digits below 1e21: 1e12 is 1000000000000, and every value
# near the int64 limit rounds to 9223372036854776000. Here since is 1e12 and the floor 2e12 (one past
# the head of an emptied journal); then since and floor sit just above 2^53; then all three near the limit.
events_trillion_sql="$events_rows_sql
DELETE FROM bd_events_journal
UPDATE bd_events_seq SET next_seq = 1999999999999 WHERE id = 0"
compare_real_database_sql events-tail-trillion-json exact "$events_trillion_sql" \
	events tail --since 1000000000000 --json
events_past_2p53_sql="$events_pruned_sql
UPDATE bd_events_journal SET seq = seq + 9007199254740992
UPDATE bd_events_seq SET next_seq = 9007199254740996 WHERE id = 0"
compare_real_database_sql events-tail-past-2p53-json exact "$events_past_2p53_sql" \
	events tail --since 9007199254740993 --json
events_near_int64_max_sql="$events_rows_sql
DELETE FROM bd_events_journal
UPDATE bd_events_seq SET next_seq = 9223372036854775806 WHERE id = 0"
compare_real_database_sql events-tail-near-int64-max-human exact "$events_near_int64_max_sql" \
	events tail --since 9223372036854775805
compare_real_database_sql events-tail-near-int64-max-json exact "$events_near_int64_max_sql" \
	events tail --since 9223372036854775805 --json
real_database_extra_sql="$events_near_int64_max_sql"
compare_real_database_env events-tail-near-int64-max-envelope-json exact BD_JSON_ENVELOPE=1 \
	events tail --since 9223372036854775805 --json
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
# Upstream's package init loads config.yaml before it parses any argument. When a file does not
# parse, every command prints "Warning: failed to initialize config: <error>" as its first stderr
# line, once, before argument errors, help and every pre-run warning, and then runs with what
# loaded. The load reads the process's own directory, never -C, and the user config.yaml.
broken_yaml=$'list:\n  limit: [unclosed'
compare_no_workspace_user_config config_init_warning_where "$broken_yaml" where
compare_no_workspace_user_config config_init_warning_where_json "$broken_yaml" where --json
compare_no_workspace_user_config config_init_warning_list "$broken_yaml" list
compare_no_workspace_user_config config_init_warning_show_json "$broken_yaml" show test-a --json
compare_no_workspace_user_config config_init_warning_types "$broken_yaml" types
compare_no_workspace_user_config config_init_warning_config_get_json "$broken_yaml" config get export.auto --json
compare_no_workspace_user_config config_init_warning_unknown_command "$broken_yaml" frobnicate
compare_no_workspace_user_config config_init_warning_unknown_flag "$broken_yaml" count --frobnicate
compare_no_workspace_user_config config_init_warning_bad_flag_value "$broken_yaml" list --limit x
compare_no_workspace_user_config config_init_warning_list_help "$broken_yaml" list --help
compare_no_workspace_user_config config_init_warning_help_list "$broken_yaml" help list
no_workspace_user_config="$broken_yaml"
version_expected_stderr="Warning: failed to initialize config: error reading config file: While parsing config: yaml: line 1: did not find expected ',' or ']'"
compare_version_mode config_init_warning_version text version
compare_version_mode config_init_warning_version_json json version --json
version_expected_stderr=""
no_workspace_user_config=""
# The database cases start in work/sub, whose .beads/config.yaml does not parse, and select the
# workspace with -C. Only the startup load reads that file, so no other config warning prints.
write_broken_start_config() {
	mkdir -p "$1/work/sub/.beads"
	printf '%s\n' "$broken_yaml" >"$1/work/sub/.beads/config.yaml"
}
real_database_setup=write_broken_start_config
real_database_directory=sub
compare_real_database config-init-warning-list exact -C .. list
compare_real_database config-init-warning-list-json exact -C .. list --json
compare_real_database config-init-warning-show-json exact -C .. show "$real_database_issue_id" --json
compare_real_database config-init-warning-count exact -C .. count
compare_real_database config-init-warning-where exact -C .. where
compare_real_database config-init-warning-types exact -C .. types
compare_real_database config-init-warning-bad-flag-value exact -C .. ready -n x
real_database_extra_metadata='. + {dolt_server_port: 3999}'
compare_real_database config-init-warning-server-port exact -C .. list
real_database_extra_metadata=""
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database config-init-warning-shared-server-notice exact -C .. where
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=""
real_database_directory=""
# Upstream's pre-run sets up the workspace it selects with prepareSelectedCommandContext, which loads
# the config again with BEADS_DIR set to it. When the workspace's config.yaml or config.local.yaml, or
# the user config.yaml, does not parse, each setup prints "Warning: failed to reinitialize config for
# selected beads dir: <error>" after the startup warning: once for version, the root help and bd help
# <command>, never for --help, twice for where (its command body sets up again), and twice for commands
# that open a store, once with a --db path. The first setup then prints the shared-server notice. A
# metadata.json that does not load stops the first setup after its warning. where still reads the
# prefix from the embedded database; without metadata.json it reads the database "beads", which the
# fixture does not have, and prints no prefix.
break_workspace_config() {
	printf '%s\n' "$broken_yaml" >"$1/work/.beads/config.yaml"
}
real_database_setup=break_workspace_config
compare_real_database reinit-config-warning-version stderr-only version
compare_real_database reinit-config-warning-version-json stderr-only version --json
compare_real_database reinit-config-warning-root stderr-only
compare_real_database reinit-config-warning-help-command exact help list
compare_real_database reinit-config-warning-help-flag exact list --help
compare_real_database reinit-config-warning-where exact where
compare_real_database reinit-config-warning-where-json exact where --json
compare_real_database reinit-config-warning-directory-where exact -C . where
compare_real_database reinit-config-warning-db-path-where exact --db .beads where
compare_real_database reinit-config-warning-db-path-version stderr-only --db .beads/embeddeddolt version
compare_real_database reinit-config-warning-show exact show "$real_database_bug_id"
compare_real_database reinit-config-warning-show-json exact show "$real_database_bug_id" --json
compare_real_database reinit-config-warning-db-path-show exact --db .beads show "$real_database_bug_id"
compare_real_database reinit-config-warning-comments exact comments "$real_database_issue_id"
compare_real_database reinit-config-warning-dep-tree exact dep tree "$real_database_issue_id"
compare_real_database reinit-config-warning-blocked-json exact blocked --json
compare_real_database reinit-config-warning-label-list exact label list "$real_database_bug_id"
compare_real_database reinit-config-warning-types exact types
compare_real_database reinit-config-warning-types-database-flag exact types --database other
compare_real_database reinit-config-warning-show-database-flag-json exact show "$real_database_issue_id" --database other --json
real_database_extra_env=("BEADS_DIR=<work>/.beads")
compare_real_database reinit-config-warning-beads-dir-version stderr-only version
compare_real_database reinit-config-warning-beads-dir-where exact where
real_database_extra_env=(BEADS_DOLT_SHARED_SERVER=1)
compare_real_database reinit-config-warning-shared-server-where exact where
compare_real_database reinit-config-warning-shared-server-version stderr-only version
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
break_workspace_config_and_metadata() {
	break_workspace_config "$1"
	printf '{not json' >"$1/work/.beads/metadata.json"
}
real_database_setup=break_workspace_config_and_metadata
compare_real_database reinit-config-warning-bad-metadata-where exact where
compare_real_database reinit-config-warning-bad-metadata-version stderr-only version
compare_real_database reinit-config-warning-bad-metadata-count exact count
break_workspace_config_without_metadata() {
	break_workspace_config "$1"
	rm -f "$1/work/.beads/metadata.json"
}
real_database_setup=break_workspace_config_without_metadata
compare_real_database reinit-config-warning-no-metadata-where exact where
compare_real_database reinit-config-warning-no-metadata-where-json exact where --json
write_broken_user_config() {
	mkdir -p "$1/user-home/.config/bd"
	printf '%s\n' "$broken_yaml" >"$1/user-home/.config/bd/config.yaml"
}
real_database_setup=write_broken_user_config
compare_real_database reinit-user-config-warning-where exact where
compare_real_database reinit-user-config-warning-version stderr-only version
compare_real_database reinit-user-config-warning-show-json exact show "$real_database_bug_id" --json
write_broken_local_config() {
	printf '%s\n' "$broken_yaml" >"$1/work/.beads/config.local.yaml"
}
real_database_setup=write_broken_local_config
compare_real_database reinit-local-config-warning-where exact where
compare_real_database reinit-local-config-warning-help-command exact help count
# After a user config.yaml that loads, the error names the workspace's config.yaml as BEADS_DIR names
# it: for a --db path, the directory that upstream derives from the path as given.
write_user_config_and_break_workspace_config() {
	break_workspace_config "$1"
	mkdir -p "$1/user-home/.config/bd"
	printf 'parity: true\n' >"$1/user-home/.config/bd/config.yaml"
}
real_database_setup=write_user_config_and_break_workspace_config
compare_real_database reinit-merged-config-warning-where exact where
compare_real_database reinit-merged-config-warning-db-path-where exact --db .beads where
compare_real_database reinit-merged-config-warning-db-path-version stderr-only --db .beads/embeddeddolt version
compare_real_database reinit-merged-config-warning-db-path-show-json exact --db .beads show "$real_database_bug_id" --json
# The commands that the native read-only store serves also warn and run with the settings that loaded
# (beadshx-m08-02.13), as do show and label list for an issue that has dependencies.
real_database_setup=break_workspace_config
compare_real_database reinit-config-warning-list exact list
compare_real_database reinit-config-warning-count-json exact count --json
compare_real_database reinit-config-warning-ready exact ready
# Human `info` also checks the Git hooks, which this build does not port.
compare_real_database reinit-config-warning-info-json exact info --json
compare_real_database reinit-config-warning-children exact children "$real_database_epic_id"
compare_real_database reinit-config-warning-search exact search parity
compare_real_database reinit-config-warning-query-json exact query status=open --json
compare_real_database reinit-config-warning-stale exact stale
compare_real_database reinit-config-warning-orphans exact orphans
compare_real_database reinit-config-warning-status exact status
compare_real_database reinit-config-warning-ping ping-human ping
compare_real_database reinit-config-warning-label-list-all exact label list-all
compare_real_database reinit-config-warning-show-dependencies exact show test-abcd11
compare_real_database reinit-config-warning-show-parent exact show "$real_database_child_id"
compare_real_database reinit-config-warning-label-list-dependencies exact label list test-abcd11
compare_real_database reinit-config-warning-show-refs exact show "$real_database_epic_id" --refs
compare_real_database reinit-config-warning-show-thread exact show test-msg-leaf --thread
compare_real_database reinit-config-warning-show-children exact show "$real_database_epic_id" --children
# A --db path sets up the workspace once.
compare_real_database reinit-config-warning-db-path-count exact --db .beads count
# config show lists what loaded, also when a --db path, BEADS_DIR or -C selects the workspace
# (beadshx-m08-02.14). Only a user config.yaml that exists makes this build refuse it (see below).
compare_real_database reinit-config-warning-config-show-json exact config show --json
compare_real_database reinit-config-warning-db-path-config-show exact --db .beads config show
compare_real_database reinit-config-warning-directory-config-show exact -C . config show --source config.yaml
real_database_extra_env=("BEADS_DIR=<work>/.beads")
compare_real_database reinit-config-warning-beads-dir-config-show exact config show --source default
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=""
reinit_config_failure="error reading config file: While parsing config: yaml: line 1: did not find expected ',' or ']'"
reinit_config_warning="Warning: failed to reinitialize config for selected beads dir: $reinit_config_failure"
reinit_store_warnings="Warning: failed to initialize config: $reinit_config_failure"$'\n'"$reinit_config_warning"$'\n'"$reinit_config_warning"
# With a user config.yaml, config show prints the same warnings and then refuses, as without a broken file.
reinit_merged_failure="error merging config file <work>/.beads/config.yaml: While parsing config: yaml: line 1: did not find expected ',' or ']'"
reinit_merged_warning="Warning: failed to reinitialize config for selected beads dir: $reinit_merged_failure"
candidate_only_setup=write_user_config_and_break_workspace_config
expect_candidate_failure reinit-merged-config-warning-config-show-unported "" \
	"Warning: failed to initialize config: $reinit_merged_failure"$'\n'"$reinit_merged_warning"$'\n'"$reinit_merged_warning"$'\n'"Error: config show is not available yet when a user config.yaml exists in this build" \
	"" config show
candidate_only_setup=""
# Without metadata.json upstream creates the database "beads"; both setups warn before that.
candidate_only_setup=break_workspace_config_without_metadata
expect_candidate_failure reinit-config-warning-no-metadata-count-unported "" \
	"$reinit_store_warnings"$'\n'"$no_metadata_warning"$'\n'"Error: count is not available yet when the embedded store has no database named \"beads\" in this build" \
	"" count
candidate_only_setup=""
# bdhx's refusals follow the same switch as upstream's errors.
real_database_extra_env=(BD_JSON=1)
candidate_only_setup=enable_shared_server
expect_candidate_failure global-json-env-shared-server-refusal \
	'{"error":"count is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" count
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
	'{"error":"list is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" list
expect_candidate_failure global-json-yaml-shared-server-flag-false-refusal "" \
	"$shared_server_notice"$'\n'"Error: list is not available yet in shared-server mode in this build" "" list --json=false
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
# Upstream's agent mode: BD_AGENT_MODE=1, or any non-empty CLAUDE_CODE, from the environment or
# from .env. The flat list then prints one "ID: Title" line for each issue, with the dependency
# note, also for --long. It prints no status icon, priority, type, labels or --skip-labels footer.
# The tree view, --format, --json and show --children do not change. show prints Markdown as
# stored. A CLAUDE_CODE run of show can print upstream's random Claude setup tip, so show cases
# use BD_AGENT_MODE.
real_database_extra_env=(BD_AGENT_MODE=1)
compare_real_database agent-mode-list-flat exact list --flat
compare_real_database agent-mode-list-flat-long exact list --flat --long --all
compare_real_database agent-mode-list-flat-skip-labels exact list --flat --skip-labels --ready
compare_real_database agent-mode-list-flat-limit exact list --flat --limit 3
compare_real_database agent-mode-list-flat-empty exact list --flat --status deferred
compare_real_database agent-mode-list-tree exact list
compare_real_database agent-mode-list-format exact list --flat --format digraph
compare_real_database agent-mode-list-format-dot exact list --flat --format dot
compare_real_database agent-mode-list-json exact list --flat --json --limit 3
compare_real_database agent-mode-children exact children "$real_database_epic_id"
compare_real_database agent-mode-show-markdown exact show "$real_database_content_id"
real_database_extra_env=(CLAUDE_CODE=1)
compare_real_database agent-mode-claude-code-list-flat exact list --tree=false --all
real_database_extra_env=(BD_AGENT_MODE=true)
compare_real_database agent-mode-only-one-counts exact list --flat
real_database_extra_env=(BD_AGENT_MODE=0 CLAUDE_CODE=)
compare_real_database agent-mode-empty-claude-code exact list --flat
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database_dotenv dotenv-agent-mode-list-flat exact $'BD_AGENT_MODE=1\n' list --flat
compare_real_database_dotenv dotenv-claude-code-list-flat exact $'CLAUDE_CODE=yes\n' list --flat --long
compare_real_database_dotenv dotenv-agent-mode-show exact $'BD_AGENT_MODE=1\n' show "$real_database_content_id"
real_database_extra_env=(BD_AGENT_MODE=0)
compare_real_database_dotenv dotenv-agent-mode-environment-wins exact $'BD_AGENT_MODE=1\n' list --flat
real_database_extra_env=(CLAUDE_CODE=)
compare_real_database_dotenv dotenv-claude-code-empty-environment-wins exact $'CLAUDE_CODE=1\n' list --flat
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# On a terminal, agent mode lowers the default limit of list from 50 to 20, and every list view
# says on stderr when a limit hid issues. These cases run each side on a pseudo-terminal through a
# runner that prints the transcript: stdout and stderr in the order written, without carriage
# returns and without the echo of the end of input that `script` sends. The flat list without agent
# mode would start a pager there, so it has no case. bdhx prints the hint after a Go template that
# it renders itself, but not after one that the native store renders (see engdocs/beadshx/compatibility/limits.md).
# The fixture lists 20 issues by default, so the cases add a 21st, of the lowest priority.
# A third argument sets the pseudo-terminal's column count (stty cols) before the binary runs;
# without it the pseudo-terminal reports no size, so term.GetSize gives 0 columns.
write_terminal_runner() {
	local runner="$1" binary="$2" columns="${3:-}"
	{
		printf '#!/usr/bin/env bash\nbinary=%q\ncolumns=%q\n' "$binary" "$columns"
		cat <<'RUNNER'
case "$(uname -s)" in
Darwin)
	if [[ -n "$columns" ]]; then
		transcript="$(script -q /dev/null /bin/sh -c 'stty cols "$0" rows 40; shift; exec "$@"' \
			"$columns" placeholder "$binary" "$@" </dev/null; status=$?; printf x; exit "$status")"
	else
		transcript="$(script -q /dev/null "$binary" "$@" </dev/null; status=$?; printf x; exit "$status")"
	fi
	;;
Linux)
	printf -v invocation '%q ' "$binary" "$@"
	if [[ -n "$columns" ]]; then
		invocation="stty cols $columns rows 40; exec $invocation"
	fi
	transcript="$(script -qec "$invocation" /dev/null </dev/null; status=$?; printf x; exit "$status")"
	;;
*)
	printf 'unsupported pseudo-terminal host: %s\n' "$(uname -s)" >&2
	exit 1
	;;
esac
status=$?
transcript="${transcript%x}"
transcript="${transcript//$'^D\b\b'/}"
printf '%s' "${transcript//$'\r'/}"
exit "$status"
RUNNER
	} >"$runner"
	chmod +x "$runner"
}
write_terminal_runner "$test_root/bin/terminal-oracle" "$oracle"
write_terminal_runner "$test_root/bin/terminal-candidate" "$candidate"
write_terminal_runner "$test_root/bin/terminal-wide-oracle" "$oracle" 120
write_terminal_runner "$test_root/bin/terminal-wide-candidate" "$candidate" 120
pipe_oracle="$oracle"
pipe_candidate="$candidate"
import_terminal_issue() {
	(
		cd "$1/work"
		printf '%s\n' '{"id":"test-terminal","title":"Twenty-first parity issue","status":"open","priority":4,"issue_type":"task","created_at":"2026-08-20T10:00:00Z","updated_at":"2026-08-20T10:00:00Z"}' |
			env HOME="$1/user-home" XDG_CONFIG_HOME="$1/config" "${real_database_env[@]}" \
				"$pipe_oracle" import - --json >/dev/null
	)
}
oracle="$test_root/bin/terminal-oracle"
candidate="$test_root/bin/terminal-candidate"
real_database_setup=import_terminal_issue
real_database_extra_env=(BD_AGENT_MODE=1)
compare_real_database agent-mode-terminal-list-flat exact list --flat
compare_real_database agent-mode-terminal-list-flat-all exact list --flat --all
compare_real_database agent-mode-terminal-list-tree exact list --skip-labels
compare_real_database agent-mode-terminal-list-json exact list --json --limit 2
compare_real_database agent-mode-terminal-list-parent exact list --parent "$real_database_epic_id" --limit 1
compare_real_database agent-mode-terminal-list-format-digraph exact list --format digraph
compare_real_database agent-mode-terminal-list-format-template exact list --format '{{.IssueID}} -> {{.DependsOnID}}'
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database terminal-list-tree-limit exact list --limit 2
compare_real_database terminal-list-format-digraph-limit exact list --format digraph --limit 15
compare_real_database terminal-list-format-dot-limit exact list --format dot --limit 2
compare_real_database terminal-list-format-template-limit exact list --format '{{.IssueID}} {{.DependsOnID}} {{.Type}}' --limit 15
compare_real_database terminal-list-format-digraph-all exact list --format digraph --limit 0
real_database_setup=""
oracle="$pipe_oracle"
candidate="$pipe_candidate"
# On a 120-column terminal the wrap width is the terminal width, capped at 100 cells: a
# 67-character reason now fits, 86 characters still fit, and 87 go into the section. The
# terminal runners read no stdin, so the record is imported through the pipe oracle first.
wide_close_reason=""
import_wide_close_reason() {
	(
		cd "$1/work"
		printf '%s\n' "$wide_close_reason" |
			env HOME="$1/user-home" XDG_CONFIG_HOME="$1/config" "${real_database_env[@]}" \
				"$pipe_oracle" import - --json >/dev/null
	)
}
oracle="$test_root/bin/terminal-wide-oracle"
candidate="$test_root/bin/terminal-wide-candidate"
real_database_setup=import_wide_close_reason
wide_close_reason="$close_reason_long"
compare_real_database terminal-wide-show-close-reason-long exact show test-reason
wide_close_reason="$(close_reason_record "$(printf '%086d' 0 | tr 0 r)")"
compare_real_database terminal-wide-show-close-reason-cap-fits exact show test-reason
wide_close_reason="$(close_reason_record "$(printf '%087d' 0 | tr 0 r)")"
compare_real_database terminal-wide-show-close-reason-cap-long exact show test-reason
real_database_setup=""
oracle="$pipe_oracle"
candidate="$pipe_candidate"
# With colors on, upstream's internal/ui package init asks the terminal for its background once per
# process (lipgloss.HasDarkBackground), before any other output and for every command, also for one
# that prints no color. It writes an OSC 11 query and a DA1 request to stdin, then again to stdout
# when stdin gets no answer, and waits up to 2 s for each answer. It asks only when stdin and stdout
# are terminals. --no-color and .beads/.env come too late to stop it. These cases run each side on a
# pseudo-terminal through scripts/beadshx/pty_transcript.py and compare every byte written there,
# the query bytes too. A terminal that answers none makes each side wait for both timeouts, about
# 4 s, and gives the dark palette; one that answers light gives the light palette at once. The
# runner kills a side that runs longer than 30 s. The environment turns colors on and hyperlinks
# off, whatever the caller's environment is; one show case turns hyperlinks on with TERM_PROGRAM.
write_pty_runner() {
	local runner="$1" binary="$2" answer="$3"
	printf '#!/usr/bin/env bash\nexec python3 -I %q --answer %q --timeout 30 -- %q "$@"\n' \
		"$repository_root/scripts/beadshx/pty_transcript.py" "$answer" "$binary" >"$runner"
	chmod +x "$runner"
}
import_terminal_link_issue() {
	(
		cd "$1/work"
		printf '%s\n' '{"id":"test-link","title":"Linked parity issue","description":"See [the docs](https://example.com/docs) and **bold** <text>.","status":"open","priority":2,"issue_type":"task","created_at":"2026-08-20T10:00:00Z","updated_at":"2026-08-20T10:00:00Z"}' |
			env HOME="$1/user-home" XDG_CONFIG_HOME="$1/config" "${real_database_env[@]}" \
				"$pipe_oracle" import - --json >/dev/null
	)
}
write_no_color_dotenv() {
	printf 'NO_COLOR=1\n' >"$1/work/.beads/.env"
}
if python3 -I -c 'import os, pty; [os.close(fd) for fd in os.openpty()]' 2>/dev/null; then
	for answer in none light; do
		write_pty_runner "$test_root/bin/pty-$answer-oracle" "$pipe_oracle" "$answer"
		write_pty_runner "$test_root/bin/pty-$answer-candidate" "$pipe_candidate" "$answer"
	done
	pty_color_env=(NO_COLOR= CLICOLOR= CLICOLOR_FORCE= BD_GIT_HOOK= TERM=xterm-256color BD_AGENT_MODE= CLAUDE_CODE=
		GLAMOUR_STYLE= FORCE_HYPERLINK= TERM_PROGRAM= WT_SESSION= KITTY_WINDOW_ID= WEZTERM_EXECUTABLE=
		KONSOLE_VERSION= DOMTERM= GHOSTTY_RESOURCES_DIR= VTE_VERSION=)
	real_database_extra_env=("${pty_color_env[@]}")
	oracle="$test_root/bin/pty-none-oracle"
	candidate="$test_root/bin/pty-none-candidate"
	compare_real_database terminal-color-ping ping-human ping
	compare_real_database terminal-color-count exact count
	oracle="$test_root/bin/pty-light-oracle"
	candidate="$test_root/bin/pty-light-candidate"
	compare_real_database terminal-color-light-ping ping-human ping
	compare_real_database terminal-color-info-thanks thanks-page info --thanks
	compare_real_database terminal-color-no-color-flag ping-human --no-color ping
	compare_real_database terminal-color-show exact show "$real_database_content_id"
	compare_real_database terminal-color-list exact list --limit 3
	real_database_setup=break_workspace_config
	compare_real_database terminal-color-config-warning exact count
	# NO_COLOR from .beads/.env comes after the question and the styles, but the Markdown renderer,
	# which decides each time it renders, leaves out its colors.
	real_database_setup=write_no_color_dotenv
	compare_real_database terminal-color-dotenv-no-color-show exact show "$real_database_content_id"
	real_database_setup=import_terminal_link_issue
	compare_real_database terminal-color-show-link exact show test-link
	real_database_extra_env=("${pty_color_env[@]}" TERM_PROGRAM=vscode)
	compare_real_database terminal-color-show-link-hyperlinks exact show test-link
	real_database_extra_env=("${pty_color_env[@]}" TERM_PROGRAM=vscode NO_COLOR=1)
	compare_real_database terminal-no-color-show-link-hyperlinks exact show test-link
	real_database_setup=""
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
	oracle="$pipe_oracle"
	candidate="$pipe_candidate"
else
	printf 'parity [%ss]: SKIP terminal color cases (python3 cannot open a pseudo-terminal)\n' "$SECONDS"
fi
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
store_refusal_notice="$shared_server_notice"
expect_store_refusal dotenv-shared-server-unported "$shared_reason" count count
store_refusal_notice=""
dotenv_contents=$'BD_DOLT_SHARED_SERVER=true\nBD_JSON=1\n'
expect_candidate_failure dotenv-bd-shared-server-json-unported \
	'{"error":"config show is not available yet in shared-server mode in this build","schema_version":1}' "$shared_server_notice" "" config show
# A db setting selects the directory derived from its path, so upstream leaves this workspace's .env
# file unread, and BD_JSON there does not turn JSON on.
candidate_only_setup=write_dotenv_with_database_path
dotenv_contents=$'BD_JSON=1\n'
expect_candidate_failure dotenv-db-setting-other-directory-unported "" \
	"Error: ready is not available yet when the db setting names a database in this build" "" ready
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
# When neither config.yaml parses, each fails on its own line. The startup warning names the current
# directory's file (line 3). A store command sets up the current directory's workspace twice; where sets up
# the BEADS_DB or BD_DB workspace twice, version and help pages once, and a --db path once (line 1).
break_both_workspace_configs() {
	add_other_workspace "$1"
	printf 'a: 1\nb: 2\n%s\n' "$broken_yaml" >"$1/work/.beads/config.yaml"
	printf '%s\n' "$broken_yaml" >"$1/work/other/.beads/config.yaml"
}
real_database_setup=break_both_workspace_configs
compare_beads_db beads-db-both-broken-configs-count exact BEADS_DB=other/.beads count
compare_beads_db beads-db-both-broken-configs-list-json exact BEADS_DB=other/.beads list --json
compare_beads_db beads-db-both-broken-configs-where exact BEADS_DB=other/.beads where
compare_beads_db beads-db-both-broken-configs-version stderr-only BEADS_DB=other/.beads version
compare_beads_db beads-db-both-broken-configs-help-command exact BEADS_DB=other/.beads help count
compare_beads_db beads-db-both-broken-configs-bd-db-where-json exact BD_DB=other/.beads where --json
compare_beads_db beads-db-both-broken-configs-db-flag-count exact BEADS_DB=other/.beads --db other/.beads count
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
# BEADS_DB=. names the working directory as a database path, so upstream sets up
# its parent (resolveCommandBeadsDir falls back to filepath.Dir), the 0755
# candidate state root, and warns about its permissions before it opens a store.
expect_beads_db_refusal beads-db-plain-directory-json-unported BEADS_DB=. \
	'{"error":"list is not available yet when BEADS_DB names this path in this build","schema_version":1}' \
	'Warning: <state> has permissions 0755 (recommended: 0700). Run: chmod 700 <state>' list --json
# BEADS_DB=<work>/db names a directory with no metadata.json, so upstream sets up
# the parent <work> (resolveCommandBeadsDir's filepath.Dir fallback) and warns
# about its 0755 permissions first.
expect_beads_db_refusal beads-db-project-directory-unported BEADS_DB='<work>/db' "" \
	$'Warning: <work> has permissions 0755 (recommended: 0700). Run: chmod 700 <work>\nError: show is not available yet when BEADS_DB names this path in this build' \
	show "$real_database_issue_id"
expect_beads_db_refusal beads-db-deeper-path-unported BEADS_DB=db/.beads/missing/beads.db "" \
	"Error: ready is not available yet when BEADS_DB names this path in this build" ready
expect_beads_db_refusal beads-db-trailing-slash-unported BEADS_DB=db/.beads/ "" \
	"Error: where is not available yet when BEADS_DB names this path in this build" where
expect_beads_db_refusal beads-db-where-missing-path-unported BEADS_DB=missing/beads.db "" \
	"Error: where is not available yet when BEADS_DB names this path in this build" where
# BD_DB=missing selects `.` for where, as its directory, and group and others can read the work
# directory, so both of upstream's setups first warn about it.
loose_work_warning='Warning: . has permissions 0755 (recommended: 0700). Run: chmod 700 .'
expect_beads_db_refusal beads-db-where-bd-db-json-unported BD_DB=missing \
	'{"error":"where is not available yet when BD_DB names this path in this build","schema_version":1}' \
	"$loose_work_warning"$'\n'"$loose_work_warning" where --json
move_workspace_without_database() {
	move_workspace_to_db "$1"
	rm -rf "$1/work/db/.beads/embeddeddolt"
}
candidate_only_setup=move_workspace_without_database
expect_beads_db_refusal beads-db-workspace-without-database-unported BEADS_DB=db/.beads "" \
	"Error: count is not available yet when BEADS_DB names this path in this build" count
candidate_only_setup=""
# Before it opens or creates a database for such a path, upstream sets up the directory that
# resolveCommandBeadsDir derives from FindDatabasePath's path: here the workspace, for a path inside
# it, a trailing slash, or a workspace without a database. In shared-server mode it prints the notice
# for that directory, and this build prints it before its refusal. A directory without metadata.json
# prints none.
move_shared_server_workspace_to_db() {
	move_workspace_to_db "$1"
	printf 'dolt:\n  shared-server: true\n' >>"$1/work/db/.beads/config.yaml"
}
candidate_only_setup=move_shared_server_workspace_to_db
expect_beads_db_refusal beads-db-deeper-path-shared-server-notice-unported BEADS_DB=db/.beads/missing/beads.db "" \
	"$shared_server_notice"$'\n'"Error: count is not available yet when BEADS_DB names this path in this build" count
expect_beads_db_refusal beads-db-trailing-slash-shared-server-notice-json-unported BEADS_DB=db/.beads/ \
	'{"error":"list is not available yet when BEADS_DB names this path in this build","schema_version":1}' \
	"$shared_server_notice" list --json
move_shared_server_workspace_without_database() {
	move_shared_server_workspace_to_db "$1"
	rm -rf "$1/work/db/.beads/embeddeddolt"
}
candidate_only_setup=move_shared_server_workspace_without_database
expect_beads_db_refusal beads-db-workspace-without-database-shared-server-notice-unported BEADS_DB=db/.beads "" \
	"$shared_server_notice"$'\n'"Error: show is not available yet when BEADS_DB names this path in this build" \
	show "$real_database_issue_id"
candidate_only_setup=move_workspace_to_db
expect_beads_db_refusal beads-db-missing-path-shared-server-env-unported \
	'BEADS_DB=missing/beads.db BEADS_DOLT_SHARED_SERVER=1' "" \
	"Error: ready is not available yet when BEADS_DB names this path in this build" ready
# A config.yaml there that does not parse makes that setup print its reinitialize warning first, and then
# the notice (beadshx-m08-02.14): once for a store command, twice for where.
move_workspace_breaking_config() {
	move_workspace_to_db "$1"
	printf '%s\n' "$broken_yaml" >"$1/work/db/.beads/config.yaml"
}
candidate_only_setup=move_workspace_breaking_config
expect_beads_db_refusal beads-db-deeper-path-broken-config-unported BEADS_DB=db/.beads/missing/beads.db "" \
	"$reinit_config_warning"$'\n'"Error: count is not available yet when BEADS_DB names this path in this build" count
expect_beads_db_refusal beads-db-trailing-slash-broken-config-json-unported BEADS_DB=db/.beads/ \
	'{"error":"list is not available yet when BEADS_DB names this path in this build","schema_version":1}' \
	"$reinit_config_warning" list --json
expect_beads_db_refusal beads-db-where-deeper-path-broken-config-unported BEADS_DB=db/.beads/missing/beads.db "" \
	"$reinit_config_warning"$'\n'"$reinit_config_warning"$'\n'"Error: where is not available yet when BEADS_DB names this path in this build" where
expect_beads_db_refusal beads-db-deeper-path-broken-config-shared-server-env-unported \
	'BEADS_DB=db/.beads/missing/beads.db BEADS_DOLT_SHARED_SERVER=1' "" \
	"$reinit_config_warning"$'\n'"$shared_server_notice"$'\n'"Error: ready is not available yet when BEADS_DB names this path in this build" ready
move_workspace_without_database_breaking_config() {
	: "${1:?}"
	move_workspace_breaking_config "$1"
	rm -rf "$1/work/db/.beads/embeddeddolt"
}
candidate_only_setup=move_workspace_without_database_breaking_config
expect_beads_db_refusal beads-db-workspace-without-database-broken-config-unported BEADS_DB=db/.beads "" \
	"$reinit_config_warning"$'\n'"Error: show is not available yet when BEADS_DB names this path in this build" \
	show "$real_database_issue_id"
candidate_only_setup=""
# A metadata.json there that does not load stops upstream in that setup, with the load warning and
# error, before it writes anything.
move_workspace_with_broken_metadata() {
	move_workspace_to_db "$1"
	printf '{bad' >"$1/work/db/.beads/metadata.json"
}
real_database_read_only=1
real_database_setup=move_workspace_with_broken_metadata
compare_beads_db beads-db-deeper-path-broken-metadata-count exact BEADS_DB=db/.beads/missing/beads.db count
compare_beads_db beads-db-trailing-slash-broken-metadata-list-json exact BEADS_DB=db/.beads/ list --json
# where, version and help pages set up the directory that the path selects there, and where guards it
# (beadshx-m08-01.12): the load warning names it as the path gives it, and where stops with the load error.
compare_beads_db beads-db-where-deeper-path-broken-metadata exact BEADS_DB=db/.beads/missing/beads.db where
compare_beads_db beads-db-where-trailing-slash-broken-metadata-json exact BEADS_DB=db/.beads/ where --json
compare_beads_db beads-db-where-database-broken-metadata exact BEADS_DB=db/.beads/embeddeddolt where
compare_beads_db beads-db-where-workspace-broken-metadata exact BEADS_DB=db/.beads where
compare_beads_db beads-db-bd-db-where-broken-metadata exact BD_DB=db/.beads/missing/beads.db where
compare_beads_db beads-db-version-broken-metadata stderr-only BEADS_DB=db/.beads/missing/beads.db version
compare_beads_db beads-db-help-command-broken-metadata exact BEADS_DB=db/.beads/beads.db help count
compare_beads_db db-flag-where-broken-metadata exact BEADSHX_PARITY_EXTRA=1 --db db/.beads where
# The guard stops a legacy layout there, for where and for a command that opens a store.
move_workspace_to_legacy_dolt_db() {
	move_workspace_to_db "$1"
	mv -f "$1/work/db/.beads/embeddeddolt" "$1/work/db/.beads/dolt"
}
real_database_setup=move_workspace_to_legacy_dolt_db
compare_beads_db beads-db-deeper-path-legacy-dolt-count exact BEADS_DB=db/.beads/missing/beads.db count
compare_beads_db beads-db-workspace-legacy-dolt-list-json exact BEADS_DB=db/.beads list --json
compare_beads_db beads-db-where-deeper-path-legacy-dolt exact BEADS_DB=db/.beads/missing/beads.db where
compare_beads_db beads-db-where-workspace-legacy-dolt-json exact BEADS_DB=db/.beads where --json
real_database_setup=move_workspace_with_broken_metadata
# Upstream loads the .env file of the directory that it sets up. For `where`, `version` and help pages
# that is the directory derived from a BEADS_DB, BD_DB or db setting path, even when a workspace is
# found from the current directory: the .env file of that workspace stays unread.
add_other_workspace_with_dotenv() {
	add_other_workspace "$1"
	printf 'BEADS_DOLT_SHARED_SERVER=1\n' >"$1/work/other/.beads/.env"
}
real_database_setup=add_other_workspace_with_dotenv
compare_beads_db beads-db-other-dotenv-version stderr-only BEADS_DB=other/.beads version
compare_beads_db beads-db-other-dotenv-help-command exact BD_DB=other/.beads/embeddeddolt help count
add_other_workspace_with_setting_and_dotenv() {
	add_other_workspace_with_dotenv "$1"
	printf 'db: other/.beads/beads.db\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=add_other_workspace_with_setting_and_dotenv
compare_beads_db db-setting-other-dotenv-help-command exact BEADSHX_PARITY_EXTRA=1 help list
add_other_workspace_with_caller_dotenv() {
	add_other_workspace "$1"
	printf 'BEADS_DOLT_SHARED_SERVER=1\nBD_JSON=1\n' >"$1/work/.beads/.env"
}
real_database_setup=add_other_workspace_with_caller_dotenv
compare_beads_db beads-db-caller-dotenv-version stderr-only BEADS_DB=other/.beads version
compare_beads_db beads-db-caller-dotenv-where exact BEADS_DB=other/.beads where
# Upstream's pre-run sets BEADS_DIR to the directory that a db setting path selects, so the body of where
# finds the workspace through BEADS_DIR and names it by its absolute path, with its config.yaml prefix and
# its database. A path that selects no workspace leaves where at the current directory's workspace.
other_database_setting=""
set_other_database_setting() {
	add_other_workspace "$1"
	printf 'issue-prefix: elsewhere\n' >>"$1/work/other/.beads/config.yaml"
	printf 'db: %s\n' "$other_database_setting" >>"$1/work/.beads/config.yaml"
}
real_database_setup=set_other_database_setting
other_database_setting=other/.beads/beads.db
compare_real_database db-setting-other-where exact where
compare_real_database db-setting-other-where-json exact where --json
other_database_setting=other/.beads
compare_real_database db-setting-other-directory-where exact where
other_database_setting=other/.beads/embeddeddolt
compare_real_database db-setting-other-database-directory-where-json exact where --json
other_database_setting=other/beads.db
compare_real_database db-setting-other-beside-where exact where
other_database_setting=missing/beads.db
compare_real_database db-setting-missing-path-where exact where
other_database_setting=""
real_database_setup=add_other_workspace_with_setting_and_dotenv
compare_real_database db-setting-other-dotenv-where exact where
# Upstream rereads its JSON switch after that setup, from the config of the directory that the setting's path
# selects: `json` there decides, also against the current directory's config.yaml, and also when the setting
# comes from the user config.yaml and no workspace is found from the current directory.
other_json_setting=""
caller_json_setting=""
set_other_database_setting_with_json() {
	other_database_setting=other/.beads/beads.db
	set_other_database_setting "$1"
	other_database_setting=""
	if [[ -n "$other_json_setting" ]]; then
		printf 'json: %s\n' "$other_json_setting" >>"$1/work/other/.beads/config.yaml"
	fi
	if [[ -n "$caller_json_setting" ]]; then
		printf 'json: %s\n' "$caller_json_setting" >>"$1/work/.beads/config.yaml"
	fi
}
real_database_setup=set_other_database_setting_with_json
other_json_setting=true
compare_real_database db-setting-other-json-setting-where exact where
other_json_setting=""
caller_json_setting=true
compare_real_database db-setting-caller-json-setting-where exact where
caller_json_setting=""
user_database_setting_with_json() {
	mkdir "$1/work/elsewhere"
	mv -f "$1/work/.beads" "$1/work/elsewhere/.beads"
	printf 'json: true\n' >>"$1/work/elsewhere/.beads/config.yaml"
	mkdir -p "$1/user-home/.config/bd"
	printf 'db: %s/work/elsewhere/.beads/beads.db\n' "$1" >"$1/user-home/.config/bd/config.yaml"
}
real_database_setup=user_database_setting_with_json
compare_real_database db-setting-user-config-json-setting-where exact where
real_database_setup=""
real_database_read_only=""
# A command that opens a store reads the setting the same way before this build refuses the db setting.
other_json_setting=true
candidate_only_setup=set_other_database_setting_with_json
expect_candidate_failure db-setting-other-json-setting-count-unported \
	'{"error":"count is not available yet when the db setting names a database in this build","schema_version":1}' "" "" count
candidate_only_setup=""
other_json_setting=""
# A db setting that selects a workspace whose metadata.json does not decode: the setup of that directory prints the
# load warning, which names it as the setting's path gives it, and where stops with the load error.
break_other_metadata_with_setting() {
	other_database_setting=other/.beads/beads.db
	set_other_database_setting "$1"
	other_database_setting=""
	printf '{bad' >"$1/work/other/.beads/metadata.json"
}
real_database_read_only=1
real_database_setup=break_other_metadata_with_setting
compare_real_database db-setting-other-broken-metadata-where exact where
compare_real_database db-setting-other-broken-metadata-version stderr-only version
compare_real_database db-setting-other-broken-metadata-help-command exact help count
real_database_setup=""
real_database_read_only=""
# Before a refusal this build loads the same .env file, which can turn shared-server mode and JSON on:
# for a store command the directory that the BEADS_DB path or the db setting selects.
move_workspace_with_dotenv_selectors() {
	move_workspace_to_db "$1"
	printf 'BEADS_DOLT_SHARED_SERVER=1\nBD_JSON=1\n' >"$1/work/db/.beads/.env"
}
candidate_only_setup=move_workspace_with_dotenv_selectors
expect_beads_db_refusal beads-db-deeper-path-dotenv-json-unported BEADS_DB=db/.beads/missing/beads.db \
	'{"error":"count is not available yet when BEADS_DB names this path in this build","schema_version":1}' \
	"$shared_server_notice" count
expect_beads_db_refusal beads-db-where-deeper-path-dotenv-json-unported BEADS_DB=db/.beads/missing/beads.db \
	'{"error":"where is not available yet when BEADS_DB names this path in this build","schema_version":1}' \
	"$shared_server_notice" where
candidate_only_setup=add_other_workspace_with_setting_and_dotenv
store_refusal_notice="$shared_server_notice"
expect_store_refusal count-db-setting-other-dotenv-notice-unported "$database_reason" count count
store_refusal_notice=""
candidate_only_setup=""
# The json setting of that directory's config.yaml sets the output mode of the refusal too, as upstream's setup
# rereads it there (beadshx-m08-01.12).
move_workspace_with_json_setting() {
	move_workspace_to_db "$1"
	printf 'json: true\n' >>"$1/work/db/.beads/config.yaml"
}
candidate_only_setup=move_workspace_with_json_setting
expect_beads_db_refusal beads-db-deeper-path-json-setting-unported BEADS_DB=db/.beads/missing/beads.db \
	'{"error":"count is not available yet when BEADS_DB names this path in this build","schema_version":1}' "" count
expect_beads_db_refusal beads-db-where-deeper-path-json-setting-unported BEADS_DB=db/.beads/missing/beads.db \
	'{"error":"where is not available yet when BEADS_DB names this path in this build","schema_version":1}' "" where
expect_beads_db_refusal beads-db-where-bd-db-json-setting-unported BD_DB=db/.beads/ \
	'{"error":"where is not available yet when BD_DB names this path in this build","schema_version":1}' "" where
candidate_only_setup=""
# On macOS upstream's CanonicalizePath also takes each name's case from the file system. A path typed
# in another case then names the directory as stored where upstream derives it from the canonical
# path: in the config warning of the setup, and in the database path that `info` prints for BEADS_DB.
# These cases need a case-insensitive file system.
if [[ -d "$real_database_seed/WORK" ]]; then
	move_workspace_with_broken_config() {
		move_workspace_to_db "$1"
		printf '[a, b\n' >>"$1/work/db/.beads/config.yaml"
		# A user config.yaml loads first, so the error names the workspace config.yaml that follows.
		mkdir -p "$1/user-home/.config/bd"
		printf 'json: false\n' >"$1/user-home/.config/bd/config.yaml"
	}
	real_database_read_only=1
	real_database_setup=move_workspace_with_broken_config
	compare_beads_db beads-db-case-version stderr-only BEADS_DB=DB/.BEADS/embeddeddolt version
	compare_beads_db beads-db-case-absolute-help-command exact BEADS_DB='<work>/DB/.BEADS/embeddeddolt' help count
	real_database_setup=move_workspace_to_db
	compare_beads_db beads-db-case-info-json exact BEADS_DB=DB/.BEADS info --json
	# Upstream reads the workspace for a path typed in another case: FindDatabasePath canonicalizes a BEADS_DB path
	# before resolveCommandBeadsDir compares its names with .beads, and that comparison also takes the canonical
	# path's parent for where (beadshx-m08-01.12). A --db path names the same directory in where.
	compare_beads_db beads-db-case-database-count exact BEADS_DB=DB/.BEADS/embeddeddolt count
	compare_beads_db beads-db-case-absolute-database-list-json exact BEADS_DB='<work>/DB/.BEADS/embeddeddolt' list --json
	compare_beads_db beads-db-case-database-info-json exact BEADS_DB=DB/.BEADS/embeddeddolt info --json
	compare_beads_db beads-db-case-database-where exact BEADS_DB=DB/.BEADS/embeddeddolt where
	compare_beads_db beads-db-case-legacy-file-where-json exact BEADS_DB=DB/.BEADS/beads.db where --json
	compare_beads_db beads-db-case-bd-db-where-json exact BD_DB=DB/.BEADS/embeddeddolt where --json
	compare_beads_db db-flag-case-database-where exact BEADSHX_PARITY_EXTRA=1 --db DB/.BEADS/embeddeddolt where
	real_database_setup=""
	real_database_read_only=""
	# For a missing file upstream also creates a workspace gate lock named after the typed directory, here
	# work/db/.BEADS.gate.lock, so these cases skip the read-only check of the upstream side.
	real_database_setup=move_workspace_to_db
	compare_beads_db beads-db-case-legacy-file-count exact BEADS_DB=DB/.BEADS/beads.db count
	compare_beads_db beads-db-case-legacy-file-info-json exact BEADS_DB=DB/.BEADS/beads.db info --json
	real_database_setup=""
fi

# Each setup of the selected directory (upstream prepareSelectedCommandContext) runs
# config.CheckBeadsDirPermissions. When group or others have any permission bit on the directory, even
# only an execute bit, it prints "Warning: <dir> has permissions 0755 (recommended: 0700). Run: chmod
# 700 <dir>" on stderr, also with --json: the bits as four octal digits, and the directory as that
# setup names it. The warning comes after the setup's config warning, and before its shared-server
# notice or metadata.json warning. So it prints twice for where and for a command that reads the
# database, and once for version, the root help, `bd help`, a --db or BEADS_DB path, and a workspace
# without a database. A --help flag, a command group's help page and a flag error print none. bdhx
# writes nothing, and upstream writes nothing where the cases do not say otherwise.
real_database_read_only=1
real_database_beads_mode=755
compare_real_database beads-mode-0755-list exact list
compare_real_database beads-mode-0755-list-json exact list --json
compare_real_database beads-mode-0755-config-get-json exact config get issue_prefix --json
compare_real_database beads-mode-0755-where exact where
compare_real_database beads-mode-0755-where-json exact where --json
compare_real_database beads-mode-0755-version stderr-only version
compare_real_database beads-mode-0755-version-json stderr-only version --json
compare_real_database beads-mode-0755-root stderr-only
compare_real_database beads-mode-0755-help-command exact help list
compare_real_database beads-mode-0755-help-flag exact list --help
compare_real_database beads-mode-0755-command-group exact label
compare_real_database beads-mode-0755-flag-error exact ready -n x
real_database_beads_mode=750
compare_real_database beads-mode-0750-count exact count
compare_real_database beads-mode-0750-where exact where
real_database_beads_mode=770
compare_real_database beads-mode-0770-ready-json exact ready --json
real_database_beads_mode=711
compare_real_database beads-mode-0711-status exact status
compare_real_database beads-mode-0711-version stderr-only version
real_database_beads_mode=700
compare_real_database beads-mode-0700-count exact count
compare_real_database beads-mode-0700-where-json exact where --json
# A --db path names the directory as given, also for where. A --db value that names a database finds
# the workspace as without --db. BEADS_DB makes a command that reads the database name the directory
# by its absolute path with symbolic links resolved, or by the absolute path of a missing file's
# directory; where and version take a BEADS_DB or BD_DB path as given.
real_database_beads_mode=755
compare_real_database beads-mode-db-path-count exact --db .beads/embeddeddolt count
compare_real_database beads-mode-db-path-list-json exact --db .beads list --json
compare_real_database beads-mode-db-path-where exact --db .beads where
compare_real_database beads-mode-db-path-version stderr-only --db .beads/beads.db version
compare_real_database beads-mode-db-name-count exact --db other count
real_database_setup=move_workspace_to_db
compare_beads_db beads-mode-beads-db-count exact BEADS_DB=db/.beads count
compare_beads_db beads-mode-beads-db-embedded-list-json exact BEADS_DB=db/.beads/embeddeddolt list --json
compare_beads_db beads-mode-beads-db-file-info-json exact BEADS_DB=db/.beads/beads.db info --json
compare_beads_db beads-mode-beads-db-where exact BEADS_DB=db/.beads where
compare_beads_db beads-mode-bd-db-where-json exact BD_DB=db/.beads where --json
compare_beads_db beads-mode-bd-db-version stderr-only BD_DB=db/.beads/embeddeddolt version
# A db setting names the directory as its path gives it. The body of where then sets up the directory
# that BEADS_DIR names, which upstream's pre-run set to it, by its absolute path.
set_beads_database_setting() {
	printf 'db: .beads/beads.db\n' >>"$1/work/.beads/config.yaml"
}
real_database_setup=set_beads_database_setting
compare_real_database beads-mode-db-setting-where exact where
compare_real_database beads-mode-db-setting-version stderr-only version
compare_real_database beads-mode-db-setting-help-command exact help count
# For a .beads directory that is a symbolic link, a command that reads the database names the link
# first, and then the target, which it binds the database from.
link_beads_directory() {
	mv -f "$1/work/.beads" "$1/work/beads-target"
	ln -s beads-target "$1/work/.beads"
}
real_database_setup=link_beads_directory
compare_real_database beads-mode-link-version stderr-only version
# The body of where finds the workspace through BEADS_DIR, which names the link: its second setup and
# the path it prints name the target. With -C, BEADS_DIR names the link before the pre-run, so both setups
# name the target.
compare_real_database beads-mode-link-where exact where
compare_real_database beads-mode-link-where-json exact where --json
compare_real_database beads-mode-link-change-directory-where exact -C . where
# Upstream also writes here: it creates a gate lock beside the link's target, which bdhx does not take.
real_database_read_only=""
compare_real_database beads-mode-link-count exact count
compare_real_database beads-mode-link-list-json exact list --json
real_database_read_only=1
# A redirect selects its target, which upstream checks instead of the redirecting directory.
redirect_to_loose_workspace() {
	mkdir "$1/work/sub"
	mv -f "$1/work/.beads" "$1/work/sub/.beads"
	chmod 750 "$1/work/sub/.beads"
	mkdir "$1/work/.beads"
	printf 'sub/.beads\n' >"$1/work/.beads/redirect"
}
real_database_setup=redirect_to_loose_workspace
compare_real_database beads-mode-redirect-count exact count
compare_real_database beads-mode-redirect-where exact where
# The order of the warnings in each setup.
real_database_setup=break_workspace_config
compare_real_database beads-mode-config-warning-count exact count
compare_real_database beads-mode-config-warning-where-json exact where --json
real_database_setup=enable_shared_server
compare_real_database beads-mode-shared-server-where exact where
compare_real_database beads-mode-shared-server-version stderr-only version
break_metadata_json() {
	printf '{not json' >"$1/work/.beads/metadata.json"
}
real_database_setup=break_metadata_json
compare_real_database beads-mode-bad-metadata-count exact count
compare_real_database beads-mode-bad-metadata-where exact where
real_database_setup=remove_embedded_database
compare_real_database beads-mode-no-database-list exact list
compare_real_database beads-mode-no-database-count-json exact count --json
real_database_setup=""
# Upstream's show also writes the issue ID into .beads/last-touched; bdhx does not.
real_database_read_only=""
compare_real_database beads-mode-0755-show-json exact show "$real_database_issue_id" --json
real_database_read_only=1
# Upstream reads the database that the db setting names, where this build refuses after the warning.
candidate_only_setup=set_beads_database_setting
expect_candidate_failure beads-mode-db-setting-count-unported "" \
	'Warning: .beads has permissions 0755 (recommended: 0700). Run: chmod 700 .beads'$'\n''Error: count is not available yet when the db setting names a database in this build' "" \
	count
candidate_only_setup=""
real_database_beads_mode=700
real_database_read_only=""
# A server that upstream cannot reach fails after both setups; a missing embedded store after one.
store_failure_beads_mode=755
compare_store_failure unavailable-server beads-mode-0755-list list
compare_store_failure unavailable-server beads-mode-0755-count-json count --json
compare_store_failure missing-embedded beads-mode-0755-ready ready
store_failure_beads_mode=700
# Without a workspace, a --db path selects its directory, which group and others can read here.
make_loose_data_directory() {
	mkdir -m 755 "$1/work/data"
}
no_workspace_setup=make_loose_data_directory
compare_no_workspace beads_mode_db_path_where where --db data/x
compare_no_workspace beads_mode_db_path_where_json where --db data/x --json
compare_no_workspace beads_mode_db_path_help_command help list --db data/x
no_workspace_setup=""

# Schema skew. Upstream's store open compares the highest schema_migrations version with the
# binary's latest migration, v65, before any command body runs. A database ahead of the binary
# stops every store command: upstream prints its "binary is stale" block on stderr, or that error
# as JSON on stderr under --json, and exits 1. The strict read-only open (--readonly) also stops a
# database behind the binary, with a plain open error in every mode, and so does every open in this
# build, which never migrates. `where` prints no stored prefix that it cannot read, and `version`
# opens nothing. BD_IGNORE_SCHEMA_SKEW=1, or --ignore-schema-skew, warns instead and reads.
schema_ahead_sql="INSERT INTO schema_migrations (version) VALUES (66)"
schema_far_ahead_sql=$'INSERT INTO schema_migrations (version) VALUES (66)\nINSERT INTO schema_migrations (version) VALUES (68)'
schema_behind_sql="DELETE FROM schema_migrations WHERE version = 65"
# Each entry is a case name, then the command. The native facade commands open the store the same
# way, so list and count stand for them.
schema_skew_commands=(
	"comments:comments $real_database_issue_id"
	"comments-json:comments $real_database_issue_id --json"
	"history:history $real_database_issue_id"
	"dep-list:dep list $real_database_issue_id"
	"dep-tree:dep tree $real_database_issue_id"
	"dep-cycles:dep cycles"
	"blocked:blocked"
	"ready-explain:ready --explain"
	"graph:graph $real_database_issue_id"
	"events-tail:events tail"
	"types:types"
	"statuses:statuses"
	"config-get:config get issue_prefix"
	"config-list-json:config list --json"
	"stale-json:stale --days 1 --json"
	"show:show $real_database_issue_id"
	"show-json:show $real_database_issue_id --json"
	"list:list"
	"count-json:count --json"
)
real_database_read_only=1
for schema_entry in "${schema_skew_commands[@]}"; do
	schema_case="${schema_entry%%:*}"
	read -r -a schema_arguments <<<"${schema_entry#*:}"
	compare_real_database_sql "schema-ahead-$schema_case" exact "$schema_ahead_sql" "${schema_arguments[@]}"
	compare_real_database_sql "schema-behind-readonly-$schema_case" exact "$schema_behind_sql" \
		--readonly "${schema_arguments[@]}"
done
compare_real_database_sql schema-far-ahead-comments exact "$schema_far_ahead_sql" comments "$real_database_issue_id"
# The pre-run open comes before the checks of the command body, which the read in this build follows.
compare_real_database_sql schema-ahead-show-without-id exact "$schema_ahead_sql" show
compare_real_database_sql schema-ahead-dep-tree-bad-direction exact "$schema_ahead_sql" \
	dep tree "$real_database_issue_id" --direction bogus
compare_real_database_sql schema-behind-readonly-list-bad-sort-json exact "$schema_behind_sql" --readonly list --sort bogus --json
real_database_extra_env=(BD_JSON_ENVELOPE=1)
compare_real_database_sql schema-ahead-envelope-dep-list-json exact "$schema_ahead_sql" dep list "$real_database_issue_id" --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_extra_config='json: true'
compare_real_database_sql schema-ahead-json-setting-types exact "$schema_ahead_sql" types
real_database_extra_config=""
# Dolt reads no row from an empty cursor table, and the behind check reports that read, as it does
# for a missing table.
compare_real_database_sql schema-empty-readonly-comments exact "DELETE FROM schema_migrations" \
	--readonly comments "$real_database_issue_id"
compare_real_database_sql schema-missing-readonly-comments exact "DROP TABLE schema_migrations" \
	--readonly comments "$real_database_issue_id"
compare_real_database_sql schema-missing-readonly-count exact "DROP TABLE schema_migrations" --readonly count
# A cursor that the version read cannot scan stops every open. Upstream's plain open (without strict
# read-only mode) reports it from its schema initialization, which names itself: "embeddeddolt: init
# schema: schema skew check: ...". The strict read-only open reports the check's error alone.
schema_broken_sql=$'ALTER TABLE schema_migrations MODIFY version VARCHAR(32) NOT NULL\nINSERT INTO schema_migrations (version) VALUES (\'x\')'
compare_real_database_sql schema-broken-readonly-count exact "$schema_broken_sql" --readonly count
compare_real_database_sql schema-broken-count exact "$schema_broken_sql" count
compare_real_database_sql schema-broken-count-json exact "$schema_broken_sql" count --json
compare_real_database_sql schema-broken-comments exact "$schema_broken_sql" comments "$real_database_issue_id"
compare_real_database_sql schema-broken-show-json exact "$schema_broken_sql" show "$real_database_issue_id" --json
compare_real_database_sql schema-broken-list exact "$schema_broken_sql" list
compare_real_database_sql schema-broken-dep-tree exact "$schema_broken_sql" dep tree "$real_database_issue_id"
compare_real_database_sql schema-broken-info exact "$schema_broken_sql" info
compare_real_database_sql schema-broken-info-whats-new exact "$schema_broken_sql" info --whats-new
compare_real_database_sql schema-broken-readonly-info-whats-new exact "$schema_broken_sql" --readonly info --whats-new
compare_real_database_sql schema-broken-where exact "$schema_broken_sql" where
real_database_extra_config='readonly: true'
compare_real_database_sql schema-broken-readonly-setting-comments exact "$schema_broken_sql" comments "$real_database_issue_id"
compare_real_database_sql schema-broken-readonly-false-comments exact "$schema_broken_sql" \
	--readonly=false comments "$real_database_issue_id"
real_database_extra_config=""
real_database_extra_env=(BD_READONLY=1)
compare_real_database_sql schema-broken-env-readonly-list exact "$schema_broken_sql" list
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database_sql schema-broken-ignored-dep-list exact "$schema_broken_sql" dep list "$real_database_issue_id"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# info --whats-new reads nothing, but upstream's pre-run opens the store first, so the check stops it too.
compare_real_database_sql schema-ahead-info-whats-new exact "$schema_ahead_sql" info --whats-new
compare_real_database_sql schema-ahead-info-whats-new-json exact "$schema_ahead_sql" info --whats-new --json
compare_real_database_sql schema-behind-readonly-info-whats-new exact "$schema_behind_sql" --readonly info --whats-new
compare_real_database_sql schema-ahead-info-thanks exact "$schema_ahead_sql" info --thanks
compare_real_database_sql schema-ahead-info-thanks-json exact "$schema_ahead_sql" info --thanks --json
compare_real_database_sql schema-behind-readonly-info-thanks exact "$schema_behind_sql" --readonly info --thanks
compare_real_database_sql schema-broken-info-thanks exact "$schema_broken_sql" info --thanks
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database_sql schema-ahead-ignored-info-whats-new exact "$schema_ahead_sql" --readonly info --whats-new
compare_real_database_sql schema-behind-ignored-info-whats-new-json exact "$schema_behind_sql" \
	--readonly info --whats-new --json
compare_real_database_sql schema-ahead-ignored-info-thanks thanks-page "$schema_ahead_sql" --readonly info --thanks
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
for schema_sql in "$schema_ahead_sql" "$schema_behind_sql"; do
	schema_case=ahead
	[[ "$schema_sql" == "$schema_behind_sql" ]] && schema_case=behind
	compare_real_database_sql "schema-$schema_case-where" exact "$schema_sql" where
	compare_real_database_sql "schema-$schema_case-where-json" exact "$schema_sql" --readonly where --json
	compare_real_database_sql "schema-$schema_case-version" stderr-only "$schema_sql" version
	real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
	compare_real_database_sql "schema-$schema_case-ignored-comments" exact "$schema_sql" \
		--readonly comments "$real_database_issue_id"
	compare_real_database_sql "schema-$schema_case-ignored-where" exact "$schema_sql" where
	compare_real_database_sql "schema-$schema_case-ignored-count" exact "$schema_sql" --readonly count
	compare_real_database_sql "schema-$schema_case-ignored-stale" exact "$schema_sql" --readonly stale --days 1
	# Upstream checks once, at the store open of the pre-run, however many reads the command makes
	# after it: the two counts of a grouped count, the custom statuses that search --status reads
	# first, the parent of each ready issue, the list reads of a --parent tree, and the later
	# reads of ready --gated, --mol and --explain.
	compare_real_database_sql "schema-$schema_case-ignored-count-by-label-json" exact "$schema_sql" \
		--readonly count --by-label --json
	compare_real_database_sql "schema-$schema_case-ignored-search-status" exact "$schema_sql" \
		--readonly search parity --status open
	compare_real_database_sql "schema-$schema_case-ignored-query-predicate-json" exact "$schema_sql" \
		--readonly query 'status=open OR priority=0' --json
	compare_real_database_sql "schema-$schema_case-ignored-ping" ping-human "$schema_sql" --readonly ping
	compare_real_database_sql "schema-$schema_case-ignored-ping-json" ping-json "$schema_sql" --readonly ping --json
	compare_real_database_sql "schema-$schema_case-ignored-ready" exact "$schema_sql" --readonly ready
	compare_real_database_sql "schema-$schema_case-ignored-children" exact "$schema_sql" \
		--readonly children "$real_database_epic_id"
	compare_real_database_sql "schema-$schema_case-ignored-list-parent" exact "$schema_sql" \
		--readonly list --parent "$real_database_epic_id"
	compare_real_database_sql "schema-$schema_case-ignored-ready-gated" exact "$schema_sql" --readonly ready --gated
	compare_real_database_sql "schema-$schema_case-ignored-ready-mol" exact "$schema_sql" \
		--readonly ready --mol "$real_database_molecule_id"
	compare_real_database_sql "schema-$schema_case-ignored-ready-explain" exact "$schema_sql" --readonly ready --explain
	compare_real_database_sql "schema-$schema_case-ignored-ready-explain-json" exact "$schema_sql" \
		--readonly ready --explain --json
	real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
	compare_real_database_sql "schema-$schema_case-flag-ignored-dep-list" exact "$schema_sql" \
		--readonly --ignore-schema-skew dep list "$real_database_issue_id"
	compare_real_database_sql "schema-$schema_case-flag-ignored-list" exact "$schema_sql" \
		--readonly --ignore-schema-skew list
	compare_real_database_sql "schema-$schema_case-flag-false-comments" exact "$schema_sql" \
		--readonly --ignore-schema-skew=false comments "$real_database_issue_id"
done
real_database_read_only=""
# Without --readonly upstream migrates a database that is behind; this build refuses as the strict
# read-only open does and leaves the database unchanged.
schema_behind_refusal="Error: failed to open database: schema version mismatch: database is at v64, binary expects v65, and the read-only open cannot migrate it; run any bd write command in that workspace to migrate, or set BD_IGNORE_SCHEMA_SKEW=1 to read anyway (queries touching newer schema may fail)"
expect_candidate_failure schema-behind-comments-refused "" "$schema_behind_refusal" "$schema_behind_sql" \
	comments "$real_database_issue_id"
expect_candidate_failure schema-behind-show-json-refused "" "$schema_behind_refusal" "$schema_behind_sql" \
	show "$real_database_issue_id" --json
expect_candidate_failure schema-behind-list-refused "" "$schema_behind_refusal" "$schema_behind_sql" list

# show records the issue in .beads/last-touched, so it compares without the read-only check. Upstream
# checks once, at the store open of the pre-run, however many issues show reads after it: each issue of
# show with more than one ID, each message of a --thread, and the dependents of each issue of --refs
# and --children.
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database_sql schema-ahead-ignored-show exact "$schema_ahead_sql" show "$real_database_issue_id"
compare_real_database_sql schema-behind-ignored-readonly-show-json exact "$schema_behind_sql" --readonly show "$real_database_issue_id" --json
for schema_sql in "$schema_ahead_sql" "$schema_behind_sql"; do
	schema_case=ahead
	[[ "$schema_sql" == "$schema_behind_sql" ]] && schema_case=behind
	compare_real_database_sql "schema-$schema_case-ignored-show-several" exact "$schema_sql" \
		--readonly show "$real_database_epic_id" "$real_database_child_id"
	compare_real_database_sql "schema-$schema_case-ignored-show-several-json" exact "$schema_sql" \
		--readonly show "$real_database_epic_id" "$real_database_child_id" "$real_database_issue_id" --include-dependents --json
	compare_real_database_sql "schema-$schema_case-ignored-show-thread" exact "$schema_sql" --readonly show test-msg-leaf --thread
	compare_real_database_sql "schema-$schema_case-ignored-show-thread-json" exact "$schema_sql" \
		--readonly show test-msg-leaf --thread --json
	# Upstream prints the --refs and --children blocks of two IDs from a Go map
	# (cmd/bd/show_refs.go:54), so compare their lines as a multiset; stderr stays exact.
	compare_real_database_sql "schema-$schema_case-ignored-show-refs" show-grouped-multi "$schema_sql" \
		--readonly show --refs "$real_database_child_id" "$real_database_epic_id"
	compare_real_database_sql "schema-$schema_case-ignored-show-children" show-grouped-multi "$schema_sql" \
		--readonly show --children "$real_database_epic_id" "$real_database_child_id"
done
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)

# An embedded list reads its page, and the blocking notes of the flat view, with Haxe-owned SQL, so it
# never opens the native store. That open would run upstream's config package, which logs its load of
# config.yaml under BD_DEBUG. bdhx prints no debug lines itself, so an empty stderr shows no native open.
real_database_extra_env=(BD_DEBUG=1)
candidate_only_exit=0
# The two abbreviation issues share a priority, so list, search and query order them by creation time,
# newest first, and then by ID. The seed creates them one after the other, often within one second, so
# these exact expectations pin their creation times: test-abcd22 is the newer one.
abbreviation_order_sql="UPDATE issues SET created_at = '2026-08-21 10:00:00', updated_at = updated_at WHERE id = 'test-abcd11';
UPDATE issues SET created_at = '2026-08-21 10:00:01', updated_at = updated_at WHERE id = 'test-abcd22';"
expect_candidate_failure embedded-list-flat-without-native-open \
	$'○ test-abcd22 [P2] [task] - Ambiguous abbreviation issue (blocks: test-abcd11)\n● test-abcd11 [P2] [task] - Unique abbreviation issue (blocked by: test-abcd22)' \
	"" "$abbreviation_order_sql" --readonly list --flat --id test-abcd11,test-abcd22
# So does ready, also for an empty page, which then reads whether any issue is open, and a list --ready page.
expect_candidate_failure embedded-ready-empty-without-native-open \
	$'\n✨ No ready work found (all issues have blocking dependencies)' "" "" --readonly ready --assignee nobody
expect_candidate_failure embedded-list-ready-without-native-open "[]" "" "" --readonly list --ready --assignee nobody --json
# So do count, also grouped, search, and query, which reads every issue and wisp as its candidates.
expect_candidate_failure embedded-count-without-native-open "2" "" "" --readonly count --id test-abcd11,test-abcd22
expect_candidate_failure embedded-count-by-label-without-native-open \
	'{"groups":[{"count":2,"group":"(no labels)"}],"schema_version":1,"total":2}' "" "" \
	--readonly count --id test-abcd11,test-abcd22 --by-label --json
expect_candidate_failure embedded-search-without-native-open \
	$'Found 2 issues matching \'abbreviation\':\ntest-abcd22 [P2] [task] open - Ambiguous abbreviation issue\ntest-abcd11 [P2] [task] open - Unique abbreviation issue' \
	"" "$abbreviation_order_sql" --readonly search abbreviation
expect_candidate_failure embedded-query-without-native-open \
	$'Found 2 issues:\n○ test-abcd22 [P2] [task] - Ambiguous abbreviation issue\n○ test-abcd11 [P2] [task] - Unique abbreviation issue' \
	"" "$abbreviation_order_sql" --readonly query title=abbreviation
candidate_only_exit=1
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)

# A server-mode workspace checks the schema only through its server, which does not answer here. An
# embedded store that the workspace still holds, even one ahead of the binary, changes nothing: upstream
# never opens it, and the escape hatch changes nothing either.
store_failure_skewed_seed="$test_root/store-failure-skewed-seed"
copy_fixture_tree "$real_database_seed/work" "$store_failure_skewed_seed"
printf '%s\n' "$schema_ahead_sql" | "$fixture_sql" "$store_failure_skewed_seed" >/dev/null
hold_skewed_embedded_store() {
	local root="$1"
	local database
	database="$(jq -er '.dolt_database' "$store_failure_skewed_seed/.beads/metadata.json")"
	copy_fixture_tree "$store_failure_skewed_seed/.beads/embeddeddolt" "$root/work/.beads/embeddeddolt"
	# Rewrite metadata.json in place, so the file keeps its mode.
	jq --arg database "$database" '.dolt_database = $database' "$root/work/.beads/metadata.json" >"$root/metadata.json"
	cat "$root/metadata.json" >"$root/work/.beads/metadata.json"
	rm -f "$root/metadata.json"
}
store_failure_setup=hold_skewed_embedded_store
compare_store_failure unavailable-server skewed-store-comments comments test-1
compare_store_failure unavailable-server skewed-store-show-json show test-1 --json
compare_store_failure unavailable-server skewed-store-list list
compare_store_failure unavailable-server skewed-store-count-json count --json
compare_store_failure unavailable-server skewed-store-readonly-dep-tree --readonly dep tree test-1
compare_store_failure unavailable-server skewed-store-info-whats-new info --whats-new
store_failure_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_store_failure unavailable-server skewed-store-ignored-comments comments test-1
compare_store_failure unavailable-server skewed-store-ignored-list-json list --json
store_failure_extra_env=(BEADSHX_PARITY_EXTRA=1)
store_failure_setup=""
compare_store_failure unavailable-server flag-ignored-show --ignore-schema-skew show test-1
compare_store_failure redirect-proxied-server flag-ignored-readonly-count --readonly --ignore-schema-skew count
store_failure_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_store_failure redirect-proxied-server ignored-global-list-json --global list --json
store_failure_extra_env=(BEADSHX_PARITY_EXTRA=1)

# The remote-migrate gate (#4259). Without strict read-only mode, upstream's store open runs this gate on a
# database behind the binary before it migrates. With a Dolt remote it refuses the migration: the commands
# in upstream's readOnlyCommands warn and read the database as it is, and every other store command stops
# with the gate's message (or its JSON error on stderr). The smart gate reads only the cached
# remote-tracking ref remotes/origin/main and tailors the stop; where it can prove a migration or a
# fast-forward safe, upstream writes, and this build refuses instead. Each setup adds a Dolt remote in the
# case's own directory (file://, never the network) and pushes to it where the scenario needs a cached ref.
gate_add_remote="CALL DOLT_REMOTE('add', 'origin', '@REMOTE@')"
gate_scratch_branch=("CALL DOLT_CHECKOUT('-b', 'scratch')" "INSERT INTO config (\`key\`, value) VALUES ('beadshx.scratch', '1')")
gate_sql() {
	local root="$1"
	shift
	mkdir -p "$root/dolt-remote"
	printf '%s\n' "$@" | sed "s|@REMOTE@|file://$root/dolt-remote|g" | "$fixture_sql" "$root/work" >/dev/null
}
gate_without_cached_ref() { gate_sql "$1" "$schema_behind_sql" "$gate_add_remote"; }
gate_remote_ahead() { gate_sql "$1" "$gate_add_remote" "CALL DOLT_PUSH('origin', 'main')" "$schema_behind_sql"; }
gate_fork_skew() {
	gate_sql "$1" "$gate_add_remote" "CALL DOLT_PUSH('origin', 'main')" "$schema_behind_sql" \
		"UPDATE schema_migrations SET content_hash = REPEAT('0', 64) WHERE version IN (7, 12)"
}
gate_remote_behind() {
	gate_sql "$1" "DELETE FROM schema_migrations WHERE version > 63" "CALL DOLT_COMMIT('-Am', 'at v63')" "$gate_add_remote" \
		"CALL DOLT_PUSH('origin', 'main')" \
		"INSERT INTO schema_migrations SELECT version, content_hash FROM schema_migrations AS OF 'main~1' WHERE version = 64"
}
# HEAD and the cached remote at the same version: a first mover, which upstream migrates at or above v43.
gate_remote_level() {
	gate_sql "$1" "DELETE FROM schema_migrations WHERE version > $2" "CALL DOLT_COMMIT('-Am', 'local')" "$gate_add_remote" \
		"CALL DOLT_PUSH('origin', 'main')" "${gate_scratch_branch[@]}"
}
gate_remote_level_64() { gate_remote_level "$1" 64; }
gate_remote_level_42() { gate_remote_level "$1" 42; }
# HEAD one commit behind the cached remote with a clean working set, so it can fast-forward. The fixture
# tool's own commit lands on a scratch branch.
gate_remote_one_ahead() {
	gate_sql "$1" "DELETE FROM schema_migrations WHERE version > $2" "CALL DOLT_COMMIT('-Am', 'local')" \
		"CALL DOLT_CHECKOUT('-b', 'remote-state')" \
		"INSERT INTO schema_migrations SELECT version, content_hash FROM schema_migrations AS OF 'main~1' WHERE version = $(($2 + 1))" \
		"CALL DOLT_COMMIT('-Am', 'remote')" "$gate_add_remote" "CALL DOLT_PUSH('origin', 'remote-state:main')" \
		"CALL DOLT_CHECKOUT('main')" "${gate_scratch_branch[@]}"
}
gate_remote_one_ahead_63() { gate_remote_one_ahead "$1" 63; }
gate_remote_one_ahead_64() { gate_remote_one_ahead "$1" 64; }
real_database_read_only=1
real_database_setup=gate_without_cached_ref
compare_real_database gate-types exact types
compare_real_database gate-types-json exact types --json
compare_real_database gate-dep-tree exact dep tree "$real_database_issue_id"
compare_real_database gate-history exact history "$real_database_issue_id"
compare_real_database gate-config-get exact config get issue_prefix
compare_real_database gate-info exact info
compare_real_database gate-info-thanks exact info --thanks
compare_real_database gate-status exact status
compare_real_database gate-stale-json exact stale --json
compare_real_database gate-children exact children "$real_database_issue_id"
compare_real_database gate-where exact where
real_database_extra_env=(BD_JSON_ENVELOPE=1)
compare_real_database gate-envelope-statuses-json exact statuses --json
real_database_extra_env=(BD_SMART_GATE=0)
compare_real_database gate-smart-off-types exact types
real_database_extra_env=(BD_SMART_GATE=maybe)
compare_real_database gate-smart-unparseable-types exact types
compare_real_database gate-smart-unparseable-types-json exact types --json
real_database_extra_env=(BD_ALLOW_REMOTE_MIGRATE=maybe)
compare_real_database gate-allow-unparseable-types exact types
real_database_extra_env=(BD_ALLOW_REMOTE_MIGRATE=false)
compare_real_database gate-allow-false-types exact types
# The schema skew escape hatch skips only the checks of the strict read-only open, not the gate.
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database gate-ignored-types exact types
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
# Strict read-only mode opens without the gate and refuses the database behind the binary.
compare_real_database gate-readonly-types exact --readonly types
compare_real_database gate-readonly-comments exact --readonly comments "$real_database_issue_id"
real_database_extra_config='readonly: true'
compare_real_database gate-readonly-setting-dep-list exact dep list "$real_database_issue_id"
real_database_extra_config=""
# The commands in readOnlyCommands, by cobra's leaf name, warn and read.
compare_real_database gate-comments exact comments "$real_database_issue_id"
compare_real_database gate-comments-json exact comments "$real_database_issue_id" --json
compare_real_database gate-blocked exact blocked
compare_real_database gate-graph exact graph "$real_database_issue_id"
compare_real_database gate-dep-list exact dep list "$real_database_issue_id"
compare_real_database gate-label-list exact label list "$real_database_bug_id"
# An issue with dependencies too: its detail read is Haxe-owned in an embedded workspace.
compare_real_database gate-label-list-related exact label list "$real_database_issue_id"
compare_real_database gate-events-tail exact events tail
compare_real_database gate-events-export exact events export
compare_real_database gate-config-list exact config list
compare_real_database gate-config-show exact config show
# count, search, query and ping read an embedded workspace with Haxe-owned SQL too.
compare_real_database gate-count exact count
compare_real_database gate-count-json exact count --json
compare_real_database gate-count-by-label exact count --by-label
compare_real_database gate-count-include-infra-by-type-json exact count --include-infra --by-type --json
compare_real_database gate-search exact search parity
compare_real_database gate-search-json exact search parity --json
compare_real_database gate-search-status exact search parity --status open --sort title
compare_real_database gate-query exact query status=open
compare_real_database gate-query-json exact query status=open --json
compare_real_database gate-query-predicate exact query 'status=open OR status=in_progress' --reverse
compare_real_database gate-ping ping-human ping
compare_real_database gate-ping-json ping-json ping --json
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database gate-ignored-comments exact comments "$real_database_issue_id"
compare_real_database gate-ignored-count exact count
compare_real_database gate-ignored-count-by-status-json exact count --by-status --json
compare_real_database gate-ignored-search exact search parity --long
compare_real_database gate-ignored-query-json exact query 'priority>=0' --all --json
compare_real_database gate-ignored-ping ping-human ping
# The native facade's strict open would read under the escape hatch; the gate runs before it.
compare_real_database gate-ignored-status exact status
compare_real_database gate-ignored-info-json exact info --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=gate_remote_ahead
compare_real_database gate-adopt-types exact types
compare_real_database gate-adopt-types-json exact types --json
compare_real_database gate-adopt-comments exact comments "$real_database_issue_id"
real_database_extra_env=(BD_SMART_GATE=maybe)
compare_real_database gate-adopt-smart-unparseable-types exact types
real_database_extra_env=(BD_ALLOW_REMOTE_MIGRATE=maybe)
compare_real_database gate-adopt-allow-unparseable-types exact types
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
real_database_setup=gate_remote_one_ahead_63
compare_real_database gate-adopt-ff-types exact types
compare_real_database gate-adopt-ff-types-json exact types --json
compare_real_database gate-adopt-ff-blocked exact blocked
real_database_setup=gate_fork_skew
compare_real_database gate-fork-skew-types exact types
compare_real_database gate-fork-skew-types-json exact types --json
compare_real_database gate-fork-skew-comments exact comments "$real_database_issue_id"
real_database_setup=gate_remote_level_42
compare_real_database gate-below-floor-types exact types
compare_real_database gate-below-floor-types-json exact types --json
real_database_setup=gate_remote_behind
compare_real_database gate-remote-behind-types exact types
real_database_read_only=""
# show records the issue in .beads/last-touched, so it compares without the read-only check. It reads an
# issue with dependencies, and the dependents of --refs and --children, as upstream does too.
real_database_setup=gate_without_cached_ref
# An embedded list and ready read with Haxe-owned SQL too, so they warn and read on as upstream does,
# also with the escape hatch.
compare_real_database gate-list exact list
compare_real_database gate-ready exact ready
compare_real_database gate-ready-json exact ready --json
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
compare_real_database gate-ignored-list exact list
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
compare_real_database gate-show exact show "$real_database_bug_id"
compare_real_database gate-show-related exact show "$real_database_issue_id"
compare_real_database gate-show-related-json exact show "$real_database_epic_id" --json --include-dependents
compare_real_database gate-show-refs exact show --refs "$real_database_child_id"
compare_real_database gate-show-children exact show --children "$real_database_epic_id"
real_database_setup=""

# A list --format template that needs upstream's Go types still reads through the native facade, whose
# strict read-only open cannot read a database behind the binary. It prints upstream's warning, then
# refuses, also under the escape hatch.
gate_read_warning=$(
	cat <<'EOF'
Warning: refusing to auto-apply 1 pending schema migration to a remote-backed database (v64 -> v65): migrating clones independently forks the schema (#4259)
  Read-only command: continuing on schema v64 without migrating.
  Writes are blocked until the schema is reconciled.  This is a
  coordination decision, not an auto-fix - do NOT run a migration unless
  you are the single designated migrator (only ONE clone may migrate a
  shared remote, else the schema forks; #4259):
    • designated migrator (only ONE machine): bd migrate --force && bd dolt push
    • every other clone (another already migrated): bd bootstrap
    • several machines: only ONE migrates; sync each other clone and run
      bd dolt pull after the migrator pushes, before upgrading it
EOF
)
gate_read_refusal() { printf '%s\nError: %s is not available yet on a database behind the binary in this build' "$gate_read_warning" "$1"; }
gate_native_template='--format={{printf "%T" .Type}}'
candidate_only_setup=gate_without_cached_ref
expect_candidate_failure gate-list-native-template-refused "" "$(gate_read_refusal list)" "" list "$gate_native_template"
real_database_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
expect_candidate_failure gate-ignored-list-native-template-refused "" "$(gate_read_refusal list)" "" list "$gate_native_template"
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=""

# Where upstream writes (BD_ALLOW_REMOTE_MIGRATE=1 or a first mover migrates, or a clean clone one commit
# behind a remote at v65 fast-forwards), this build refuses and leaves the database unchanged.
gate_migrate_refusal() { printf 'Error: %s is not available yet where upstream would migrate a database with a Dolt remote in this build' "$1"; }
candidate_only_setup=gate_without_cached_ref
real_database_extra_env=(BD_ALLOW_REMOTE_MIGRATE=1)
expect_candidate_failure gate-allow-types-refused "" "$(gate_migrate_refusal types)" "" types
expect_candidate_failure gate-allow-comments-refused "" "$(gate_migrate_refusal comments)" "" comments "$real_database_issue_id"
expect_candidate_failure gate-allow-types-json-refused \
	'{"error":"types is not available yet where upstream would migrate a database with a Dolt remote in this build","schema_version":1}' "" "" \
	types --json
real_database_extra_env=(BEADSHX_PARITY_EXTRA=1)
candidate_only_setup=gate_remote_level_64
expect_candidate_failure gate-first-mover-types-refused "" "$(gate_migrate_refusal types)" "" types
expect_candidate_failure gate-first-mover-list-refused "" "$(gate_migrate_refusal list)" "" list
candidate_only_setup=gate_remote_one_ahead_64
expect_candidate_failure gate-fast-forward-types-refused "" \
	"Error: types is not available yet where upstream would fast-forward a database with a Dolt remote in this build" "" types
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

# Waits until the file holds the line `value` at least `count` times.
wait_for_watch_count() {
	local file="$1"
	local value="$2"
	local count="$3"
	for _ in {1..200}; do
		if [[ "$(grep -Fc "$value" "$file" || true)" -ge "$count" ]]; then
			return 0
		fi
		sleep 0.05
	done
	printf 'watch output did not contain %q %s times\n' "$value" "$count" >&2
	return 1
}

watch_case_count=0
# Statements that each side's fixture gets before its watch starts, and more environment for both sides.
watch_extra_sql=""
watch_extra_env=(BEADSHX_PARITY_EXTRA=1)

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
		if [[ -n "$watch_extra_sql" ]]; then
			printf '%s\n' "$watch_extra_sql" | "$fixture_sql" "$state_root/work" >/dev/null
		fi
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
				"${watch_extra_env[@]}" \
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
			# Each side writes at its own time, and show prints the date of updated_at, so a clock write
			# differs when the two writes fall on each side of midnight UTC. The write sets a fixed
			# updated_at instead; the watch sees the new value and refreshes.
			printf "UPDATE issues SET title = 'Updated watch parity issue', updated_at = '2030-01-02 03:04:05' WHERE id = '%s'\n" \
				"$real_database_content_id" | "$fixture_sql" "$state_root/work" >/dev/null
			wait_for_watch_text "$case_root/$side.stdout" 'Updated watch parity issue'
			# The new view ends when the watch prints its prompt again. An interrupt before that cancels
			# upstream's later reads of the view, such as its dependencies.
			wait_for_watch_count "$case_root/$side.stderr" 'Watching for changes' 2
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
		gate-held)
			# The watch holds both gates shared: an exclusive try would wait, and a shared one does not.
			for lock in .beads.gate.lock .beads/embeddeddolt.gate.lock; do
				if [[ "$(python3 -I -c "$gate_lock_python" try "$state_root/work/$lock" exclusive)" != held ||
					"$(python3 -I -c "$gate_lock_python" try "$state_root/work/$lock" shared)" != free ]]; then
					printf '%s-watch %s does not hold %s shared\n' "$name" "$side" "$lock" >&2
					return 1
				fi
			done
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
compare_watch_refresh list-gates gate-held list --watch --limit 0
# With BD_IGNORE_SCHEMA_SKEW=1 upstream warns once, at the store open of its pre-run, however many
# refreshes the watch reads after it. The watched issue has a dependency, which the detail read of
# show reads too, and is a child in the --parent tree.
watch_extra_env=(BD_IGNORE_SCHEMA_SKEW=1)
for schema_sql in "$schema_ahead_sql" "$schema_behind_sql"; do
	schema_case=ahead
	[[ "$schema_sql" == "$schema_behind_sql" ]] && schema_case=behind
	watch_extra_sql="$schema_sql"$'\n'"$dependency_row ('fixture-watch-1', '$real_database_content_id', '$real_database_issue_id', 'related', '2026-08-21 10:00:00', 'fixture')"
	compare_watch_refresh "show-schema-$schema_case-ignored" update --readonly show "$real_database_content_id" --watch
	compare_watch_refresh "list-schema-$schema_case-ignored" update --readonly list --watch --limit 0
	compare_watch_refresh "list-schema-$schema_case-ignored-ready" update --readonly list --watch --ready
	watch_extra_sql="$schema_sql"$'\n'"$dependency_row ('fixture-watch-1', '$real_database_content_id', '$real_database_epic_id', 'parent-child', '2026-08-21 10:00:00', 'fixture')"
	compare_watch_refresh "list-schema-$schema_case-ignored-parent" update --readonly list --watch --parent "$real_database_epic_id"
done
watch_extra_sql=""
watch_extra_env=(BEADSHX_PARITY_EXTRA=1)

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
if [[ "$real_database_out_of_memory_count" -gt 0 ]]; then
	printf 'real-database differentials: PASS (%s cases, %s skipped because upstream and candidate both ran out of memory; ping timings normalized)\n' "$real_database_case_count" "$real_database_out_of_memory_count"
else
	printf 'real-database differentials: PASS (%s cases; ping timings normalized)\n' "$real_database_case_count"
fi
printf 'candidate-only checks: PASS (%s cases; views not ported yet fail the same way)\n' "$candidate_only_case_count"
printf 'watch differentials: PASS (%s cases; poll change, refresh error, and signal lifecycle)\n' "$watch_case_count"
printf 'JSON terminal notice differential: PASS\n'
