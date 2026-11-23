#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
dispatcher="$repository_root/scripts/beadshx/command.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-command-surface.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

# The build outputs of this checkout, which later gate steps use: the bdhx candidate and the
# upstream oracle in build/bin, the package, the generated Go and its licenses.
build_outputs() {
	local path
	for path in build/bin build/packages LICENSES generated/go; do
		if [[ -d "$repository_root/$path" ]]; then
			(cd "$repository_root" && find "$path" -maxdepth 2 ! -type d -print)
		fi
	done | LC_ALL=C sort
}
outputs_before="$(build_outputs)"

for command_name in setup bootstrap generate build oracle inventory inventory-check output-contracts error-contracts storage-contracts effect-contracts native-pressure schema-migrations test-focused generated identity caf-intent parity test ci-local format lint package clean; do
	grep -Fq "bash scripts/beadshx/command.sh $command_name" "$repository_root/package.json"
done

if "$dispatcher" unknown >"$fixture_root/result.json"; then
	printf 'command dispatcher accepted an unknown command\n' >&2
	exit 1
fi
jq -e '
	.command == "unknown" and
	.status == "fail" and
	.exitCode == 2
' "$fixture_root/result.json" >/dev/null
grep -Fq 'usage:' "$repository_root/build/evidence/commands/unknown.log"

printf '%s\n' '#!/usr/bin/env bash' \
	'if [[ "${1:-}" == env && "${2:-}" == GOWORK ]]; then exit 0; fi' \
	'exit 7' >"$fixture_root/go"
expected_identity="$(jq -er '.binaries.developmentIdentity' \
	"$repository_root/release/identity-policy.json")"
printf '#!/usr/bin/env bash\nprintf '\''%%s\\n'\'' %q\n' "$expected_identity" \
	>"$fixture_root/bdhx"
chmod +x "$fixture_root/go" "$fixture_root/bdhx"
if BEADSHX_CANDIDATE_BIN="$fixture_root/bdhx" PATH="$fixture_root:$PATH" \
	"$dispatcher" test-focused >"$fixture_root/focused.json"; then
	printf 'command dispatcher masked a focused-test failure\n' >&2
	exit 1
fi
jq -e '
	.command == "test-focused" and
	.status == "fail" and
	.exitCode == 7
' "$fixture_root/focused.json" >/dev/null

# `clean` and `build` run in a disposable copy of the dispatcher and the scripts that they call, so
# this check never removes the outputs of this checkout. The copy holds one output of each kind.
clean_root="$fixture_root/checkout"
mkdir -p "$clean_root/scripts/beadshx" "$clean_root/engdocs/beadshx/program" \
	"$clean_root/build/bin" "$clean_root/build/packages" \
	"$clean_root/generated/go/bdhx" "$clean_root/generated/go/hxrt"
for script in command.sh clean-generated.sh build-generated.sh; do
	cp -f "$repository_root/scripts/beadshx/$script" "$clean_root/scripts/beadshx/$script"
done
cp -f "$repository_root/.buildflags" "$clean_root/.buildflags"
cp -f "$repository_root/engdocs/beadshx/program/toolchain-locks.json" \
	"$clean_root/engdocs/beadshx/program/toolchain-locks.json"
cp -f "$repository_root/generated/go/.gitignore" "$clean_root/generated/go/.gitignore"
seeded_outputs=(
	build/bin/bdhx
	build/bin/bd-upstream
	build/packages/beadshx-development-bootstrap.zip
	generated/go/bdhx/.reflaxe-go-owned.json
	generated/go/hxrt/hxrt.go
)
for output in "${seeded_outputs[@]}"; do
	touch "$clean_root/$output"
done
clean_dispatcher="$clean_root/scripts/beadshx/command.sh"

result="$($clean_dispatcher clean)"
jq -e '
	.schemaVersion == 1 and
	.command == "clean" and
	.status == "pass" and
	.exitCode == 0 and
	.log == "build/evidence/commands/clean.log"
' <<<"$result" >/dev/null
for output in "${seeded_outputs[@]}"; do
	if [[ -e "$clean_root/$output" ]]; then
		printf 'clean command left a build output: %s\n' "$output" >&2
		exit 1
	fi
done
if [[ ! -f "$clean_root/generated/go/.gitignore" ]]; then
	printf 'clean command removed the tracked generated/go/.gitignore\n' >&2
	exit 1
fi

result="$($clean_dispatcher build || true)"
jq -e '
	.schemaVersion == 1 and
	.command == "build" and
	.status == "fail" and
	.exitCode == 1 and
	.log == "build/evidence/commands/build.log"
' <<<"$result" >/dev/null
grep -Fq 'generated bootstrap source is missing' \
	"$clean_root/build/evidence/commands/build.log"

# A check must never remove an output that a later step needs.
removed="$(LC_ALL=C comm -23 <(printf '%s\n' "$outputs_before") <(build_outputs))"
if [[ -n "$removed" ]]; then
	printf 'command surface check removed build outputs from the checkout:\n%s\n' "$removed" >&2
	exit 1
fi

printf 'BeadsHX command surface: PASS\n'
