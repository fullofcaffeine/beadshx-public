#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
policy="$repository_root/release/identity-policy.json"
checker="$repository_root/scripts/beadshx/check-release-identity.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-release-identity.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

"$checker"

jq '.product.name = "Beads"' "$policy" >"$test_root/upstream-name.json"
if BEADSHX_IDENTITY_POLICY="$test_root/upstream-name.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'identity checker accepted an upstream product name\n' >&2
	exit 1
fi
grep -Fq 'does not match the admitted bootstrap contract' "$test_root/stderr"

jq '.compatibilityTarget.commit = "0000000000000000000000000000000000000000"' \
	"$policy" >"$test_root/wrong-upstream.json"
if BEADSHX_IDENTITY_POLICY="$test_root/wrong-upstream.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'identity checker accepted the wrong upstream commit\n' >&2
	exit 1
fi

jq '.bdAlias.status = "allowed"' "$policy" >"$test_root/early-alias.json"
if BEADSHX_IDENTITY_POLICY="$test_root/early-alias.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'identity checker accepted an early bd alias\n' >&2
	exit 1
fi

printf 'release identity rejection: PASS\n'
