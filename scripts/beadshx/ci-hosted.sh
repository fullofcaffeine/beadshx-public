#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
lane="${1:-}"

case "$lane" in
    bootstrap) evidence_name=bootstrap ;;
    upstream-oracle) evidence_name=oracle ;;
    parity-smoke) evidence_name=parity ;;
    proxied-readonly) evidence_name=proxied-readonly ;;
    license) evidence_name=license ;;
    output-contracts) evidence_name=output-contracts ;;
    performance-baseline) evidence_name=performance-baseline ;;
    secret-scan) evidence_name=secrets ;;
    evidence-gate) evidence_name=gate ;;
    *)
        printf 'usage: %s {bootstrap|upstream-oracle|parity-smoke|proxied-readonly|license|output-contracts|performance-baseline|secret-scan|evidence-gate}\n' \
            "$0" >&2
        exit 2
        ;;
esac

evidence_root="$repository_root/build/evidence/$evidence_name"
log="$evidence_root/lane.log"
mkdir -p "$evidence_root"

lane_status=0
if {
    "$repository_root/scripts/beadshx/verify-runner.sh" --profile=linux-ci
    if [[ "$lane" == parity-smoke || "$lane" == proxied-readonly ]]; then
        chmod +x "$repository_root/build/evidence/candidate/bdhx" \
            "$repository_root/build/evidence/oracle/bd-upstream"
    fi
    "$repository_root/scripts/beadshx/ci-lane.sh" "$lane"
} >"$log" 2>&1; then
    lane_result=success
else
    lane_status=$?
    lane_result=failure
fi

case "$lane" in
    bootstrap)
        if [[ -f "$repository_root/build/bin/bdhx" ]]; then
            cp "$repository_root/build/bin/bdhx" "$evidence_root/bdhx"
        fi
        if [[ -d "$repository_root/LICENSES" ]]; then
            mkdir -p "$evidence_root/LICENSES"
            cp "$repository_root"/LICENSES/* \
                "$evidence_root/LICENSES/"
        fi
        ;;
    upstream-oracle)
        if [[ -f "$repository_root/build/bin/bd-upstream" ]]; then
            cp "$repository_root/build/bin/bd-upstream" "$evidence_root/bd-upstream"
        fi
        ;;
    license)
        if [[ -f "$repository_root/build/evidence/bootstrap/SHA256SUMS" ]]; then
            cp "$repository_root/build/evidence/bootstrap/SHA256SUMS" \
                "$evidence_root/bootstrap-SHA256SUMS"
        fi
        ;;
esac

checksum_status=0
case "$lane" in
    bootstrap)
        checksum_inputs=()
        [[ -f "$evidence_root/bdhx" ]] && checksum_inputs+=(bdhx)
        if [[ -d "$evidence_root/LICENSES" ]]; then
            while IFS= read -r -d '' license; do
                checksum_inputs+=("${license#"$evidence_root/"}")
            done < <(find "$evidence_root/LICENSES" -type f -print0)
        fi
        if [[ ${#checksum_inputs[@]} -ne 0 ]]; then
            (cd "$evidence_root" && sha256sum "${checksum_inputs[@]}" >SHA256SUMS) || \
                checksum_status=$?
        fi
        ;;
    upstream-oracle)
        if [[ -f "$evidence_root/bd-upstream" ]]; then
            (cd "$evidence_root" && sha256sum bd-upstream >SHA256SUMS) || \
                checksum_status=$?
        fi
        ;;
esac

locks_status=0
if "$repository_root/scripts/beadshx/report-locks.sh" \
    "$lane" "$evidence_root/locks.json" >>"$log" 2>&1; then
    :
else
    locks_status=$?
fi

final_status="$lane_status"
if [[ "$final_status" -eq 0 && "$checksum_status" -ne 0 ]]; then
    final_status="$checksum_status"
    lane_result=failure
fi
if [[ "$final_status" -eq 0 && "$locks_status" -ne 0 ]]; then
    final_status="$locks_status"
    lane_result=failure
fi

jq -n \
    --argjson schemaVersion 1 \
    --arg revision "$(git -C "$repository_root" rev-parse HEAD)" \
    --arg lane "$lane" \
    --arg status "$lane_result" \
    --argjson exitCode "$final_status" \
    --argjson laneExitCode "$lane_status" \
    --argjson evidenceExitCode "$checksum_status" \
    --argjson locksExitCode "$locks_status" \
    '{
        schemaVersion:$schemaVersion,
        revision:$revision,
        statusVocabulary:["success", "failure"],
        lane:$lane,
        status:$status,
        exitCode:$exitCode,
        laneExitCode:$laneExitCode,
        evidenceExitCode:$evidenceExitCode,
        locksExitCode:$locksExitCode
    }' >"$evidence_root/result.json"

cat "$log"
exit "$final_status"
