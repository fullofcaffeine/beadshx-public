#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scanner="$repository_root/.toolchains/bin/gitleaks"
report="${1:-$repository_root/build/evidence/gitleaks.json}"
scan_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-secret-scan.XXXXXX")"
trap 'find "$scan_root" -mindepth 1 -delete; rmdir "$scan_root"' EXIT
tree_report="$scan_root/tree.json"
history_report="$scan_root/history.json"

case "$report" in
    /*) ;;
    *) report="$repository_root/$report" ;;
esac

if ! "$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null 2>&1; then
    "$repository_root/scripts/beadshx/install-gitleaks.sh"
fi
"$repository_root/scripts/beadshx/verify-gitleaks.sh" >/dev/null

python3 "$repository_root/scripts/beadshx/materialize_scan_tree.py" \
    --repository "$repository_root" --tree HEAD --destination "$scan_root"

python3 "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$scan_root"

mkdir -p "$(dirname "$report")"
tree_status=0
(
    cd "$scan_root"
    "$scanner" dir . --redact --no-banner --report-format json \
        --ignore-gitleaks-allow \
        --config "$scan_root/scripts/beadshx/gitleaks.toml" \
        --gitleaks-ignore-path "$scan_root/.gitleaksignore" \
        --report-path "$tree_report"
) || tree_status=$?

baseline="$(jq -er '.compatibilityTarget.commit' \
    "$repository_root/engdocs/beadshx/program/source-locks.json")"
if ! git -C "$repository_root" merge-base --is-ancestor "$baseline" HEAD; then
    printf 'secret scan baseline is not an ancestor of HEAD: %s\n' "$baseline" >&2
    exit 1
fi
history_commits="$(git -C "$repository_root" rev-list --count "$baseline..HEAD")"

history_status=0
# Gitleaks discovers ignore files in its Git target even with an explicit path.
# Require committed policy bytes before treating a local history scan as proof.
if ! git -C "$repository_root" diff HEAD --quiet -- .gitleaksignore; then
    printf 'commit the secret ignore policy before scanning history\n' >&2
    exit 1
fi
"$scanner" git "$repository_root" \
    --log-opts="$baseline..HEAD" \
    --redact \
    --no-banner \
    --ignore-gitleaks-allow \
    --config "$scan_root/scripts/beadshx/gitleaks.toml" \
    --gitleaks-ignore-path "$scan_root/.gitleaksignore" \
    --report-format json \
    --report-path "$history_report" || history_status=$?

[[ -f "$tree_report" ]] || printf '[]\n' >"$tree_report"
[[ -f "$history_report" ]] || printf '[]\n' >"$history_report"
jq -s 'add' "$tree_report" "$history_report" >"$report"

if [[ "$tree_status" -ne 0 || "$history_status" -ne 0 ]]; then
    printf 'secret scan: FAIL (tree=%s history=%s)\n' \
        "$tree_status" "$history_status" >&2
    exit 1
fi

printf 'secret scan: PASS (tracked tree and %s BeadsHX commits)\n' \
    "$history_commits"
