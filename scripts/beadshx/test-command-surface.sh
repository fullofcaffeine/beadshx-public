#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
dispatcher="$repository_root/scripts/beadshx/command.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-command-surface.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

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

result="$($dispatcher clean)"
jq -e '
	.schemaVersion == 1 and
	.command == "clean" and
	.status == "pass" and
	.exitCode == 0 and
	.log == "build/evidence/commands/clean.log"
' <<<"$result" >/dev/null

result="$($dispatcher build || true)"
jq -e '
	.schemaVersion == 1 and
	.command == "build" and
	.status == "fail" and
	.exitCode == 1 and
	.log == "build/evidence/commands/build.log"
' <<<"$result" >/dev/null
grep -Fq 'generated bootstrap source is missing' \
	"$repository_root/build/evidence/commands/build.log"

printf 'BeadsHX command surface: PASS\n'
