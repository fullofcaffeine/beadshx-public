#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

if [[ ! -d node_modules || ! -d haxe_libraries ]]; then
	./scripts/beadshx/setup-haxe.sh
fi

# haxe.go warns when authored Haxe uses typed go.* APIs outside a @:goNative
# extern module. Treat that warning as an error so native use stays behind the
# extern boundary.
output="$(mktemp)"
trap 'rm -f "$output"' EXIT
if ! npx haxe compile.bootstrap.hxml -D go_no_build 2>&1 | tee "$output"; then
	exit 1
fi
if grep -q 'NativeAuthorityGate' "$output"; then
	printf 'generate-source: haxe.go reported a native authority warning; move typed go.* use into a @:goNative extern module\n' >&2
	exit 1
fi
