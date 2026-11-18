#!/usr/bin/env bash
# Shared Go formatting check for Make and PR lint wrappers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'fmt-check must run inside a Git checkout\n' >&2
    exit 2
fi

# Check only Go files that Git tracks or would track. Ignored folders such as
# .toolchains/ and node_modules/ hold local tools and scratch programs.
GO_FILES=()
while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
        GO_FILES+=("$file")
    fi
done < <(git ls-files -z --cached --others --exclude-standard -- '*.go')

printf 'Checking Go formatting...\n'
if [[ ${#GO_FILES[@]} -eq 0 ]]; then
    UNFORMATTED=""
elif UNFORMATTED="$(gofmt -l "${GO_FILES[@]}")"; then
    :
else
    status=$?
    printf 'gofmt failed while checking formatting\n' >&2
    exit "$status"
fi

if [[ -n "$UNFORMATTED" ]]; then
    printf 'The following files are not properly formatted:\n'
    printf '%s\n' "$UNFORMATTED"
    printf '\n'
    printf "Run 'make fmt' to fix formatting\n"
    exit 1
fi

printf 'All Go files are properly formatted\n'
