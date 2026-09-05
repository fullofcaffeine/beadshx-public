#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
cd "$repository_root"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-staged-go.XXXXXX")"
trap 'find "$temporary_root" -mindepth 1 -delete; rmdir "$temporary_root"' EXIT

initial_tree="$(git write-tree)"
staged_paths=()
staged_oids=()

# Rename detection is disabled deliberately. A rename is represented as one
# deletion and one addition, so the destination cannot bypass this check.
while IFS= read -r -d '' header && IFS= read -r -d '' path; do
    read -r old_mode new_mode old_oid new_oid status <<<"${header#:}"
    case "$status" in
        A|M|T) ;;
        *) continue ;;
    esac
    case "$new_mode" in
        100644|100755) ;;
        *)
            printf 'staged Go check rejects non-regular index entry %q (mode %s)\n' \
                "$path" "$new_mode" >&2
            exit 1
            ;;
    esac
    staged_paths+=("$path")
    staged_oids+=("$new_oid")
done < <(git diff-index --cached --raw -z --full-index --no-renames HEAD -- '*.go')

if [[ ${#staged_paths[@]} -eq 0 ]]; then
    exit 0
fi

if [[ "$(git write-tree)" != "$initial_tree" ]]; then
    printf 'staged Go check stopped because the index changed during inspection\n' >&2
    exit 1
fi

go_toolchain="$(jq -er '.common.go' "$locks")"
goroot="$(GOWORK=off GOTOOLCHAIN="$go_toolchain" go env GOROOT)"
locked_go="$goroot/bin/go"
locked_gofmt="$goroot/bin/gofmt"
if [[ ! -x "$locked_go" || ! -x "$locked_gofmt" ]]; then
    printf 'locked Go tools are unavailable under %s\n' "$goroot" >&2
    exit 1
fi
if [[ "$(GOWORK=off "$locked_go" env GOVERSION)" != "$go_toolchain" ]]; then
    printf 'locked Go toolchain did not resolve to %s\n' "$go_toolchain" >&2
    exit 1
fi

check_worktree_copy() {
    local path="$1"
    local expected="$2"
    python3 - "$repository_root" "$path" "$expected" <<'PY'
import os
import stat
import sys

root, relative, expected_path = sys.argv[1:]
candidate = os.path.abspath(os.path.join(root, relative))
try:
    if os.path.commonpath((root, candidate)) != root:
        raise ValueError("path escapes the repository")
except ValueError as error:
    print(f"staged Go check rejects {relative!r}: {error}", file=sys.stderr)
    raise SystemExit(1)

flags = os.O_RDONLY
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
try:
    descriptor = os.open(candidate, flags)
except OSError as error:
    print(f"staged Go check cannot safely open {relative!r}: {error}", file=sys.stderr)
    raise SystemExit(1)
try:
    details = os.fstat(descriptor)
    if not stat.S_ISREG(details.st_mode):
        print(f"staged Go check rejects non-regular worktree file {relative!r}", file=sys.stderr)
        raise SystemExit(1)
    with os.fdopen(descriptor, "rb", closefd=False) as source:
        actual = source.read()
finally:
    os.close(descriptor)

with open(expected_path, "rb") as source:
    expected = source.read()
if actual != expected:
    print(
        f"staged Go check refuses {relative!r} because its worktree bytes differ from the index",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

for index in "${!staged_paths[@]}"; do
    path="${staged_paths[$index]}"
    oid="${staged_oids[$index]}"
    original="$temporary_root/$index.original.go"
    formatted="$temporary_root/$index.formatted.go"
    git cat-file blob "$oid" >"$original"
    cp "$original" "$formatted"
    "$locked_gofmt" -w "$formatted"
    if ! cmp -s "$original" "$formatted"; then
        printf 'staged Go file is not formatted: %q\n' "$path" >&2
        diff -u --label "staged:$path" --label "gofmt:$path" \
            "$original" "$formatted" >&2 || true
        exit 1
    fi
    check_worktree_copy "$path" "$original"
done

"$repository_root/scripts/beadshx/run-golangci.sh" --new-from-rev=HEAD

if [[ "$(git write-tree)" != "$initial_tree" ]]; then
    printf 'staged Go check stopped because the index changed during lint\n' >&2
    exit 1
fi
for index in "${!staged_paths[@]}"; do
    check_worktree_copy "${staged_paths[$index]}" \
        "$temporary_root/$index.original.go"
done

printf 'staged Go formatting and lint: PASS\n'
