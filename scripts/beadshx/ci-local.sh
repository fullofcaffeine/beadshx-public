#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
evidence_root="$repository_root/build/evidence/local-ci"
revision="$(git -C "$repository_root" rev-parse HEAD)"
index_tree="$(git -C "$repository_root" write-tree)"
results="$(jq -cn \
    --arg revision "$revision" \
    --arg indexTree "$index_tree" \
    '{
        schemaVersion:1,
        revision:$revision,
        indexTree:$indexTree,
        statusVocabulary:["success", "failure", "skipped"],
        overallStatus:"running",
        lanes:{}
    }')"

mkdir -p "$evidence_root"

record_result() {
    local lane="$1"
    local status="$2"
    local exit_code="$3"
    results="$(jq -c --arg lane "$lane" --arg status "$status" \
        --argjson exitCode "$exit_code" \
        '.lanes[$lane] = {status:$status, exitCode:$exitCode}' <<<"$results")"
    printf '%-16s %s\n' "$lane" "$status"
}

run_lane() {
    local lane="$1"
    shift
    local lane_root="$evidence_root/$lane"
    local log="$lane_root/lane.log"
    local status=success
    local exit_code=0

    mkdir -p "$lane_root"
    if "$@" >"$log" 2>&1; then
        :
    else
        exit_code=$?
        status=failure
    fi
    if ! "$repository_root/scripts/beadshx/report-locks.sh" \
        "$lane" "$lane_root/locks.json" >>"$log" 2>&1; then
        status=failure
        [[ "$exit_code" -ne 0 ]] || exit_code=1
    fi
    record_result "$lane" "$status" "$exit_code"
}

skip_lane() {
    local lane="$1"
    local reason="$2"
    local lane_root="$evidence_root/$lane"
    mkdir -p "$lane_root"
    printf '%s\n' "$reason" >"$lane_root/lane.log"
    record_result "$lane" skipped 0
}

run_lane bootstrap "$repository_root/scripts/beadshx/ci-lane.sh" bootstrap
run_lane upstream-oracle "$repository_root/scripts/beadshx/ci-lane.sh" upstream-oracle

bootstrap_status="$(jq -r '.lanes.bootstrap.status' <<<"$results")"
oracle_status="$(jq -r '.lanes["upstream-oracle"].status' <<<"$results")"
if [[ "$bootstrap_status" == success && "$oracle_status" == success ]]; then
    run_lane parity-smoke "$repository_root/scripts/beadshx/ci-lane.sh" parity-smoke
    run_lane proxied-readonly "$repository_root/scripts/beadshx/ci-lane.sh" proxied-readonly
else
    skip_lane parity-smoke 'Skipped because bootstrap or upstream-oracle failed.'
    skip_lane proxied-readonly 'Skipped because bootstrap or upstream-oracle failed.'
fi

if [[ "$bootstrap_status" == success ]]; then
    run_lane license "$repository_root/scripts/beadshx/ci-lane.sh" license
else
    skip_lane license 'Skipped because bootstrap failed.'
fi

run_lane output-contracts "$repository_root/scripts/beadshx/ci-lane.sh" output-contracts
run_lane performance-baseline "$repository_root/scripts/beadshx/ci-lane.sh" performance-baseline
run_lane secret-scan env \
    BEADSHX_SECRET_REPORT="$evidence_root/secret-scan/gitleaks.json" \
    "$repository_root/scripts/beadshx/ci-lane.sh" secret-scan

run_lane evidence-gate env \
    BOOTSTRAP="$bootstrap_status" \
    ORACLE="$oracle_status" \
    PARITY="$(jq -r '.lanes["parity-smoke"].status' <<<"$results")" \
    PROXIED_READONLY="$(jq -r '.lanes["proxied-readonly"].status' <<<"$results")" \
    LICENSE_RESULT="$(jq -r '.lanes.license.status' <<<"$results")" \
    OUTPUT_CONTRACTS="$(jq -r '.lanes["output-contracts"].status' <<<"$results")" \
    PERFORMANCE_BASELINE="$(jq -r '.lanes["performance-baseline"].status' <<<"$results")" \
    SECRETS="$(jq -r '.lanes["secret-scan"].status' <<<"$results")" \
    BEADSHX_GATE_REPORT="$evidence_root/evidence-gate/results.json" \
    "$repository_root/scripts/beadshx/ci-lane.sh" evidence-gate

gate_status="$(jq -r '.lanes["evidence-gate"].status' <<<"$results")"
if [[ "$gate_status" == success ]]; then
    results="$(jq -c '.overallStatus = "success"' <<<"$results")"
else
    results="$(jq -c '.overallStatus = "failure"' <<<"$results")"
fi
printf '%s\n' "$results" | jq . >"$evidence_root/results.json"

if [[ "$gate_status" != success ]]; then
    printf 'local CI: FAIL; read %s\n' \
        "$evidence_root/results.json" >&2
    exit 1
fi

printf 'local CI: PASS\n'
