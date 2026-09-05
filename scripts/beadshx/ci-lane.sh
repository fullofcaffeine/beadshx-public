#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
lane="${1:-}"
go_toolchain="$(jq -er '.common.go' \
    "$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
export GOWORK=off
export GOTOOLCHAIN="$go_toolchain"

if [[ $# -ne 1 ]]; then
    printf 'usage: %s {bootstrap|upstream-oracle|parity-smoke|proxied-readonly|license|output-contracts|performance-baseline|secret-scan|evidence-gate}\n' \
        "$0" >&2
    exit 2
fi

case "$lane" in
    bootstrap)
        if [[ -n "${BEADSHX_TOOLCHAIN_PROFILE:-}" ]]; then
            export BEADSHX_TOOLCHAIN_PROFILE
        fi
        "$repository_root/scripts/beadshx/check-bootstrap.sh"
        ;;
    upstream-oracle)
        "$repository_root/scripts/beadshx/build-upstream-oracle.sh"
        ;;
    parity-smoke)
        candidate="${BEADSHX_CANDIDATE_BIN:-$repository_root/build/bin/bdhx}"
        oracle="${BEADSHX_ORACLE_BIN:-$repository_root/build/bin/bd-upstream}"
        "$repository_root/scripts/beadshx/test-parity-smoke.sh" \
            "$oracle" "$candidate"
        ;;
    proxied-readonly)
        "$repository_root/scripts/beadshx/test-proxied-readonly.sh"
        ;;
    license)
        "$repository_root/scripts/beadshx/check-license-plan.sh"
        ;;
    output-contracts)
        "$repository_root/scripts/beadshx/test-output-contracts.sh"
        ;;
    performance-baseline)
        "$repository_root/scripts/beadshx/performance-baseline.sh" check
        ;;
    secret-scan)
        report="${BEADSHX_SECRET_REPORT:-$repository_root/build/evidence/secrets/gitleaks.json}"
        "$repository_root/scripts/beadshx/scan-secrets.sh" "$report"
        ;;
    evidence-gate)
        gate_report="${BEADSHX_GATE_REPORT:-$repository_root/build/evidence/gate/results.json}"
        mkdir -p "$(dirname "$gate_report")"
        jq -n \
            --argjson schemaVersion 1 \
            --arg revision "$(git -C "$repository_root" rev-parse HEAD)" \
            --arg bootstrap "${BOOTSTRAP:-missing}" \
            --arg oracle "${ORACLE:-missing}" \
            --arg parity "${PARITY:-missing}" \
            --arg proxiedReadonly "${PROXIED_READONLY:-missing}" \
            --arg license "${LICENSE_RESULT:-missing}" \
            --arg outputContracts "${OUTPUT_CONTRACTS:-missing}" \
            --arg performanceBaseline "${PERFORMANCE_BASELINE:-missing}" \
            --arg secrets "${SECRETS:-missing}" \
            '{
                schemaVersion:$schemaVersion,
                revision:$revision,
                statusVocabulary:["success", "failure", "skipped", "cancelled", "missing"],
                lanes:{
                    bootstrap:$bootstrap,
                    "upstream-oracle":$oracle,
                    "parity-smoke":$parity,
                    "proxied-readonly":$proxiedReadonly,
                    license:$license,
                    "output-contracts":$outputContracts,
                    "performance-baseline":$performanceBaseline,
                    "secret-scan":$secrets
                }
            }' \
            | tee "$gate_report"
        jq -e 'all(.lanes[]; . == "success")' "$gate_report" >/dev/null
        ;;
    *)
        printf 'unknown CI lane: %s\n' "$lane" >&2
        exit 2
        ;;
esac
