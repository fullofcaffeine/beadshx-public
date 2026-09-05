#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-tool-lock.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

printf '%s\n' '#!/usr/bin/env bash' 'printf "v0.0.0\\n"' >"$fixture_root/node"
chmod +x "$fixture_root/node"

if PATH="$fixture_root:$PATH" \
    "$repository_root/scripts/beadshx/verify-toolchains.sh" \
    >"$fixture_root/stdout" 2>"$fixture_root/stderr"; then
    printf 'toolchain verifier accepted an unapproved Node version\n' >&2
    exit 1
fi

if ! grep -Fq 'Node mismatch: expected 24.18.1, got 0.0.0' \
    "$fixture_root/stderr"; then
    printf 'toolchain verifier did not report the expected Node mismatch\n' >&2
    sed -n '1,20p' "$fixture_root/stderr" >&2
    exit 1
fi

if "$repository_root/scripts/beadshx/verify-toolchains.sh" --profile=unknown \
    >"$fixture_root/stdout" 2>"$fixture_root/stderr"; then
    printf 'toolchain verifier accepted an unknown profile\n' >&2
    exit 1
fi

printf 'toolchain lock rejection: PASS\n'
