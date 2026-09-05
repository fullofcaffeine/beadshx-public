#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

if ! command -v bd-toolchain >/dev/null 2>&1; then
    printf 'bd-toolchain is required to validate the repository Beads client.\n' >&2
    exit 1
fi

bd-toolchain check >/dev/null
bd --readonly info --json >/dev/null
"$repository_root/scripts/beadshx/setup-haxe.sh"

if ! "$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null 2>&1; then
    "$repository_root/scripts/beadshx/install-gitleaks.sh"
fi
"$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null

expected_pre_commit="$(jq -er '.common.preCommit' \
    "$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
actual_pre_commit="missing"
if [[ -x "$repository_root/.toolchains/pre-commit/bin/python" ]]; then
    actual_pre_commit="$("$repository_root/.toolchains/pre-commit/bin/python" \
        -m pre_commit --version 2>/dev/null || true)"
fi
if [[ "$actual_pre_commit" != "pre-commit $expected_pre_commit" ]]; then
    "$repository_root/scripts/beadshx/install-pre-commit.sh"
fi

"$repository_root/scripts/beadshx/run-pre-commit.sh" validate-config \
    "$repository_root/.pre-commit-config.yaml"
git config core.hooksPath .githooks

printf 'repository hooks installed from .githooks\n'
