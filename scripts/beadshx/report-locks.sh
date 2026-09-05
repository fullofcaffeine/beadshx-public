#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
lane="${1:?usage: report-locks.sh LANE [OUTPUT]}"
output="${2:-}"

report="$(jq -n \
    --arg lane "$lane" \
    --arg commit "$(git -C "$repository_root" rev-parse HEAD)" \
    --arg imageOS "${ImageOS:-local}" \
    --arg imageVersion "${ImageVersion:-local}" \
    --arg kernel "$(uname -srm)" \
    --arg go "$(go env GOVERSION 2>/dev/null || printf 'unavailable')" \
    --arg node "$(node --version 2>/dev/null || printf 'unavailable')" \
    --arg gcc "$(gcc -dumpfullversion -dumpversion 2>/dev/null || printf 'unavailable')" \
    --slurpfile sources "$repository_root/engdocs/beadshx/program/source-locks.json" \
    --slurpfile tools "$repository_root/engdocs/beadshx/program/toolchain-locks.json" \
    '{
        lane: $lane,
        commit: $commit,
        runtime: {
            imageOS: $imageOS,
            imageVersion: $imageVersion,
            kernel: $kernel,
            go: $go,
            node: $node,
            gcc: $gcc
        },
        sourceLocks: $sources[0],
        toolchainLocks: $tools[0]
    }')"

printf '%s\n' "$report"
if [[ -n "$output" ]]; then
    mkdir -p "$(dirname "$output")"
    printf '%s\n' "$report" >"$output"
fi
