#!/usr/bin/env bash
# Validate the compatibility manifest (BHX-M02-10): its JSON Schema, the
# semantic and drift rules, and the freshness of the generated report. Then
# prove that the gate rejects every negative fixture in compatibility/testdata.
#
#   check-compatibility-manifest.sh                 check the manifest and run the fixtures
#   check-compatibility-manifest.sh --write-report  regenerate the report, then check
#   check-compatibility-manifest.sh -- <flags>      run the gate once with its own flags,
#                                                   for example -command-inventory <file>
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
go_toolchain="$(jq -er '.common.go' "$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
manifest="compatibility/manifests/beads-v1.2.1.json"
inventory="compatibility/upstream-v1.2.1-command-inventory.json.gz"
fixture_root="compatibility/testdata/invalid"
# The audit's minimum negative set. Each must exist and fail for its own reason.
required_fixtures=(missing-command extra-command dangling-id false-none stale-evidence
	wildcard-waiver pending-waiver d0-full-coverage inventory-drift report-drift)

work_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-compatibility-manifest.XXXXXX")"
cleanup() {
	: "${work_root:?}"
	rm -rf -- "$work_root"
}
trap cleanup EXIT

gate="$work_root/compatibility-manifest"
(
	cd "$repository_root"
	GOWORK=off GOTOOLCHAIN="$go_toolchain" GOFLAGS=-mod=readonly CGO_ENABLED=0 \
		go build -o "$gate" ./scripts/beadshx/compatibility-manifest
)
run_gate() {
	"$gate" -repository "$repository_root" "$@"
}

case "${1:-}" in
--)
	shift
	run_gate "$@"
	exit
	;;
--write-report)
	run_gate -write-report
	;;
"") ;;
*)
	printf 'usage: %s [--write-report | -- <gate flags>]\n' "$0" >&2
	exit 2
	;;
esac

run_gate

for name in "${required_fixtures[@]}"; do
	if [[ ! -f "$repository_root/$fixture_root/$name.json" ]]; then
		printf 'compatibility manifest fixture is missing: %s/%s.json\n' "$fixture_root" "$name" >&2
		exit 1
	fi
done

fixture_count=0
for fixture in "$repository_root/$fixture_root"/*.json; do
	name="$(basename "$fixture" .json)"
	case_manifest="$work_root/$name.manifest.json"
	jq "$(jq -er '.filter' "$fixture")" "$repository_root/$manifest" >"$case_manifest"
	arguments=(-manifest "$case_manifest")
	changed=0
	if ! cmp -s "$case_manifest" <(jq . "$repository_root/$manifest"); then
		changed=1
	fi
	if inventory_filter="$(jq -er '.inventoryFilter // empty' "$fixture")" && [[ -n "$inventory_filter" ]]; then
		case_inventory="$work_root/$name.inventory.json.gz"
		gzip -dc "$repository_root/$inventory" | jq -c "$inventory_filter" | gzip -n >"$case_inventory"
		arguments+=(-command-inventory "$case_inventory")
		changed=1
	fi
	if [[ "$changed" -ne 1 ]]; then
		printf 'compatibility manifest fixture changes nothing: %s\n' "$name" >&2
		exit 1
	fi
	if [[ "$(jq -r '.checkReport // false' "$fixture")" != true ]]; then
		arguments+=(-skip-report)
	fi
	if run_gate "${arguments[@]}" >"$work_root/$name.stdout" 2>"$work_root/$name.stderr"; then
		printf 'compatibility manifest gate accepted the invalid fixture %s\n' "$name" >&2
		exit 1
	fi
	while IFS= read -r expected; do
		if ! grep -Fq -- "$expected" "$work_root/$name.stderr"; then
			printf 'compatibility manifest fixture %s failed without: %s\n' "$name" "$expected" >&2
			cat "$work_root/$name.stderr" >&2
			exit 1
		fi
	done < <(jq -r '.expect[]' "$fixture")
	fixture_count=$((fixture_count + 1))
done

printf 'compatibility manifest fixtures: PASS (%d rejected)\n' "$fixture_count"
