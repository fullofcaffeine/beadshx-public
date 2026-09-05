#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
go_toolchain="$(jq -er '.common.go' \
    "$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
export GOWORK=off
export GOTOOLCHAIN="$go_toolchain"
cd "$repository_root"

go test ./scripts/beadshx/command-inventory
go run ./scripts/beadshx/command-inventory \
    --repository "$repository_root" \
    --check

gzip -dc compatibility/upstream-v1.2.1-command-inventory.json.gz | jq -e '
    .schemaVersion == 1 and
    .source.version == "v1.2.1" and
    .source.commit == "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff" and
    .toolchain.go == "go1.26.5" and
    .toolchain.cobra == "v1.10.2" and
    (.profiles | length) == 2 and
    (.activations | length) == 2 and
    .coverage.snapshotCount == 4 and
    .coverage.commandInstances > 0 and
    .coverage.flagDeclarations > 0 and
    .coverage.obligationCount > 0 and
    .coverage.unresolved == 0 and
    .coverage.orphaned == 0 and
    .coverage.conflicting == 0 and
    .coverage.unexpectedGlobalFlags == 0
' >/dev/null

printf 'command inventory: PASS\n'
