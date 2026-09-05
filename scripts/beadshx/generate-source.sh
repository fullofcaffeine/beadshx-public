#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

if [[ ! -d node_modules || ! -d haxe_libraries ]]; then
	./scripts/beadshx/setup-haxe.sh
fi

npx haxe compile.bootstrap.hxml -D go_no_build
