#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
package="$repository_root/build/packages/beadshx-development-bootstrap.zip"

"$repository_root/scripts/beadshx/generate-bootstrap.sh"
"$repository_root/scripts/beadshx/check-release-identity.sh"
mkdir -p "$(dirname "$package")"
go test "$repository_root/scripts/beadshx/package-bootstrap"
go run "$repository_root/scripts/beadshx/package-bootstrap" \
		--repository "$repository_root" \
		--output "$package"
printf '%s\n' "$package"
