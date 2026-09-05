#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

./scripts/beadshx/setup-haxe.sh
shasum -a 256 -c beadshx-prd-sha256.txt
jq empty beadshx-complete-backlog.json engdocs/beadshx/program/source-locks.json upstream/locks/*.json
./scripts/beadshx/test-toolchain-locks.sh
if [[ -n "${BEADSHX_TOOLCHAIN_PROFILE:-}" ]]; then
    ./scripts/beadshx/verify-toolchains.sh \
        "--profile=$BEADSHX_TOOLCHAIN_PROFILE"
else
    ./scripts/beadshx/verify-toolchains.sh
fi
baseline="$(jq -er '.compatibilityTarget.commit' \
    engdocs/beadshx/program/source-locks.json)"
./scripts/beadshx/check-local-paths-staged.sh --range "$baseline..HEAD"
./scripts/beadshx/check-haxe-format.sh
./scripts/beadshx/test-repository-safety.sh
./scripts/beadshx/test-ci-lanes.sh
./scripts/beadshx/check-program-ledger.sh
./scripts/beadshx/test-data-safety.sh
./scripts/beadshx/test-command-surface.sh
./scripts/beadshx/test-generated-governance.sh
./scripts/beadshx/test-release-identity.sh
./scripts/beadshx/test-caf-provider-intent.sh
./scripts/beadshx/test-command-inventory.sh
./scripts/beadshx/test-error-contracts.sh
./scripts/beadshx/test-storage-contracts.sh
./scripts/beadshx/test-effect-contracts.sh
./scripts/beadshx/test-daily-workflow.sh --require-approved
./scripts/beadshx/test-native-pressure.sh
./scripts/beadshx/schema-migration-graph.sh check
./scripts/beadshx/generate-source.sh
./scripts/beadshx/build-generated.sh
./scripts/beadshx/check-license-plan.sh
git diff --check
