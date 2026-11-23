#!/usr/bin/env bash
# Compare the Haxe export read (test/export_read) with upstream
# `bd export --all` on a workspace that the upstream oracle fills in a fresh
# disposable directory: each issue line must be byte-equal, and the read must
# leave the workspace as the oracle reads it.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=export-fixture.sh
source "$repository_root/scripts/beadshx/export-fixture.sh"
oracle="$repository_root/build/bin/bd-upstream"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-export-read.XXXXXX")"
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-export-generated.XXXXXX")"
generated_root="$repository_root/generated/go"
had_generated=false
cleanup() {
	if [[ -d "$generated_root" ]]; then
		find "$generated_root" -mindepth 1 -delete
		rmdir "$generated_root"
	fi
	if [[ "$had_generated" == true ]]; then
		mv -f "$backup_root/go" "$generated_root"
	fi
	find "$backup_root" -mindepth 1 -delete
	rmdir "$backup_root"
	find "$fixture_root" -mindepth 1 -delete
	rmdir "$fixture_root"
}
cd "$repository_root"
if [[ -d "$generated_root" ]]; then
	cp -rf "$generated_root" "$backup_root/go"
	had_generated=true
fi
trap cleanup EXIT
identity="$("$oracle" version)"
[[ "$identity" == *'1.2.1'* && "$identity" == *'634cbbc4b'* ]] || {
	echo 'unexpected upstream oracle identity' >&2
	exit 1
}
export GOTOOLCHAIN="$(jq -er '.common.go' engdocs/beadshx/program/toolchain-locks.json)"
go build -tags gms_pure_go -o "$fixture_root/fixture-sql" ./scripts/beadshx/fixture-sql
npx haxe test/export_read/compile.hxml -D go_no_build
CGO_ENABLED=1 go build -tags=gms_pure_go -o "$fixture_root/export-read-test" ./generated/go/bdhx

workspace="$fixture_root/work"
mkdir -p "$workspace" "$fixture_root/home" "$fixture_root/config"
touch "$workspace/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$workspace" >/dev/null
oracle_command=(env -i PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" HOME="$fixture_root/home"
	XDG_CONFIG_HOME="$fixture_root/config" TZ=UTC BEADS_ACTOR=fixture
	BEADS_TELEMETRY_DISABLED=1 BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1
	BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1 "$oracle")
build_export_fixture "$workspace" "$fixture_root/fixture-sql" "${oracle_command[@]}"

(cd "$workspace" && "${oracle_command[@]}" export --all) >"$fixture_root/oracle.jsonl"
require_export_coverage "$fixture_root/oracle.jsonl"
sorted_issue_lines "$fixture_root/oracle.jsonl" >"$fixture_root/expected.jsonl"
(cd "$workspace" && "${oracle_command[@]:0:${#oracle_command[@]}-1}" "$fixture_root/export-read-test" "$workspace") \
	>"$fixture_root/haxe.jsonl"
sorted_issue_lines "$fixture_root/haxe.jsonl" >"$fixture_root/actual.jsonl"
if ! cmp -s "$fixture_root/expected.jsonl" "$fixture_root/actual.jsonl"; then
	echo 'Haxe export read differs from upstream export --all' >&2
	diff -u "$fixture_root/expected.jsonl" "$fixture_root/actual.jsonl" >&2 || true
	exit 1
fi
if [[ "$(wc -l <"$fixture_root/haxe.jsonl")" != "$(wc -l <"$fixture_root/actual.jsonl")" ]]; then
	echo 'Haxe export read printed a line that is not an issue' >&2
	exit 1
fi
(cd "$workspace" && "${oracle_command[@]}" export --all) >"$fixture_root/after.jsonl"
if ! cmp -s "$fixture_root/oracle.jsonl" "$fixture_root/after.jsonl"; then
	echo 'Haxe export read changed the workspace as the oracle reads it' >&2
	exit 1
fi
echo "Haxe export read equals upstream export --all ($(wc -l <"$fixture_root/actual.jsonl" | tr -d ' ') issues): PASS"
