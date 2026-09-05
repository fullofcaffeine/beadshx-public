#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
lint_version="$(jq -er '.common.golangciLint' "$locks")"
go_toolchain="$(jq -er '.common.go' "$locks")"
lint_module="$(jq -er '.golangciLintModule.path' "$locks")"
lint_package="$lint_module/cmd/golangci-lint@$lint_version"

cd "$repository_root"
goroot="$(GOWORK=off GOTOOLCHAIN="$go_toolchain" go env GOROOT)"
locked_go="$goroot/bin/go"
if [[ ! -x "$locked_go" || "$(GOWORK=off "$locked_go" env GOVERSION)" != "$go_toolchain" ]]; then
    printf 'locked Go executable is unavailable for GolangCI-Lint\n' >&2
    exit 1
fi
module_evidence="$(GOWORK=off "$locked_go" mod download -json \
    "$lint_module@$lint_version")"
jq -e --arg path "$lint_module" \
    --arg version "$lint_version" \
    --arg sum "$(jq -er '.golangciLintModule.sum' "$locks")" \
    --arg goModSum "$(jq -er '.golangciLintModule.goModSum' "$locks")" \
    '.Path == $path and .Version == $version and .Sum == $sum and .GoModSum == $goModSum' \
    <<<"$module_evidence" >/dev/null || {
        printf 'GolangCI-Lint module bytes do not match the repository lock\n' >&2
        exit 1
    }
GOWORK=off CGO_ENABLED=0 "$locked_go" run "$lint_package" run "$@"
