#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
profile="${1:-}"

if [[ "$profile" != "--profile=linux-ci" ]]; then
    printf 'usage: %s --profile=linux-ci\n' "$0" >&2
    exit 2
fi

expect_exact() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf '%s mismatch: expected %s, got %s\n' \
            "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

locked() {
    jq -er "$1" "$locks"
}

expect_exact kernel Linux "$(uname -s)"
expect_exact runner "$(locked '.linuxCi.imageOS')" "${ImageOS:-missing}"
expect_exact runner-image "$(locked '.linuxCi.imageVersion')" "${ImageVersion:-missing}"
expect_exact Bash "$(locked '.linuxCi.bash')" "$BASH_VERSION"
expect_exact Git "$(locked '.linuxCi.git')" \
    "$(git --version | sed 's/^git version //')"
expect_exact jq "$(locked '.linuxCi.jq')" "$(jq --version)"

printf 'runner profile linux-ci: PASS\n'
