#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
oracle="$repository_root/build/bin/bd-upstream"
candidate="${1:-}"
if [[ -n "$candidate" && ! -x "$candidate" ]]; then
    echo 'relation CLI candidate is not executable' >&2
    exit 1
fi
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-storage-relation.XXXXXX")"
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-relation-generated.XXXXXX")"
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
npx haxe test/storage_relation/compile.hxml -D go_no_build
CGO_ENABLED=1 go build -tags=gms_pure_go -o "$fixture_root/relation-tracer" ./generated/go/bdhx

for plane in durable wisp; do
    workspace="$fixture_root/$plane/work"
    mkdir -p "$workspace" "$fixture_root/$plane/home" "$fixture_root/$plane/config"
    touch "$workspace/.beadshx-disposable-fixture"
    "$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$workspace" >/dev/null
    (
        cd "$workspace"
        git init -q
        git config user.name fixture
        git config user.email fixture@example.invalid
        oracle_command=(env -i PATH="$PATH" HOME="$fixture_root/$plane/home"
            XDG_CONFIG_HOME="$fixture_root/$plane/config" BEADS_ACTOR=fixture
            BEADS_TELEMETRY_DISABLED=1 BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1
            BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1 "$oracle")
        "${oracle_command[@]}" init --prefix rel --non-interactive --skip-agents --skip-hooks --quiet
        "${oracle_command[@]}" create Target --id rel-target --json >/dev/null
        flags=()
        [[ "$plane" != wisp ]] || flags+=(--ephemeral)
        "${oracle_command[@]}" create Dependent --id rel-dependent --description "Relation description" --labels fixture-label "${flags[@]}" --json >/dev/null
        "${oracle_command[@]}" update rel-dependent --await-id fixture-run --json >/dev/null
        "${oracle_command[@]}" dep add rel-dependent rel-target >/dev/null
        "${oracle_command[@]}" dep list rel-target --direction up --json >"$fixture_root/$plane/oracle.json"
        jq -e 'length == 1 and .[0].id == "rel-dependent" and .[0].title == "Dependent" and .[0].dependency_type == "blocks" and .[0].labels == ["fixture-label"] and .[0].description == "Relation description" and (.[0].await_type // "") == "" and .[0].await_id == "fixture-run"' \
            "$fixture_root/$plane/oracle.json" >/dev/null
        "$fixture_root/relation-tracer" "$workspace"
        "${oracle_command[@]}" dep list rel-target --direction up --json >"$fixture_root/$plane/after.json"
        cmp "$fixture_root/$plane/oracle.json" "$fixture_root/$plane/after.json"
        if [[ -n "$candidate" ]]; then
            candidate_command=("${oracle_command[@]:0:${#oracle_command[@]}-1}" "$candidate")
            compare_cli() {
                local name="$1" oracle_exit=0 candidate_exit=0
                shift
                "${oracle_command[@]}" "$@" >"$fixture_root/$plane/$name.oracle.out" 2>"$fixture_root/$plane/$name.oracle.err" || oracle_exit=$?
                "${candidate_command[@]}" "$@" >"$fixture_root/$plane/$name.candidate.out" 2>"$fixture_root/$plane/$name.candidate.err" || candidate_exit=$?
                if [[ "$oracle_exit" != "$candidate_exit" ]]; then
                    printf '%s/%s exit mismatch: upstream=%s candidate=%s\n' "$plane" "$name" "$oracle_exit" "$candidate_exit" >&2
                    cat "$fixture_root/$plane/$name.candidate.err" >&2
                    return 1
                fi
                diff -u "$fixture_root/$plane/$name.oracle.out" "$fixture_root/$plane/$name.candidate.out"
                diff -u "$fixture_root/$plane/$name.oracle.err" "$fixture_root/$plane/$name.candidate.err"
            }
            compare_cli incoming-json dep list rel-target --direction up --json
            compare_cli incoming-human dep list rel-target --direction=up
            compare_cli outgoing-json dep list rel-dependent --json
            compare_cli incoming-filter dep list rel-target --direction up --type blocks --json
            compare_cli incoming-filter-empty dep list rel-target --direction up --type tracks --json
            compare_cli incoming-empty dep list rel-dependent --direction up
            compare_cli incoming-empty-json dep list rel-dependent --direction up --json
            compare_cli incoming-duplicates dep list rel-target rel-target --direction up --json
            compare_cli incoming-batch-empty dep list rel-dependent rel-dependent --direction up
            compare_cli incoming-batch-missing dep list rel-target rel-missing --direction up --json
            compare_cli incoming-missing dep list rel-missing --direction up --json
            compare_cli incoming-all-missing dep list rel-missing rel-absent --direction up --json
            compare_cli incoming-invalid-type dep list rel-target --direction up --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
            compare_cli unknown-direction-batch dep list rel-dependent rel-dependent --direction sideways --json
            compare_cli empty-direction-batch dep list rel-dependent rel-dependent --direction= --json
            compare_cli default-direction-batch dep list rel-dependent rel-target --json
            compare_cli missing-invalid-type dep list rel-missing --direction up --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
            compare_cli all-missing-invalid-type dep list rel-missing rel-absent --direction up --type xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx --json
            printf 'Dolt relation CLI parity (%s): PASS\n' "$plane"
        fi
    )
done
printf 'Dolt relation tracer (durable and wisp): PASS\n'
