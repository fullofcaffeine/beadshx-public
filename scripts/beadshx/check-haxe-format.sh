#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
lix="$repository_root/node_modules/.bin/lix"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
export PATH="$repository_root/node_modules/.bin:$PATH"

if [[ ! -x "$lix" ]]; then
    printf 'Haxe formatter check requires the locked npm tools; run npm ci\n' >&2
    exit 1
fi

expected="$(jq -er '.common.haxeFormatter' "$locks")"
actual="$(cd "$repository_root" && "$lix" run formatter --help 2>&1 | \
    sed -n -E 's/^Haxe Formatter ([0-9.]+)$/\1/p' | head -n 1)"
if [[ "$actual" != "$expected" ]]; then
    printf 'Haxe Formatter mismatch: expected %s, got %s\n' \
        "$expected" "${actual:-unavailable}" >&2
    printf 'Run npm run setup:haxe to install the locked formatter.\n' >&2
    exit 1
fi

if [[ "${1:-}" == "--staged" ]]; then
    if [[ $# -ne 1 ]]; then
        printf 'usage: %s [--staged|HAXE_FILE ...]\n' "$0" >&2
        exit 2
    fi

    staged_files=()
    while IFS= read -r -d '' source; do
        staged_files+=("$source")
    done < <(git -C "$repository_root" diff --cached --name-only \
        --diff-filter=ACMR -z -- '*.hx')

    if [[ ${#staged_files[@]} -eq 0 ]]; then
        exit 0
    fi

    temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-haxe-format.XXXXXX")"
    trap 'find "$temporary_root" -mindepth 1 -delete; rmdir "$temporary_root"' EXIT
    for source in "${staged_files[@]}"; do
        staged_source="$temporary_root/staged.hx"
        formatted_source="$temporary_root/formatted.hx"
        git -C "$repository_root" show ":$source" >"$staged_source"
        (
            cd "$repository_root"
            "$lix" run formatter --stdin -s "$repository_root/$source" \
                <"$staged_source" >"$formatted_source"
        )
        # The formatter's stdin mode prints one newline after its formatted
        # file content. Normalize that transport newline to the repository's
        # single end-of-file newline before comparing bytes.
        python3 - "$formatted_source" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_bytes(path.read_bytes().rstrip(b"\n") + b"\n")
PY
        if ! cmp -s "$staged_source" "$formatted_source"; then
            printf 'Haxe formatting differs in staged file: %s\n' "$source" >&2
            diff -u --label "$source (staged)" --label "$source (formatted)" \
                "$staged_source" "$formatted_source" >&2 || true
            exit 1
        fi
    done

    printf 'staged Haxe formatting: PASS\n'
    exit 0
fi

format_args=()
if [[ $# -gt 0 ]]; then
    for source in "$@"; do
        case "$source" in
            *.hx) ;;
            *)
                printf 'Haxe formatter received a non-Haxe path: %s\n' "$source" >&2
                exit 2
                ;;
        esac
        if [[ -f "$repository_root/$source" ]]; then
            format_args+=("-s" "$repository_root/$source")
        fi
    done
else
    while IFS= read -r source; do
        format_args+=("-s" "$source")
    done < <(find "$repository_root/src/beadshx" -type f -name '*.hx' | sort)
fi

if [[ ${#format_args[@]} -eq 0 ]]; then
    exit 0
fi

cd "$repository_root"
"$lix" run formatter "${format_args[@]}" --check
printf 'Haxe formatting: PASS\n'
