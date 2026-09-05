#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
commit="$(jq -er '.commit' "$repository_root/upstream/locks/beads-v1.2.1.json")"
worktree_parent="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-oracle.XXXXXX")"
worktree="$worktree_parent/source"
output="$repository_root/build/bin/bd-upstream"

cleanup() {
    if [[ -d "$worktree" ]]; then
        git -C "$repository_root" worktree remove --force "$worktree"
    fi
    rmdir "$worktree_parent"
}
trap cleanup EXIT

git -C "$repository_root" worktree add --quiet --detach "$worktree" "$commit"
(
    cd "$worktree"
    go test ./internal/atomicfile
    make build
)

mkdir -p "$(dirname "$output")"
install -m 0755 "$worktree/bd" "$output"
identity="$($output version)"
if [[ "$identity" != *'1.2.1'* || "$identity" != *'634cbbc4b'* ]]; then
    printf 'unexpected upstream identity: %s\n' "$identity" >&2
    exit 1
fi
printf '%s\n' "$identity"
