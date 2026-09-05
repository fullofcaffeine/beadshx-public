#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
descriptor="$repository_root/caf/providers/beadshx-task-port.intent.json"
checker="$repository_root/scripts/beadshx/check-caf-provider-intent.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-caf-intent.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

"$checker"

reject_fixture() {
	local name="$1"
	local filter="$2"
	local fixture="$test_root/$name.json"
	jq "$filter" "$descriptor" >"$fixture"
	if BEADSHX_CAF_INTENT="$fixture" "$checker" >/dev/null 2>&1; then
		printf 'Caf provider checker accepted invalid fixture: %s\n' "$name" >&2
		exit 1
	fi
}

reject_fixture selected '.selection.status = "selected"'
reject_fixture task-fact '.runtimeFacts.taskId = "beadshx-example"'
reject_fixture local-path '.identity.localPath = "/tmp/beadshx"'
reject_fixture broad-effect '.effectUpperBounds += ["caf.effect.beads.mutate"]'
reject_fixture success-claim '.claims.effectSuccess = true'

printf 'Caf provider intent rejection fixtures: PASS\n'
