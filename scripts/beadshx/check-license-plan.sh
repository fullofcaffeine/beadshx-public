#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
generated_root="${BEADSHX_GENERATED_ROOT:-$repository_root}"

cd "$repository_root"

grep -Fqx 'Copyright (c) 2025 Beads Contributors' LICENSE
grep -Fqx 'Copyright (c) 2026 BeadsHX Contributors' LICENSE
grep -Fq 'dolthub/dolt' THIRD_PARTY_LICENSES

jq -e '
    .project == "Beads" and
    .version == "v1.2.1" and
    .commit == "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"
' upstream/locks/beads-v1.2.1.json >/dev/null

jq -e '
    .project == "haxe.go" and
    .liveStartingCommit == "990d78bcf7a8641ef589cd230b7d69d59beadb84" and
    .requiredCommit == "c1e3333d2ce358b451e69b2b1530030bc4083dd5" and
    .requiredHaxe == "4.3.7"
' upstream/locks/haxe-go.json >/dev/null

if [[ ! -d "$generated_root/LICENSES" ]]; then
    printf 'generated license directory is missing: %s\n' "$generated_root/LICENSES" >&2
    exit 1
fi

(
    cd "$generated_root"
    printf '%s  %s\n' \
        '6889cefcfdc5bf1b6fb9fc4807b0ae080db219ca3c82208c9455c1cf7e81ef94' \
        'LICENSES/HAXE-GO-GENERATED-MIT.txt' \
        '61c9e5c8ca48e1f6e27f66cc6fb2eb11865a08672e1c793a13cfdaa89ad1bb74' \
        'LICENSES/HAXE-STDLIB-MIT.txt' |
        shasum -a 256 -c
)

if find "$generated_root/LICENSES" -type f -name 'LICENSE*' \
    ! -path "$generated_root/LICENSES/HAXE-GO-GENERATED-MIT.txt" \
    ! -path "$generated_root/LICENSES/HAXE-STDLIB-MIT.txt" |
    grep -q .; then
    printf 'generated output contains an unapproved license file\n' >&2
    exit 1
fi

printf 'license plan: PASS\n'
