#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
candidate="${BEADSHX_CANDIDATE_BIN:-$repository_root/build/bin/bdhx}"
oracle="${BEADSHX_ORACLE_BIN:-$repository_root/build/bin/bd-upstream}"

for binary in "$candidate" "$oracle"; do
	if [[ ! -x "$binary" ]]; then
		printf 'proxied read tracer binary is missing or not executable: %s\n' "$binary" >&2
		exit 1
	fi
done
if ! command -v docker >/dev/null 2>&1; then
	printf 'proxied read tracer requires Docker\n' >&2
	exit 1
fi
if ! docker image inspect dolthub/dolt-sql-server:2.2.0 >/dev/null 2>&1; then
	"$repository_root/scripts/ci/pull-dolt-image.sh"
fi

cd "$repository_root"
BEADS_TEST_PROXIED_SERVER=1 \
	BEADS_TEST_BD_BINARY="$oracle" \
	BEADSHX_CANDIDATE_BIN="$candidate" \
	CGO_ENABLED=1 \
	go test -tags gms_pure_go ./cmd/bd \
		-run '^TestBeadsHXProxiedReadonly$' -count=1 -v

printf 'BeadsHX proxied read-only parity: PASS\n'
