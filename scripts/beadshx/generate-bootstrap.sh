#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

cd "$repository_root"
./scripts/beadshx/setup-haxe.sh
./scripts/beadshx/generate-source.sh
./scripts/beadshx/build-generated.sh
