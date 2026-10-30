#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
ledger="$repository_root/engdocs/beadshx/program/ledger.tsv"
expected_header=$'ts\tphase\tdecision\twhy\tevidence\tresult'

if [[ ! -f "$ledger" ]]; then
    printf 'program ledger is missing: %s\n' "$ledger" >&2
    exit 1
fi

if [[ "$(sed -n '1p' "$ledger")" != "$expected_header" ]]; then
    printf 'program ledger header does not match the required schema\n' >&2
    exit 1
fi

awk -F '\t' '
    function fail(message) {
        printf "program ledger line %d: %s\n", NR, message > "/dev/stderr"
        errors = 1
    }

    NR == 1 { next }

    {
        if (NF != 6) fail("expected six TSV cells")
        for (cell = 1; cell <= NF; cell++) {
            if ($cell == "") fail("empty cell")
            if ($cell ~ /^[=+@-]/) fail("unsafe spreadsheet formula prefix")
        }
        if ($1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) {
            fail("timestamp must use UTC ISO 8601 format")
        }
        if ($5 !~ /(^|; )issue:beadshx-[a-z0-9.-]+(;|$)/) fail("missing BeadsHX issue reference")
        if ($5 !~ /(^|; )commit:(WORKTREE|[0-9a-f]+)(;|$)/) fail("missing commit reference")
        if ($5 !~ /(^|; )artifact:[^;]+(;|$)/) fail("missing artifact reference")
        if ($6 !~ /(^|; )state:(worktree|committed|blocked|superseded)(;|$)/) fail("missing result state")
        if ($6 !~ /(^|; )disposition:[a-z0-9-]+(;|$)/) fail("missing disposition")
        if ($5 ~ /(^|; )commit:WORKTREE(;|$)/ && $6 !~ /(^|; )state:worktree(;|$)/) {
            fail("WORKTREE commit requires worktree state")
        }
        if ($5 !~ /(^|; )commit:WORKTREE(;|$)/ && $6 ~ /(^|; )state:worktree(;|$)/) {
            fail("worktree state requires WORKTREE commit")
        }
    }

    END {
        if (NR < 2) fail("ledger has no decision rows")
        exit errors
    }
' "$ledger"

while IFS=$'\t' read -r _ _ _ _ evidence _; do
    artifact="${evidence#*artifact:}"
    artifact="${artifact%%;*}"
    case "$artifact" in
        /*|../*|*/../*|*/..)
            printf 'program ledger artifact escapes the repository: %s\n' "$artifact" >&2
            exit 1
            ;;
    esac
    if [[ ! -e "$repository_root/$artifact" ]]; then
        printf 'program ledger artifact does not exist: %s\n' "$artifact" >&2
        exit 1
    fi
done < <(tail -n +2 "$ledger")

printf 'program ledger: PASS\n'
