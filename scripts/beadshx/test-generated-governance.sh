#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
checker="$repository_root/scripts/beadshx/check-generated-drift.sh"
fixture="$repository_root/engdocs/beadshx/generated/bootstrap-fixture.json"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-generated-policy.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

jq -e '
	.schemaVersion == 1 and
	.owners.compilerRevision == "c141ac6df83bff1e2a420f18146ce68e4d7a87c7" and
	(.owners.haxeSources | length) > 0 and
	(.files | length) > 0
' "$fixture" >/dev/null

grep -Fqx '/generated/go/*' "$repository_root/.gitignore"
grep -Fq 'Never edit generated Go' "$repository_root/generated/README.md"

"$checker"
jq '.files[0].sha256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
	"$fixture" >"$test_root/changed.json"
if BEADSHX_GENERATED_FIXTURE="$test_root/changed.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'generated drift checker accepted a changed byte fixture\n' >&2
	exit 1
fi
grep -Fq 'generated Go drift detected' "$test_root/stderr"
grep -Fq 'src/beadshx/bootstrap/Main.hx' "$test_root/stderr"
grep -Fq 'c141ac6df83bff1e2a420f18146ce68e4d7a87c7' "$test_root/stderr"

jq '.owners.haxeSources = []' "$fixture" >"$test_root/missing-owner.json"
if BEADSHX_GENERATED_FIXTURE="$test_root/missing-owner.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'generated drift checker accepted an incomplete owner inventory\n' >&2
	exit 1
fi
grep -Fq 'generated-source owner inventory changed' "$test_root/stderr"

jq '.owners.compilerRevision = "0000000000000000000000000000000000000000"' \
	"$fixture" >"$test_root/wrong-compiler.json"
if BEADSHX_GENERATED_FIXTURE="$test_root/wrong-compiler.json" \
	"$checker" >"$test_root/stdout" 2>"$test_root/stderr"; then
	printf 'generated drift checker accepted the wrong compiler revision\n' >&2
	exit 1
fi
grep -Fq 'haxe.go compiler revision changed' "$test_root/stderr"

printf 'generated-source governance: PASS\n'
