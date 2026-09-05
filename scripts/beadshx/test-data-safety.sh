#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
guard="$repository_root/scripts/beadshx/assert-disposable-workspace.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-safety.XXXXXX")"
outside_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-outside.XXXXXX")"
trap 'rm -rf -- "$fixture_root" "$outside_root"' EXIT

if "$guard" "$repository_root" >/dev/null 2>&1; then
	echo "guard accepted the source repository" >&2
	exit 1
fi

if "$guard" "$fixture_root" >/dev/null 2>&1; then
	echo "guard accepted an unmarked temporary directory" >&2
	exit 1
fi

touch "$fixture_root/.beadshx-disposable-fixture"
resolved="$($guard "$fixture_root")"
if [[ "$resolved" != "$(cd "$fixture_root" && pwd -P)" ]]; then
	echo "guard returned an unexpected workspace" >&2
	exit 1
fi

source_fixture="$fixture_root/source-checkout"
mkdir -p "$source_fixture/.git"
touch "$source_fixture/.beadshx-disposable-fixture"
if "$guard" "$source_fixture" >/dev/null 2>&1; then
	echo "guard accepted a marked source checkout" >&2
	exit 1
fi

outside_database="$outside_root/database"
mkdir -p "$(dirname "$outside_database")"
if BEADS_DB="$outside_database" "$guard" "$fixture_root" >/dev/null 2>&1; then
	echo "guard accepted an ambient database outside the fixture" >&2
	exit 1
fi

inside_database="$fixture_root/.beads/database"
mkdir -p "$(dirname "$inside_database")"
BEADS_DB="$inside_database" "$guard" "$fixture_root" >/dev/null

echo "data-safety guard: PASS"
