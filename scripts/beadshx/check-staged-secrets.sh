#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scanner="$repository_root/.toolchains/bin/gitleaks"

if git -C "$repository_root" diff --cached --quiet -- .; then
    exit 0
fi

if ! "$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null 2>&1; then
    "$repository_root/scripts/beadshx/install-gitleaks.sh"
fi
"$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null
python3 "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$repository_root"

"$scanner" git "$repository_root" \
    --staged \
    --redact \
    --no-banner \
    --gitleaks-ignore-path "$repository_root/.gitleaksignore"

printf 'staged secret scan: PASS\n'
