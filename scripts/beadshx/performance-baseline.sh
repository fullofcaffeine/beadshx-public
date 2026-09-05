#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
operation="${1:-}"
shift || true
go_toolchain="$(jq -er '.common.go' \
    "$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
export GOWORK=off
export GOTOOLCHAIN="$go_toolchain"

usage() {
    printf 'usage: %s capture --run-id ID [--source-repository PATH] | comparison | check\n' "$0" >&2
}

case "$operation" in
capture)
    run_id=""
    source_repository="$repository_root/../beads"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --run-id)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            run_id="$2"
            shift 2
            ;;
        --source-repository)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            source_repository="$2"
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
        esac
    done
    [[ -n "$run_id" ]] || { usage; exit 2; }
    preparation="$repository_root/build/evidence/performance-baseline/work/$run_id/preparation.json"
    if [[ ! -f "$preparation" ]]; then
        (
            cd "$repository_root"
            go run ./scripts/beadshx/performance-baseline \
                --repository "$repository_root" \
                --prepare-run "$run_id" \
                --source-repository "$source_repository"
        )
    fi
    (
        cd "$repository_root"
        go run ./scripts/beadshx/performance-baseline \
            --repository "$repository_root" --run-prepared "$run_id"
        go run ./scripts/beadshx/performance-baseline \
            --repository "$repository_root" --summarize-prepared "$run_id"
        go run ./scripts/beadshx/performance-baseline \
            --repository "$repository_root" --publish-prepared "$run_id"
    )
    ;;
check)
    [[ $# -eq 0 ]] || { usage; exit 2; }
    (
        cd "$repository_root"
        go run ./scripts/beadshx/performance-baseline \
            --repository "$repository_root" --check-published
    )
    ;;
comparison)
    [[ $# -eq 0 ]] || { usage; exit 2; }
    (
        cd "$repository_root"
        go run ./scripts/beadshx/performance-baseline \
            --repository "$repository_root" --write-comparison
    )
    ;;
*)
    usage
    exit 2
    ;;
esac
