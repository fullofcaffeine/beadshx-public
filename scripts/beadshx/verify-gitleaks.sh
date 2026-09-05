#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
scanner="$repository_root/.toolchains/bin/gitleaks"

case "$(uname -s):$(uname -m)" in
    Darwin:arm64) asset=darwin_arm64 ;;
    Darwin:x86_64) asset=darwin_x64 ;;
    Linux:aarch64|Linux:arm64) asset=linux_arm64 ;;
    Linux:x86_64) asset=linux_x64 ;;
    *)
        printf 'gitleaks has no lock for %s/%s\n' "$(uname -s)" "$(uname -m)" >&2
        exit 1
        ;;
esac

if [[ ! -x "$scanner" ]]; then
    printf 'locked gitleaks executable is missing\n' >&2
    exit 1
fi
expected_version="$(jq -er '.secretScanner.version' "$locks")"
expected_digest="$(jq -er --arg asset "$asset" \
    '.secretScanner.binarySha256[$asset]' "$locks")"
actual_digest="$(shasum -a 256 "$scanner" | awk '{print $1}')"
if [[ "$actual_digest" != "$expected_digest" ]]; then
    printf 'gitleaks binary mismatch: expected %s, got %s\n' \
        "$expected_digest" "$actual_digest" >&2
    exit 1
fi
actual_version="$("$scanner" version)"
if [[ "$actual_version" != "$expected_version" ]]; then
    printf 'gitleaks version mismatch: expected %s, got %s\n' \
        "$expected_version" "$actual_version" >&2
    exit 1
fi

printf 'gitleaks executable: PASS (%s)\n' "$asset"
