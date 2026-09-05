#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
requirements="$repository_root/scripts/beadshx/pre-commit-requirements.txt"
python="$repository_root/.toolchains/pre-commit/bin/python"
expected_version="$(jq -er '.common.preCommit' "$locks")"
expected_requirements="$(jq -er '.common.preCommitRequirementsSha256' "$locks")"

if [[ "$(shasum -a 256 "$requirements" | awk '{print $1}')" != \
    "$expected_requirements" ]]; then
    printf 'pre-commit requirements do not match the repository lock\n' >&2
    exit 1
fi
if [[ ! -x "$python" ]]; then
    printf 'repository pre-commit is missing; run npm run hooks:install\n' >&2
    exit 1
fi
if [[ "$("$python" -m pre_commit --version)" != "pre-commit $expected_version" ]]; then
    printf 'repository pre-commit version does not match %s\n' "$expected_version" >&2
    exit 1
fi
temporary="$(mktemp "${TMPDIR:-/tmp}/beadshx-precommit-freeze.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
"$python" -m pip freeze --all | sed -E '/^(pip|setuptools)==/d' | \
    LC_ALL=C sort >"$temporary"
if ! diff -u "$requirements" "$temporary"; then
    printf 'repository pre-commit environment drifted from its lock\n' >&2
    exit 1
fi

exec "$python" -m pre_commit "$@"
