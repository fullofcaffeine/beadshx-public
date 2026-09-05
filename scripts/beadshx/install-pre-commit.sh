#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
requirements="$repository_root/scripts/beadshx/pre-commit-requirements.txt"
install_root="$repository_root/.toolchains/pre-commit"
expected_version="$(jq -er '.common.preCommit' "$locks")"
expected_requirements="$(jq -er '.common.preCommitRequirementsSha256' "$locks")"
actual_requirements="$(shasum -a 256 "$requirements" | awk '{print $1}')"

if [[ "$actual_requirements" != "$expected_requirements" ]]; then
    printf 'pre-commit requirements mismatch: expected %s, got %s\n' \
        "$expected_requirements" "$actual_requirements" >&2
    exit 1
fi

toolchain_parent="$repository_root/.toolchains"
mkdir -p "$toolchain_parent"
temporary="$(mktemp -d "$toolchain_parent/pre-commit.install.XXXXXX")"
previous=""
cleanup() {
    if [[ -d "$temporary" ]]; then
        find "$temporary" -mindepth 1 -delete
        rmdir "$temporary"
    fi
}
trap cleanup EXIT

python3 -m venv "$temporary"
"$temporary/bin/python" -m pip install --disable-pip-version-check \
    --requirement "$requirements"
"$temporary/bin/python" -m pip check
"$temporary/bin/python" -m pip freeze --all | \
    sed -E '/^(pip|setuptools)==/d' | LC_ALL=C sort >"$temporary/installed.txt"
if ! diff -u "$requirements" "$temporary/installed.txt"; then
    printf 'pre-commit environment does not match its repository lock\n' >&2
    exit 1
fi
if [[ "$("$temporary/bin/pre-commit" --version)" != "pre-commit $expected_version" ]]; then
    printf 'pre-commit did not resolve to %s\n' "$expected_version" >&2
    exit 1
fi
rm "$temporary/installed.txt"

if [[ -e "$install_root" ]]; then
    previous="$toolchain_parent/pre-commit.previous.$$"
    mv "$install_root" "$previous"
fi
if ! mv "$temporary" "$install_root"; then
    if [[ -n "$previous" && -e "$previous" ]]; then
        mv "$previous" "$install_root"
    fi
    exit 1
fi
if [[ -n "$previous" && -d "$previous" ]]; then
    find "$previous" -mindepth 1 -delete
    rmdir "$previous"
fi

printf 'pre-commit: %s\n' "$expected_version"
