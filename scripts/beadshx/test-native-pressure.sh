#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

go_toolchain="$(jq -er '.common.go' \
    engdocs/beadshx/program/toolchain-locks.json)"
export GOWORK=off
export GOTOOLCHAIN="$go_toolchain"

if [[ ! -d node_modules || ! -d haxe_libraries ]]; then
    ./scripts/beadshx/setup-haxe.sh
fi

go test ./scripts/beadshx/native-pressure
go run ./scripts/beadshx/native-pressure \
    --repository "$repository_root" \
    --check

inventory="compatibility/native-pressure/inventory.json.gz"
gzip -dc "$inventory" | jq -e '
    .schemaVersion == 1 and
    .source.version == "v1.2.1" and
    .source.commit == "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff" and
    .compilerEvidence.commit == "c1e3333d2ce358b451e69b2b1530030bc4083dd5" and
    .toolchain.go == "go1.26.5" and
    .toolchain.analyzer == "golang.org/x/tools/go/packages+go/types" and
    ([.profiles[].id] | sort) == ["portable-nocgo", "release-cgo"] and
    .coverage.profileCount == 2 and
    .coverage.reachableFirstPartyPackages > 0 and
    .coverage.boundaryPackageCount > 0 and
    .coverage.boundaryCount == (.boundaries | length) and
    .coverage.unmappedBoundaryCalls == 0 and
    .coverage.unmappedEffects == 0 and
    .coverage.unmappedProfiles == 0 and
    .coverage.unmappedOperations == 0 and
    (.coverage.boundariesByAxis | keys | sort) == [
        "callback", "cgo", "channel", "context", "generic", "interface",
        "multipleReturns", "platformSpecific", "pointer"
    ] and
    all(.coverage.boundariesByAxis[]; . > 0) and
    ([.featureRanks[].id] | length) == 7 and
    ([.featureRanks[].id] | length) ==
        ([.featureRanks[].id] | unique | length) and
    all(.featureRanks[];
        (.priority == "P0" or .priority == "P1") and
        (.observedCount > 0) and
        (.decision | length) > 0) and
    all(.dependencies[];
        (.packageRoot | length) > 0 and
        (.policyId | length) > 0 and
        (.owner | length) > 0 and
        (.boundaryCount > 0)) and
    ([.boundaries[].id] | length) ==
        ([.boundaries[].id] | unique | length) and
    all(.boundaries[];
        (.sourceLocators | length) > 0 and
        (.callerPackages | length) > 0 and
        (.callerSymbols | length) > 0 and
        (.targetPackage | length) > 0 and
        (.targetSymbol | length) > 0 and
        (.normalizedSignature | length) > 0 and
        (.commandProfiles | length) > 0 and
        (.operationIds | length) > 0 and
        (.effectIds | length) > 0 and
        (.buildProfiles | length) > 0 and
        (.semanticRole | length) > 0 and
        (.selectedOwner == "authored-haxe-first-party-port") and
        (.facadeId | length) > 0 and
        (.haxeGoEvidence | length) > 0 and
        (.severity == "P0" or .severity == "P1") and
        (.reducedFixture | length) > 0 and
        .waiver == null)
' >/dev/null

artifact_bytes="$(wc -c <"$inventory" | tr -d ' ')"
if [[ "$artifact_bytes" -gt 1048576 ]]; then
    printf 'native-pressure inventory is %s bytes; expected at most 1048576\n' \
        "$artifact_bytes" >&2
    exit 1
fi

tracer_root="build/evidence/native-pressure/simple-facade"
cleanup() {
    if [[ -d "$tracer_root" ]]; then
        find "$tracer_root" -mindepth 1 -delete
        rmdir "$tracer_root"
    fi
}
trap cleanup EXIT
cleanup

npx haxe test/native-pressure/simple_facade/compile.hxml -D go_no_build
(
    cd "$tracer_root"
    go test ./...
)
actual_output="$(cd "$tracer_root" && go run .)"
if ! diff -u test/native-pressure/simple_facade/expected.stdout \
    <(printf '%s\n' "$actual_output"); then
    printf 'typed native-pressure tracer output differs\n' >&2
    exit 1
fi

summary="$(gzip -dc "$inventory" | jq -r '
    [.coverage.reachableFirstPartyPackages,
     .coverage.boundaryPackageCount,
     .coverage.boundaryCount,
     .coverage.boundariesByAxis.cgo] | @tsv
')"
IFS=$'\t' read -r reachable boundary_packages boundaries cgo_boundaries \
    <<<"$summary"
printf 'native pressure: PASS (%s reachable packages; %s boundary packages; %s typed APIs; %s CGO-only APIs; typed Haxe tracer passed)\n' \
    "$reachable" "$boundary_packages" "$boundaries" "$cgo_boundaries"
