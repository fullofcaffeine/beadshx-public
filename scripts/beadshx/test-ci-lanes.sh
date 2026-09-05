#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
workflow="$repository_root/.github/workflows/beadshx-bootstrap.yml"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"

for job in bootstrap upstream-oracle parity-smoke proxied-readonly license output-contracts performance-baseline secret-scan evidence-gate; do
    if ! grep -Eq "^  ${job}:$" "$workflow"; then
        printf 'bootstrap workflow is missing job: %s\n' "$job" >&2
        exit 1
    fi
done

grep -Fq 'needs: [bootstrap, upstream-oracle]' "$workflow"
grep -Fq 'needs: [bootstrap, upstream-oracle, parity-smoke, proxied-readonly, license, output-contracts, performance-baseline, secret-scan]' "$workflow"
if grep -Eq '^\s+paths(-ignore)?:' "$workflow"; then
    printf 'base CI workflow must not skip repository paths\n' >&2
    exit 1
fi

while IFS=$'\t' read -r action commit; do
    repository="${action%@*}"
    if ! grep -Fq "uses: $repository@$commit" "$workflow"; then
        printf 'workflow is missing pinned action: %s@%s\n' "$repository" "$commit" >&2
        exit 1
    fi
done < <(jq -r '.githubActions | to_entries[] | [.key, .value] | @tsv' "$locks")

if grep -E '^\s*- uses: [^ ]+@(v[0-9]+|main|master)$' "$workflow"; then
    printf 'bootstrap workflow contains an action without a commit pin\n' >&2
    exit 1
fi

upload_count="$(grep -c 'actions/upload-artifact@' "$workflow")"
retention_count="$(grep -c 'retention-days: 7' "$workflow")"
always_upload_count="$(grep -B1 'uses: actions/upload-artifact@' "$workflow" | \
    grep -c 'if: always()')"
if [[ "$upload_count" -ne 9 || "$retention_count" -ne 9 || \
    "$always_upload_count" -ne 9 ]]; then
    printf 'expected 9 always-retained uploads; got uploads=%s always=%s retention=%s\n' \
        "$upload_count" "$always_upload_count" "$retention_count" >&2
    exit 1
fi

for parity_result in \
    'parity identity smoke: PASS' \
	'no-workspace differential: PASS (42 command forms)' \
    'store-failure differentials: PASS (7 cases)' \
	'real-database differentials: PASS (%s cases; ping timings normalized)' \
	'watch differentials: PASS (%s cases; poll change, refresh error, and signal lifecycle)' \
    'JSON terminal notice differential: PASS'; do
    grep -Fq "$parity_result" \
        "$repository_root/scripts/beadshx/test-parity-smoke.sh"
done
for lane in bootstrap upstream-oracle parity-smoke proxied-readonly license output-contracts performance-baseline secret-scan evidence-gate; do
    grep -Fq "scripts/beadshx/ci-hosted.sh $lane" "$workflow"
done
sed -n '/^  secret-scan:/,/^  evidence-gate:/p' "$workflow" |
    grep -Fq 'fetch-depth: 0'
sed -n '/^  output-contracts:/,/^  secret-scan:/p' "$workflow" |
    grep -Fq 'fetch-depth: 0'

grep -Fq 'shell: bash --noprofile --norc -euo pipefail {0}' "$workflow"
if grep -Fq '| tee' "$workflow"; then
    printf 'hosted workflow must not hide lane failures behind tee\n' >&2
    exit 1
fi
if [[ "$(grep -c 'persist-credentials: false' "$workflow")" -ne 9 ]]; then
    printf 'every checkout must disable persisted credentials\n' >&2
    exit 1
fi
grep -Fq 'verify-runner.sh" --profile=linux-ci' \
    "$repository_root/scripts/beadshx/ci-hosted.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-ci-lanes.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT
fixture="$test_root/hosted-failure"
mkdir -p "$fixture/scripts/beadshx" "$fixture/build/evidence"
git -C "$fixture" init --quiet
git -C "$fixture" config user.email ci@example.invalid
git -C "$fixture" config user.name 'CI lane test'
cp "$repository_root/scripts/beadshx/ci-hosted.sh" \
    "$fixture/scripts/beadshx/ci-hosted.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
    >"$fixture/scripts/beadshx/verify-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "controlled lane failure\\n"' 'exit 37' \
    >"$fixture/scripts/beadshx/ci-lane.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "{}\\n" >"$2"' \
    >"$fixture/scripts/beadshx/report-locks.sh"
chmod +x "$fixture/scripts/beadshx/"*.sh
printf 'fixture\n' >"$fixture/README.md"
git -C "$fixture" add -- .
git -C "$fixture" commit --quiet -m fixture

hosted_status=0
"$fixture/scripts/beadshx/ci-hosted.sh" secret-scan >/dev/null 2>&1 || \
    hosted_status=$?
if [[ "$hosted_status" -ne 37 ]]; then
    printf 'hosted wrapper lost lane exit 37: got %s\n' "$hosted_status" >&2
    exit 1
fi
jq -e '.schemaVersion == 1 and .status == "failure" and .laneExitCode == 37' \
    "$fixture/build/evidence/secrets/result.json" >/dev/null
grep -Fq 'controlled lane failure' "$fixture/build/evidence/secrets/lane.log"
test -f "$fixture/build/evidence/secrets/locks.json"

printf 'base CI lane policy: PASS\n'
