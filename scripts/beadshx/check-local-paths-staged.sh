#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
exec python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$repository_root" "$@"
