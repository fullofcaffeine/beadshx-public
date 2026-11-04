#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
actual="${ImageVersion:-missing}"

# Hosted image rollouts overlap. Admit only enumerated, independently reviewed
# immutable manifests; native tool versions remain checked by both callers.
if ! jq -e --arg actual "$actual" '
    .schemaVersion == 2 and
    (.linuxCi.images as $images |
        ($images | type == "array" and length > 0) and
        all($images[];
            (.version | test("^[0-9]{8}\\.[0-9]+\\.[0-9]+$")) and
            (.manifest | test("^https://github.com/actions/runner-images/blob/[0-9a-f]{40}/images/ubuntu/Ubuntu2404-Readme\\.md$")) and
            (.reviewedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))) and
        ([$images[].version] | length == (unique | length)) and
        any($images[]; .version == $actual))
' "$locks" >/dev/null; then
    printf 'runner-image is not admitted with reviewed immutable provenance: %s\n' "$actual" >&2
    exit 1
fi
printf 'runner-image: %s\n' "$actual"
