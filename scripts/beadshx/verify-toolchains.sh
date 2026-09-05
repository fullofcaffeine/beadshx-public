#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
profile="common"

if [[ $# -gt 0 ]]; then
    case "$1" in
        --profile=common|--profile=linux-ci)
            profile="${1#--profile=}"
            ;;
        *)
            printf 'usage: %s [--profile=common|--profile=linux-ci]\n' "$0" >&2
            exit 2
            ;;
    esac
fi

expect_exact() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf '%s mismatch: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
    printf '%s: %s\n' "$label" "$actual"
}

locked() {
    jq -er "$1" "$locks"
}

expect_file_text() {
    local label="$1"
    local file="$2"
    local text="$3"
    if ! grep -Fq -- "$text" "$file"; then
        printf '%s lock is missing from %s: %s\n' "$label" "$file" "$text" >&2
        exit 1
    fi
}

cd "$repository_root"

ambient_gowork="$(go env GOWORK)"
if [[ -n "$ambient_gowork" && "$ambient_gowork" != off ]]; then
    printf 'an ambient Go workspace is active: %s\nSet GOWORK=off for BeadsHX commands.\n' \
        "$ambient_gowork" >&2
    exit 1
fi
export GOWORK=off

locked_go="$(locked '.common.go')"
source_locks=engdocs/beadshx/program/source-locks.json
jq -e --arg npm "npm@$(locked '.common.npm')" \
    --arg lix "$(locked '.common.lix')" \
    '.packageManager == $npm and .devDependencies.lix == $lix' package.json >/dev/null

jq -e --slurpfile tools "$locks" '
    .toolchains.haxe == $tools[0].common.haxe and
    .toolchains.haxeFormatter == $tools[0].common.haxeFormatter and
    ("go" + .toolchains.go) == $tools[0].common.go and
    .toolchains.golangciLint == $tools[0].common.golangciLint and
    .toolchains.preCommit == $tools[0].common.preCommit and
    .toolchains.node == $tools[0].common.node and
    .toolchains.npm == $tools[0].common.npm and
    .toolchains.lix == $tools[0].common.lix and
    .compiler.requiredCommit == $tools[0].common.haxeGoCommit and
    .toolchains.policy == "engdocs/beadshx/program/toolchain-locks.json"
' "$source_locks" >/dev/null

while read -r digest file; do
    case "$file" in
        beadshx-complete-port-prd.md)
            expect_exact PRD "$(jq -er '.specification.prdSha256' "$source_locks")" "$digest"
            ;;
        beadshx-complete-backlog.json)
            expect_exact backlog "$(jq -er '.specification.backlogSha256' "$source_locks")" "$digest"
            ;;
    esac
done <beadshx-prd-sha256.txt

workflow=.github/workflows/beadshx-bootstrap.yml
expect_file_text runner "$workflow" "runs-on: $(locked '.linuxCi.runnerLabel')"
while IFS=$'\t' read -r action commit; do
    action_repository="${action%@*}"
    expect_file_text "$action" "$workflow" "uses: $action_repository@$commit"
done < <(jq -r '.githubActions | to_entries[] | [.key, .value] | @tsv' "$locks")
expect_file_text Node "$workflow" "node-version: \"$(locked '.common.node')\""
expect_file_text Go "$workflow" "go-version: \"${locked_go#go}\""
expect_file_text npm "$workflow" "npm@$(locked '.common.npm')"

expect_exact Node "$(locked '.common.node')" "$(node --version | sed 's/^v//')"
expect_exact npm "$(locked '.common.npm')" "$(npm --version)"
expect_exact Go "$locked_go" "$(go env GOVERSION)"
expect_exact Haxe "$(locked '.common.haxe')" "$(npx haxe --version)"
expect_exact Lix "$(locked '.common.lix')" "$(npx lix --version)"
expect_exact "Haxe Formatter" "$(locked '.common.haxeFormatter')" \
    "$(npx lix run formatter --help 2>&1 | sed -n -E 's/^Haxe Formatter ([0-9.]+)$/\1/p' | head -n 1)"

expect_exact node-modules \
    "$(shasum -a 256 package-lock.json | awk '{print $1}')" \
    "$(cat node_modules/.beadshx-package-lock.sha256 2>/dev/null || printf missing)"

compiler_root="$repository_root/.toolchains/haxe.go"
if [[ ! -d "$compiler_root/.git" ]]; then
    printf 'haxe.go checkout is missing; run npm run setup:haxe first\n' >&2
    exit 1
fi
expect_exact haxe.go "$(locked '.common.haxeGoCommit')" \
    "$(git -C "$compiler_root" rev-parse HEAD)"
if [[ -n "$(git -C "$compiler_root" status --porcelain --untracked-files=all)" ]]; then
    printf 'haxe.go checkout contains tracked or untracked changes\n' >&2
    exit 1
fi
compiler_git_dir="$(git -C "$compiler_root" rev-parse --absolute-git-dir)"
if [[ -f "$compiler_git_dir/objects/info/alternates" ]]; then
    printf 'haxe.go checkout depends on an external Git object store\n' >&2
    exit 1
fi

while IFS=$'\t' read -r module expected; do
    actual="$(go list -m -f '{{.Version}}' "$module")"
    expect_exact "$module" "$expected" "$actual"
done < <(jq -r '.goModules | to_entries[] | [.key, .value] | @tsv' "$locks")
go mod verify
if GOWORK=off go list -m -json all | jq -se 'any(.[]; .Replace != null)' >/dev/null; then
    printf 'Go module replacements are not admitted by the BeadsHX toolchain lock\n' >&2
    exit 1
fi

if [[ "$profile" == "linux-ci" ]]; then
    expect_exact kernel Linux "$(uname -s)"
    expect_exact runner "$(locked '.linuxCi.imageOS')" "${ImageOS:-missing}"
    expect_exact runner-image "$(locked '.linuxCi.imageVersion')" "${ImageVersion:-missing}"
    expect_exact Bash "$(locked '.linuxCi.bash')" "$BASH_VERSION"
    expect_exact GCC "$(locked '.linuxCi.gcc')" "$(gcc -dumpfullversion -dumpversion)"
    expect_exact G++ "$(locked '.linuxCi.gxx')" "$(g++ -dumpfullversion -dumpversion)"
    expect_exact binutils "$(locked '.linuxCi.binutils')" \
        "$(ld -v | sed -E 's/^GNU ld \([^)]*\) ([0-9.]+)$/\1/')"
    expect_exact pkg-config "$(locked '.linuxCi.pkgConfig')" "$(pkg-config --version)"
    expect_exact Make "$(locked '.linuxCi.make')" \
        "$(make --version | sed -n -E '1s/^GNU Make ([0-9.]+)$/\1/p')"
    expect_exact Git "$(locked '.linuxCi.git')" "$(git --version | sed 's/^git version //')"
    expect_exact jq "$(locked '.linuxCi.jq')" "$(jq --version)"
    expect_exact ShellCheck "$(locked '.linuxCi.shellcheck')" \
        "$(shellcheck --version | sed -n 's/^version: //p')"
fi

printf 'toolchain profile %s: PASS\n' "$profile"
