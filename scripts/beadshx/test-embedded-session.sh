#!/usr/bin/env bash
# Run the Haxe embedded-session test (test/embedded_session) against a
# workspace that the upstream oracle creates in a fresh disposable directory,
# then read the workspace back through the oracle to prove that it is unchanged.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
oracle="$repository_root/build/bin/bd-upstream"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-embedded-session.XXXXXX")"
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-session-generated.XXXXXX")"
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
npx haxe test/embedded_session/compile.hxml -D go_no_build
CGO_ENABLED=1 go build -tags=gms_pure_go -o "$fixture_root/embedded-session-test" ./generated/go/bdhx

workspace="$fixture_root/work"
missing_store="$fixture_root/nostore"
mkdir -p "$workspace" "$missing_store/.beads" "$fixture_root/home" "$fixture_root/config"
touch "$workspace/.beadshx-disposable-fixture" "$missing_store/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$workspace" >/dev/null
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$missing_store" >/dev/null
fixture_env=(env -i PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" HOME="$fixture_root/home"
    XDG_CONFIG_HOME="$fixture_root/config" BEADS_ACTOR=fixture
    BEADS_TELEMETRY_DISABLED=1 BEADS_NO_AUTO_FLUSH=1 BD_DISABLE_METRICS=1
    BD_DISABLE_EVENT_FLUSH=1 NO_COLOR=1)
(
    cd "$workspace"
    git init -q
    git config user.name fixture
    git config user.email fixture@example.invalid
    "${fixture_env[@]}" "$oracle" init --prefix es --non-interactive --skip-agents --skip-hooks --quiet
    "${fixture_env[@]}" "$oracle" create "Session issue" --json | jq -er '.id' >"$fixture_root/issue-id"
    "${fixture_env[@]}" "$oracle" comments add "$(cat "$fixture_root/issue-id")" "Session comment" >/dev/null
)
issue_id="$(cat "$fixture_root/issue-id")"
read_back() {
    (
        cd "$workspace"
        "${fixture_env[@]}" "$oracle" config list --json
        "${fixture_env[@]}" "$oracle" show "$issue_id" --json
    )
}
read_back >"$fixture_root/before.json"
(cd "$workspace" && "${fixture_env[@]}" "$fixture_root/embedded-session-test" "$workspace/.beads" "$missing_store/.beads" "$issue_id")
read_back >"$fixture_root/after.json"
if ! cmp -s "$fixture_root/before.json" "$fixture_root/after.json"; then
    echo 'embedded session test changed the workspace as the oracle reads it' >&2
    diff -u "$fixture_root/before.json" "$fixture_root/after.json" >&2 || true
    exit 1
fi
echo 'embedded session lifecycle and oracle readback: PASS'
