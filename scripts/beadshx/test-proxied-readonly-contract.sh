#!/usr/bin/env bash
set -euo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-proxied-contract.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/docker"
printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/binary"
cat >"$fixture/bin/go" <<'STUB'
#!/bin/sh
printf '{"Action":"%s","Test":"TestBeadsHXProxiedReadonly"}\n' "$QUALIFICATION_ACTION"
STUB
chmod +x "$fixture/bin/"*
for action in pass skip fail; do
    result=0
    PATH="$fixture/bin:$PATH" QUALIFICATION_ACTION="$action" \
        BEADSHX_CANDIDATE_BIN="$fixture/bin/binary" \
        BEADSHX_ORACLE_BIN="$fixture/bin/binary" \
        "$repository_root/scripts/beadshx/test-proxied-readonly.sh" >"$fixture/$action.log" 2>&1 || result=$?
    if [[ "$action" == pass && "$result" != 0 ]] || [[ "$action" != pass && "$result" == 0 ]]; then
        printf 'qualification wrapper accepted the wrong outcome: %s (exit %s)\n' "$action" "$result" >&2
        exit 1
    fi
done
printf 'proxied qualification requires an executed passing test: PASS\n'
