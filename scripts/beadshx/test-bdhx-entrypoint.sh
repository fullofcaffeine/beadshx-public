#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
policy="$repository_root/release/identity-policy.json"
project="$repository_root/compile.bdhx.json"
candidate="${BEADSHX_CANDIDATE_BIN:-$repository_root/build/bin/bdhx}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-entrypoint.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

expected_identity="$(jq -er '.binaries.developmentIdentity' "$policy")"

jq -e '
	.schemaVersion == 1 and
	.mode == "existing-module" and
	.moduleRoot == "." and
	.packageDir == "generated/go/bdhx" and
	.packageName == "main" and
	.runtimeDir == "generated/go/hxrt" and
	.entrypoint == {"kind":"compiler-main"} and
	.build == {"kind":"none"}
' "$project" >/dev/null

grep -Fqx -- '-D go_output=generated/go/bdhx' "$repository_root/compile.bootstrap.hxml"
grep -Fqx -- '-D reflaxe_go_project=compile.bdhx.json' "$repository_root/compile.bootstrap.hxml"

if [[ ! -x "$candidate" ]]; then
	printf 'bdhx candidate is missing: %s\n' "$candidate" >&2
	exit 1
fi

# Bare invocation now renders Haxe-owned root help. Exercise the stable identity
# through its command so this entrypoint check does not duplicate CLI help tests.
first="$(cd "$test_root" && "$candidate" version)"
second="$(cd "$test_root" && "$candidate" version)"
if [[ "$first" != "$expected_identity" || "$second" != "$expected_identity" ]]; then
	printf 'unexpected bdhx identity: %s\n' "$first" >&2
	exit 1
fi
if [[ -n "$(find "$test_root" -mindepth 1 -print -quit)" ]]; then
	printf 'bdhx startup mutated its workspace\n' >&2
	exit 1
fi

printf 'bdhx entrypoint: PASS\n'
