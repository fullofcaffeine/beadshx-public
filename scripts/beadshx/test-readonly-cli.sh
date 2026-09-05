#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
policy="$repository_root/release/identity-policy.json"
candidate="${BEADSHX_CANDIDATE_BIN:-$repository_root/build/bin/bdhx}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-readonly-cli.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

if [[ ! -x "$candidate" ]]; then
	printf 'bdhx candidate is missing: %s\n' "$candidate" >&2
	exit 1
fi

mkdir -p "$test_root/home" "$test_root/work"
mkdir -p "$test_root/user-config"

run_case() {
	local name="$1"
	shift
	local stdout="$test_root/$name.stdout"
	local stderr="$test_root/$name.stderr"
	local exit_file="$test_root/$name.exit"

	set +e
	(
		cd "$test_root/work"
		env HOME="$test_root/home" \
			XDG_CONFIG_HOME="$test_root/user-config" \
			BEADS_TELEMETRY_DISABLED=1 \
			BEADS_NO_AUTO_FLUSH=1 \
			BD_JSON_ENVELOPE="${BEADSHX_TEST_JSON_ENVELOPE:-0}" \
			NO_COLOR=1 \
			"$candidate" "$@"
	) >"$stdout" 2>"$stderr"
	printf '%s\n' "$?" >"$exit_file"
	set -e
}

expected_identity="$(jq -er '.binaries.developmentIdentity' "$policy")"

run_case version version
[[ "$(<"$test_root/version.exit")" == 0 ]]
[[ "$(<"$test_root/version.stdout")" == "$expected_identity" ]]
[[ ! -s "$test_root/version.stderr" ]]

run_case version_json version --json
[[ "$(<"$test_root/version_json.exit")" == 0 ]]
[[ ! -s "$test_root/version_json.stderr" ]]
jq -e --arg identity "$expected_identity" '
	.schema_version == 1 and
	.version == "0.0.0-development" and
	.build == "development" and
	.compatibility == {
		project: "Beads",
		version: "v1.2.1",
		commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"
	} and
	.identity == $identity and
	(keys | sort) == ["build", "compatibility", "identity", "schema_version", "version"]
' "$test_root/version_json.stdout" >/dev/null

BEADSHX_TEST_JSON_ENVELOPE=1 run_case version_json_envelope version --json
[[ "$(<"$test_root/version_json_envelope.exit")" == 0 ]]
[[ ! -s "$test_root/version_json_envelope.stderr" ]]
jq -e --arg identity "$expected_identity" '
	.schema_version == 1 and
	.data == {
		build: "development",
		compatibility: {
			commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff",
			project: "Beads",
			version: "v1.2.1"
		},
		identity: $identity,
		version: "0.0.0-development"
	} and
	(keys | sort) == ["data", "schema_version"] and
	(.data | has("schema_version") | not)
' "$test_root/version_json_envelope.stdout" >/dev/null

run_case version_flag --version
cmp -s "$test_root/version.stdout" "$test_root/version_flag.stdout"
[[ "$(<"$test_root/version_flag.exit")" == 0 ]]

for ignored_argument_case in version_extra version_dash version_flag_terminator; do
	case "$ignored_argument_case" in
		version_extra) run_case "$ignored_argument_case" version extra ;;
		version_dash) run_case "$ignored_argument_case" version - ;;
		version_flag_terminator) run_case "$ignored_argument_case" version -- --frobnicate ;;
	esac
	cmp -s "$test_root/version.stdout" "$test_root/$ignored_argument_case.stdout"
	[[ "$(<"$test_root/$ignored_argument_case.exit")" == 0 ]]
	[[ ! -s "$test_root/$ignored_argument_case.stderr" ]]
done

run_case unknown_long_flag version --frobnicate
[[ "$(<"$test_root/unknown_long_flag.exit")" == 1 ]]
[[ ! -s "$test_root/unknown_long_flag.stdout" ]]
grep -Fqx 'Error: unknown flag: --frobnicate' "$test_root/unknown_long_flag.stderr"

run_case unknown_attached_flag version --frobnicate=value
[[ "$(<"$test_root/unknown_attached_flag.exit")" == 1 ]]
[[ ! -s "$test_root/unknown_attached_flag.stdout" ]]
grep -Fqx 'Error: unknown flag: --frobnicate' "$test_root/unknown_attached_flag.stderr"

run_case unknown_short_flag version -xyz
[[ "$(<"$test_root/unknown_short_flag.exit")" == 1 ]]
[[ ! -s "$test_root/unknown_short_flag.stdout" ]]
grep -Fqx "Error: unknown shorthand flag: 'x' in -xyz" \
	"$test_root/unknown_short_flag.stderr"

for unknown_command_case in unknown_command unknown_command_help; do
	case "$unknown_command_case" in
		unknown_command) run_case "$unknown_command_case" frobnicate ;;
		unknown_command_help) run_case "$unknown_command_case" frobnicate --help ;;
	esac
	[[ "$(<"$test_root/$unknown_command_case.exit")" == 1 ]]
	[[ ! -s "$test_root/$unknown_command_case.stdout" ]]
	grep -Fqx 'Error: unknown command "frobnicate" for "bd"' \
		"$test_root/$unknown_command_case.stderr"
	grep -Fqx "Run 'bd --help' for usage." \
		"$test_root/$unknown_command_case.stderr"
done

for verbose_case in verbose_before verbose_after verbose_short verbose_true verbose_false; do
	case "$verbose_case" in
		verbose_before) run_case "$verbose_case" --verbose version ;;
		verbose_after) run_case "$verbose_case" version --verbose ;;
		verbose_short) run_case "$verbose_case" version -v ;;
		verbose_true) run_case "$verbose_case" version -v=true ;;
		verbose_false) run_case "$verbose_case" version --verbose=false ;;
	esac
	cmp -s "$test_root/version.stdout" "$test_root/$verbose_case.stdout"
	[[ "$(<"$test_root/$verbose_case.exit")" == 0 ]]
	[[ ! -s "$test_root/$verbose_case.stderr" ]]
done

run_case verbose_invalid version --verbose=bogus
[[ "$(<"$test_root/verbose_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/verbose_invalid.stdout" ]]
grep -Fqx 'Error: invalid argument "bogus" for "-v, --verbose" flag: strconv.ParseBool: parsing "bogus": invalid syntax' \
	"$test_root/verbose_invalid.stderr"

for global_case in global_before global_after global_true global_false; do
	case "$global_case" in
		global_before) run_case "$global_case" --global version ;;
		global_after) run_case "$global_case" version --global ;;
		global_true) run_case "$global_case" version --global=true ;;
		global_false) run_case "$global_case" version --global=false ;;
	esac
	cmp -s "$test_root/version.stdout" "$test_root/$global_case.stdout"
	[[ "$(<"$test_root/$global_case.exit")" == 0 ]]
	[[ ! -s "$test_root/$global_case.stderr" ]]
done

run_case global_invalid version --global=bogus
[[ "$(<"$test_root/global_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/global_invalid.stdout" ]]
grep -Fqx 'Error: invalid argument "bogus" for "--global" flag: strconv.ParseBool: parsing "bogus": invalid syntax' \
	"$test_root/global_invalid.stderr"

run_case cpu_profile_version version --cpu-profile
cmp -s "$test_root/version.stdout" "$test_root/cpu_profile_version.stdout"
[[ "$(<"$test_root/cpu_profile_version.exit")" == 0 ]]
[[ ! -s "$test_root/cpu_profile_version.stderr" ]]

run_case cpu_profile_invalid version --cpu-profile=bogus
[[ "$(<"$test_root/cpu_profile_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/cpu_profile_invalid.stdout" ]]
grep -Fqx 'Error: invalid argument "bogus" for "--cpu-profile" flag: strconv.ParseBool: parsing "bogus": invalid syntax' \
	"$test_root/cpu_profile_invalid.stderr"

profile_root="$test_root/profiles"
mkdir -p "$profile_root"

set +e
(
	cd "$profile_root"
	env HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/user-config" \
		BEADS_TELEMETRY_DISABLED=1 \
		BEADS_NO_AUTO_FLUSH=1 \
		NO_COLOR=1 \
		"$candidate" info --cpu-profile
) >"$test_root/cpu_profile_info.stdout" 2>"$test_root/cpu_profile_info.stderr"
printf '%s\n' "$?" >"$test_root/cpu_profile_info.exit"
set -e
[[ "$(<"$test_root/cpu_profile_info.exit")" == 1 ]]
[[ ! -s "$test_root/cpu_profile_info.stdout" ]]
grep -Fqx 'Error: no beads database found' "$test_root/cpu_profile_info.stderr"
[[ "$(find "$profile_root" -maxdepth 1 -type f -name 'bd-profile-info-*.prof' | wc -l | tr -d ' ')" == 1 ]]
[[ "$(find "$profile_root" -maxdepth 1 -type f -name 'bd-trace-info-*.out' | wc -l | tr -d ' ')" == 1 ]]

heap_profile="$profile_root/version.prof"
run_case mem_profile_version version --mem-profile "$heap_profile"
cmp -s "$test_root/version.stdout" "$test_root/mem_profile_version.stdout"
[[ "$(<"$test_root/mem_profile_version.exit")" == 0 ]]
[[ -s "$heap_profile" ]]

help_profile="$profile_root/help.prof"
run_case mem_profile_help version --help --mem-profile "$help_profile"
[[ "$(<"$test_root/mem_profile_help.exit")" == 0 ]]
[[ ! -e "$help_profile" ]]

run_case mem_profile_missing version --mem-profile
[[ "$(<"$test_root/mem_profile_missing.exit")" == 1 ]]
grep -Fqx 'Error: flag needs an argument: --mem-profile' "$test_root/mem_profile_missing.stderr"

for skew_case in skew_plain skew_true skew_false; do
	case "$skew_case" in
		skew_plain) run_case "$skew_case" version --ignore-schema-skew ;;
		skew_true) run_case "$skew_case" --ignore-schema-skew=true version ;;
		skew_false) run_case "$skew_case" version --ignore-schema-skew=false ;;
	esac
	cmp -s "$test_root/version.stdout" "$test_root/$skew_case.stdout"
	[[ "$(<"$test_root/$skew_case.exit")" == 0 ]]
	[[ ! -s "$test_root/$skew_case.stderr" ]]
done

run_case skew_invalid version --ignore-schema-skew=bogus
[[ "$(<"$test_root/skew_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/skew_invalid.stdout" ]]
grep -Fqx 'Error: invalid argument "bogus" for "--ignore-schema-skew" flag: strconv.ParseBool: parsing "bogus": invalid syntax' \
	"$test_root/skew_invalid.stderr"

for auto_commit_case in auto_commit_on auto_commit_off auto_commit_batch auto_commit_empty; do
	case "$auto_commit_case" in
		auto_commit_on) run_case "$auto_commit_case" version --dolt-auto-commit on ;;
		auto_commit_off) run_case "$auto_commit_case" --dolt-auto-commit=off version ;;
		auto_commit_batch) run_case "$auto_commit_case" version --dolt-auto-commit batch ;;
		auto_commit_empty) run_case "$auto_commit_case" version --dolt-auto-commit= ;;
	esac
	cmp -s "$test_root/version.stdout" "$test_root/$auto_commit_case.stdout"
	[[ "$(<"$test_root/$auto_commit_case.exit")" == 0 ]]
	[[ ! -s "$test_root/$auto_commit_case.stderr" ]]
done

run_case auto_commit_invalid version --dolt-auto-commit nope
[[ "$(<"$test_root/auto_commit_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/auto_commit_invalid.stdout" ]]
grep -Fqx 'Error: invalid --dolt-auto-commit="nope" (valid: off, on, batch)' \
	"$test_root/auto_commit_invalid.stderr"

run_case auto_commit_missing version --dolt-auto-commit
[[ "$(<"$test_root/auto_commit_missing.exit")" == 1 ]]
[[ ! -s "$test_root/auto_commit_missing.stdout" ]]
grep -Fqx 'Error: flag needs an argument: --dolt-auto-commit' \
	"$test_root/auto_commit_missing.stderr"

run_case format_json version --format json
run_case format_json_upper --format=JSON version
cmp -s "$test_root/version_json.stdout" "$test_root/format_json.stdout"
cmp -s "$test_root/version_json.stdout" "$test_root/format_json_upper.stdout"
[[ "$(<"$test_root/format_json.exit")" == 0 ]]
[[ "$(<"$test_root/format_json_upper.exit")" == 0 ]]

run_case format_other version --format yaml
run_case format_empty version --format=
cmp -s "$test_root/version.stdout" "$test_root/format_other.stdout"
cmp -s "$test_root/version.stdout" "$test_root/format_empty.stdout"

run_case format_missing version --format
[[ "$(<"$test_root/format_missing.exit")" == 1 ]]
[[ ! -s "$test_root/format_missing.stdout" ]]
grep -Fqx 'Error: flag needs an argument: --format' "$test_root/format_missing.stderr"

run_case root
run_case help help
[[ "$(<"$test_root/root.exit")" == 0 ]]
[[ "$(<"$test_root/help.exit")" == 0 ]]
cmp -s "$test_root/root.stdout" "$test_root/help.stdout"
[[ ! -s "$test_root/root.stderr" ]]
grep -Fq 'Usage:' "$test_root/root.stdout"
for command_name in version info where ping status; do
	grep -Eq "^[[:space:]]+$command_name[[:space:]]" "$test_root/root.stdout"
done

for command_name in version where info ping status stats; do
	run_case "${command_name}_help" "$command_name" --help
	[[ "$(<"$test_root/${command_name}_help.exit")" == 0 ]]
	[[ ! -s "$test_root/${command_name}_help.stderr" ]]
	grep -Fq 'Usage:' "$test_root/${command_name}_help.stdout"
	usage_name="$command_name"
	[[ "$usage_name" != stats ]] || usage_name=status
	grep -Fq "bdhx $usage_name" "$test_root/${command_name}_help.stdout"
	grep -Fq -- '--directory string' "$test_root/${command_name}_help.stdout"
	grep -Fq -- '--database string' "$test_root/${command_name}_help.stdout"
	grep -Fq -- '--db string' "$test_root/${command_name}_help.stdout"
	run_case "help_${command_name}" help "$command_name"
	[[ "$(<"$test_root/help_${command_name}.exit")" == 0 ]]
	[[ ! -s "$test_root/help_${command_name}.stderr" ]]
	cmp -s "$test_root/${command_name}_help.stdout" "$test_root/help_${command_name}.stdout"
done
grep -Fq -- '--directory string' "$test_root/root.stdout"
grep -Fq -- '--database string' "$test_root/root.stdout"
grep -Fq -- '--db string' "$test_root/root.stdout"
grep -Fq -- '--verbose' "$test_root/root.stdout"
grep -Fq -- '--dolt-auto-commit string' "$test_root/root.stdout"
grep -Fq -- '--ignore-schema-skew' "$test_root/root.stdout"
grep -Fq -- '--global' "$test_root/root.stdout"
grep -Fq -- '--cpu-profile' "$test_root/root.stdout"
grep -Fq -- '--mem-profile string' "$test_root/root.stdout"
grep -Fqx '      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)' \
	"$test_root/root.stdout"
grep -Fqx '      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)' \
	"$test_root/root.stdout"
grep -Fqx '  -q, --quiet                     Suppress non-essential output (errors only)' \
	"$test_root/root.stdout"
grep -Fqx '      --readonly                  Read-only mode: block write operations (for worker sandboxes)' \
	"$test_root/root.stdout"
grep -Fqx '      --sandbox                   Sandbox mode: disables Dolt auto-push' \
	"$test_root/root.stdout"

run_case where where
[[ "$(<"$test_root/where.exit")" == 1 ]]
[[ ! -s "$test_root/where.stdout" ]]
grep -Fqx 'Error: No active beads workspace found.' "$test_root/where.stderr"
grep -Fqx "Hint: check BEADS_DIR/worktree setup, or run 'bd init' to create a new database" \
	"$test_root/where.stderr"

run_case where_json where --json
[[ "$(<"$test_root/where_json.exit")" == 1 ]]
[[ ! -s "$test_root/where_json.stderr" ]]
jq -e '
	.schema_version == 1 and
	.error == "no_beads_directory" and
	.message == "No active beads workspace found." and
	.hint == "check BEADS_DIR/worktree setup, or run '\''bd init'\'' to create a new database" and
	(keys | sort) == ["error", "hint", "message", "schema_version"]
' "$test_root/where_json.stdout" >/dev/null

for command_name in info ping status stats; do
	run_case "${command_name}_missing" "$command_name" --json
	[[ "$(<"$test_root/${command_name}_missing.exit")" == 1 ]]
	[[ ! -s "$test_root/${command_name}_missing.stdout" ]]
	grep -Fqx 'Error: no beads database found' "$test_root/${command_name}_missing.stderr"
	grep -Fqx "Hint: run 'bd where' to inspect the resolved workspace, or 'bd init' to create a new database" \
		"$test_root/${command_name}_missing.stderr"
	grep -Fqx '      or set BEADS_DIR to point to your .beads directory' \
		"$test_root/${command_name}_missing.stderr"
done

run_case compatibility_noops info --readonly --sandbox --no-color --quiet --ignore-schema-skew --dolt-auto-commit off --json
[[ "$(<"$test_root/compatibility_noops.exit")" == 1 ]]
[[ ! -s "$test_root/compatibility_noops.stdout" ]]
grep -Fqx 'Error: no beads database found' "$test_root/compatibility_noops.stderr"

run_case info_whats_new_missing info --whats-new --json
[[ "$(<"$test_root/info_whats_new_missing.exit")" == 1 ]]
[[ ! -s "$test_root/info_whats_new_missing.stdout" ]]
grep -Fqx 'Error: no beads database found' "$test_root/info_whats_new_missing.stderr"

grep -Fq -- '--whats-new' "$test_root/info_help.stdout"

run_case actor_missing --actor
[[ "$(<"$test_root/actor_missing.exit")" == 1 ]]
[[ ! -s "$test_root/actor_missing.stdout" ]]
grep -Fqx 'Error: --actor requires a value' "$test_root/actor_missing.stderr"

run_case actor_empty --actor=
[[ "$(<"$test_root/actor_empty.exit")" == 1 ]]
[[ ! -s "$test_root/actor_empty.stdout" ]]
grep -Fqx 'Error: --actor requires a non-empty value' "$test_root/actor_empty.stderr"

selection_root="$test_root/selected-project"
global_root="$test_root/global-project"
mkdir -p "$selection_root/.beads" "$selection_root/nested/deeper" "$global_root/.beads" "$test_root/empty-project"
chmod 700 "$selection_root/.beads"
printf '%s\n' '{"backend":"dolt"}' >"$selection_root/.beads/metadata.json"
chmod 700 "$global_root/.beads"
printf '%s\n' '{"backend":"dolt","dolt_mode":"server"}' >"$global_root/.beads/metadata.json"
printf '%s\n' 'issue-prefix: globaltest' >"$global_root/.beads/config.yaml"
selected_beads="$(cd "$selection_root/.beads" && pwd -P)"

run_case global_requires_shared -C "$global_root" info --global
[[ "$(<"$test_root/global_requires_shared.exit")" == 1 ]]
[[ ! -s "$test_root/global_requires_shared.stdout" ]]
grep -Fqx 'Error: --global requires shared-server mode (set BEADS_DOLT_SHARED_SERVER=1 or dolt.shared-server: true in config.yaml)' \
	"$test_root/global_requires_shared.stderr"

run_case global_whats_new_requires_shared -C "$global_root" info --whats-new --global
[[ "$(<"$test_root/global_whats_new_requires_shared.exit")" == 1 ]]
[[ ! -s "$test_root/global_whats_new_requires_shared.stdout" ]]
cmp -s "$test_root/global_requires_shared.stderr" "$test_root/global_whats_new_requires_shared.stderr"

run_case directory_before -C "$selection_root/nested/deeper" where --json
[[ "$(<"$test_root/directory_before.exit")" == 0 ]]
[[ ! -s "$test_root/directory_before.stderr" ]]
jq -e --arg path "$selected_beads" '
	.path == $path and
	.schema_version == 1 and
	(keys | sort) == ["path", "schema_version"]
' "$test_root/directory_before.stdout" >/dev/null

run_case directory_after where --directory="$selection_root" --json
[[ "$(<"$test_root/directory_after.exit")" == 0 ]]
[[ ! -s "$test_root/directory_after.stderr" ]]
cmp -s "$test_root/directory_before.stdout" "$test_root/directory_after.stdout"

run_case directory_attached -C"$selection_root" where --json
[[ "$(<"$test_root/directory_attached.exit")" == 0 ]]
[[ ! -s "$test_root/directory_attached.stderr" ]]
cmp -s "$test_root/directory_before.stdout" "$test_root/directory_attached.stdout"

run_case directory_last_wins -C "$test_root/missing" -C "$selection_root" where --json
[[ "$(<"$test_root/directory_last_wins.exit")" == 0 ]]
[[ ! -s "$test_root/directory_last_wins.stderr" ]]
cmp -s "$test_root/directory_before.stdout" "$test_root/directory_last_wins.stdout"

run_case directory_empty where --directory= --json
[[ "$(<"$test_root/directory_empty.exit")" == 1 ]]
[[ ! -s "$test_root/directory_empty.stderr" ]]
jq -e '.error == "no_beads_directory"' "$test_root/directory_empty.stdout" >/dev/null

run_case directory_missing_value where -C
[[ "$(<"$test_root/directory_missing_value.exit")" == 1 ]]
[[ ! -s "$test_root/directory_missing_value.stdout" ]]
grep -Fqx "Error: flag needs an argument: 'C' in -C" "$test_root/directory_missing_value.stderr"

run_case directory_missing where -C "$test_root/missing" --json
[[ "$(<"$test_root/directory_missing.exit")" == 1 ]]
[[ ! -s "$test_root/directory_missing.stdout" ]]
grep -Fq "Error: cannot use -C directory \"$test_root/missing\": stat " "$test_root/directory_missing.stderr"
grep -Fq 'no such file or directory' "$test_root/directory_missing.stderr"

run_case directory_no_project -C "$test_root/empty-project" where --json
[[ "$(<"$test_root/directory_no_project.exit")" == 1 ]]
[[ ! -s "$test_root/directory_no_project.stdout" ]]
grep -Fqx "Error: cannot use -C directory \"$test_root/empty-project\": no beads project found" \
	"$test_root/directory_no_project.stderr"

printf x >"$test_root/not-a-directory"
run_case directory_file -C "$test_root/not-a-directory" where --json
[[ "$(<"$test_root/directory_file.exit")" == 1 ]]
[[ ! -s "$test_root/directory_file.stdout" ]]
grep -Fqx "Error: cannot use -C directory \"$test_root/not-a-directory\": not a directory" \
	"$test_root/directory_file.stderr"

run_case directory_help_bypass -C "$test_root/missing" where --help
[[ "$(<"$test_root/directory_help_bypass.exit")" == 0 ]]
[[ ! -s "$test_root/directory_help_bypass.stderr" ]]
cmp -s "$test_root/where_help.stdout" "$test_root/directory_help_bypass.stdout"

run_case directory_root_invalid -C "$test_root/missing"
[[ "$(<"$test_root/directory_root_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/directory_root_invalid.stdout" ]]
grep -Fq "Error: cannot use -C directory \"$test_root/missing\": stat " "$test_root/directory_root_invalid.stderr"

run_case directory_version_invalid -C "$test_root/missing" version
[[ "$(<"$test_root/directory_version_invalid.exit")" == 1 ]]
[[ ! -s "$test_root/directory_version_invalid.stdout" ]]
grep -Fq "Error: cannot use -C directory \"$test_root/missing\": stat " "$test_root/directory_version_invalid.stderr"

database_root="$test_root/database-project"
mkdir -p "$database_root/.beads/embeddeddolt"
chmod 700 "$database_root/.beads" "$database_root/.beads/embeddeddolt"
printf '%s\n' '{"backend":"dolt"}' >"$database_root/.beads/metadata.json"
printf '%s\n' 'issue-prefix: test' >"$database_root/.beads/config.yaml"
database_beads="$(cd "$database_root/.beads" && pwd -P)"
database_data="$database_beads/embeddeddolt"

run_case database_path --db "$database_data" where --json
[[ "$(<"$test_root/database_path.exit")" == 0 ]]
[[ ! -s "$test_root/database_path.stderr" ]]
jq -e --arg path "$database_beads" --arg database "$database_data" '
	.path == $path and
	.database_path == $database and
	.schema_version == 1
' "$test_root/database_path.stdout" >/dev/null

run_case database_missing_path --db "$test_root/missing/database" where --json
[[ "$(<"$test_root/database_missing_path.exit")" == 0 ]]
[[ ! -s "$test_root/database_missing_path.stderr" ]]
missing_database_parent="$(printf '%s' "$test_root/missing" | sed 's://:/:g')"
jq -e --arg path "$missing_database_parent" '.path == $path and .schema_version == 1' \
	"$test_root/database_missing_path.stdout" >/dev/null

database_mode_error='--database (or a --db value naming a database) is only supported in proxied-server mode'
printf '%s\n' 'issue-prefix: test' >"$selection_root/.beads/config.yaml"
run_case database_name -C "$selection_root" --database alternate_db info --json
[[ "$(<"$test_root/database_name.exit")" == 1 ]]
[[ ! -s "$test_root/database_name.stderr" ]]
jq -e --arg error "$database_mode_error" '.error == $error and .schema_version == 1' \
	"$test_root/database_name.stdout" >/dev/null

run_case database_name_via_db -C "$selection_root" --db alternate_db info --json
[[ "$(<"$test_root/database_name_via_db.exit")" == 1 ]]
[[ ! -s "$test_root/database_name_via_db.stderr" ]]
cmp -s "$test_root/database_name.stdout" "$test_root/database_name_via_db.stdout"

run_case database_conflict -C "$selection_root" --db alternate_db --database another_db info --json
[[ "$(<"$test_root/database_conflict.exit")" == 1 ]]
[[ ! -s "$test_root/database_conflict.stdout" ]]
grep -Fqx 'Error: conflicting database selection: --db="alternate_db" vs --database="another_db"' \
	"$test_root/database_conflict.stderr"

run_case database_path_missing_value info --db
[[ "$(<"$test_root/database_path_missing_value.exit")" == 1 ]]
grep -Fqx 'Error: flag needs an argument: --db' "$test_root/database_path_missing_value.stderr"

run_case database_name_missing_value info --database
[[ "$(<"$test_root/database_name_missing_value.exit")" == 1 ]]
grep -Fqx 'Error: flag needs an argument: --database' "$test_root/database_name_missing_value.stderr"

if find "$test_root/home" "$test_root/user-config" "$test_root/work" \
	-mindepth 1 -print -quit | grep -q .; then
	printf 'read-only no-workspace commands created persistent files\n' >&2
	find "$test_root/home" "$test_root/user-config" "$test_root/work" -mindepth 1 -print >&2
	exit 1
fi

printf 'read-only CLI tracer: PASS\n'
