#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scanner="$repository_root/.toolchains/bin/gitleaks"

# Freeze the index so the exception check and scanner inspect the same bytes.
snapshot="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-staged-secrets.XXXXXX")"
trap 'rm -rf "$snapshot"' EXIT
index_path="$(git -C "$repository_root" rev-parse --path-format=absolute --git-path index)"
if [[ ! -f "$index_path" ]]; then
    exit 0
fi
cp -f "$index_path" "$snapshot/index"
cp -f "$index_path" "$snapshot/original-index"
export GIT_INDEX_FILE="$snapshot/index"

if git -C "$repository_root" diff --cached --quiet -- .; then
    exit 0
fi

if ! "$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null 2>&1; then
    "$repository_root/scripts/beadshx/install-gitleaks.sh"
fi
"$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null
python3 "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$repository_root" --staged

# Gitleaks also discovers ignore files in the scan root. Materialize only the
# frozen staged tree so unstaged ignore files cannot suppress a finding.
mkdir "$snapshot/tree"
tree="$(git -C "$repository_root" write-tree)"
python3 "$repository_root/scripts/beadshx/materialize_scan_tree.py" \
    --repository "$repository_root" --tree "$tree" --destination "$snapshot/tree"
(
    cd "$snapshot/tree"
    "$scanner" dir . \
        --redact \
        --no-banner \
        --ignore-gitleaks-allow \
        --config "$snapshot/tree/scripts/beadshx/gitleaks.toml" \
        --gitleaks-ignore-path "$snapshot/tree/.gitleaksignore"
)

if ! cmp -s "$index_path" "$snapshot/original-index"; then
    printf 'index changed during secret scan; stage and retry\n' >&2
    exit 1
fi

printf 'staged secret scan: PASS\n'
