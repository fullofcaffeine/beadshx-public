#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
source_locks="$repository_root/engdocs/beadshx/program/source-locks.json"

required_scripts=(
    check-haxe-format.sh
    check_gitleaks_ignore_contract.py
    check-local-paths-staged.sh
    check_local_paths_staged.py
    check-staged-go.sh
    check-staged-secrets.sh
    ci-hosted.sh
    ci-lane.sh
    ci-local.sh
    install-hooks.sh
    install-pre-commit.sh
    run-golangci.sh
    run-pre-commit.sh
    verify-gitleaks.sh
    verify-runner.sh
)

for script in "${required_scripts[@]}"; do
    if [[ ! -x "$repository_root/scripts/beadshx/$script" ]]; then
        printf 'repository safety script is missing or not executable: %s\n' "$script" >&2
        exit 1
    fi
done

jq -e '
    .common.haxeFormatter == "1.18.0" and
    .common.golangciLint == "v2.10.1" and
    .common.preCommit == "4.3.0" and
    .secretScanner.name == "gitleaks" and
    .secretScanner.version == "8.30.1" and
    (.secretScanner.binarySha256 | length) == 4 and
    .golangciLintModule.version == .common.golangciLint
' "$locks" >/dev/null

jq -e --slurpfile tools "$locks" '
    .toolchains.haxeFormatter == $tools[0].common.haxeFormatter and
    .toolchains.preCommit == $tools[0].common.preCommit
' "$source_locks" >/dev/null

grep -Fq 'formatter=1.18.0' "$repository_root/haxe_libraries/formatter.hxml"
grep -Fq 'run-pre-commit.sh" run' "$repository_root/.githooks/pre-commit"
grep -Fq -- '--hook-stage pre-commit' "$repository_root/.githooks/pre-commit"

for hook in \
    trailing-whitespace \
    end-of-file-fixer \
    check-yaml \
    check-added-large-files \
    check-merge-conflict \
    detect-private-key \
    beadshx-local-paths \
    beadshx-staged-secrets \
    beadshx-haxe-format \
    beadshx-go-lint; do
    if ! grep -Fq -- "- id: $hook" "$repository_root/.pre-commit-config.yaml"; then
        printf 'pre-commit configuration is missing hook: %s\n' "$hook" >&2
        exit 1
    fi
done

expected_hooks=(
    beadshx-go-lint
    beadshx-haxe-format
    beadshx-local-paths
    beadshx-staged-secrets
    check-added-large-files
    check-case-conflict
    check-json
    check-merge-conflict
    check-symlinks
    check-toml
    check-yaml
    detect-private-key
    end-of-file-fixer
    forbid-submodules
    mixed-line-ending
    trailing-whitespace
)
actual_hooks=()
while IFS= read -r hook; do
    actual_hooks+=("$hook")
done < <(sed -n -E 's/^[[:space:]]+- id: ([^[:space:]]+)$/\1/p' \
    "$repository_root/.pre-commit-config.yaml" | LC_ALL=C sort)
if [[ "${actual_hooks[*]}" != "${expected_hooks[*]}" ]]; then
    printf 'pre-commit hook set differs from the reviewed policy\n' >&2
    exit 1
fi

grep -Fq '3e8a8703264a2f4a69428a0aa4dcb512790b2c8c' \
    "$repository_root/.pre-commit-config.yaml"
grep -A1 -F -- '- id: check-added-large-files' \
    "$repository_root/.pre-commit-config.yaml" | grep -Fq -- 'args: [--maxkb=1024]'

for command_name in ci:local hooks:install test:repository-safety test:upstream-performance; do
    jq -e --arg command "$command_name" '.scripts[$command] != null' \
        "$repository_root/package.json" >/dev/null
done

for lane in bootstrap upstream-oracle parity-smoke proxied-readonly license output-contracts performance-baseline secret-scan evidence-gate; do
    if ! grep -Fq -- "$lane" "$repository_root/scripts/beadshx/ci-local.sh"; then
        printf 'local CI is missing lane: %s\n' "$lane" >&2
        exit 1
    fi
done
grep -Fq 'BEADSHX_TOOLCHAIN_PROFILE: linux-ci' \
    "$repository_root/.github/workflows/beadshx-bootstrap.yml"

if grep -En '(^|[^[:alnum:]_])gh([[:space:]]|$)' \
    "$repository_root/scripts/beadshx/ci-local.sh" >/dev/null; then
    printf 'local CI must not call the GitHub CLI\n' >&2
    exit 1
fi

while IFS= read -r use_line; do
    action="$(printf '%s\n' "$use_line" | sed -E \
        's#^.*uses:[[:space:]]*([^[:space:]#]+).*$#\1#')"
    case "$action" in
        ./*) continue ;;
    esac
    if [[ ! "$action" =~ @[0-9a-f]{40}$ ]]; then
        printf 'GitHub action does not use a full commit pin: %s\n' "$use_line" >&2
        exit 1
    fi
done < <(grep -REn --include='*.yml' --include='*.yaml' \
	'^[[:space:]]*(- )?uses:' "$repository_root/.github/workflows")

expected_actions="$(jq -r '.githubActions | to_entries[] |
    "\(.key | sub("@v[0-9]+$"; ""))@\(.value)"' "$locks" | LC_ALL=C sort)"
actual_actions="$(sed -n -E 's/^[[:space:]]*(- )?uses: ([^[:space:]#]+).*$/\2/p' \
    "$repository_root/.github/workflows/beadshx-bootstrap.yml" | \
    grep -v '^\./' | LC_ALL=C sort -u)"
if [[ "$actual_actions" != "$expected_actions" ]]; then
    printf 'GitHub action set differs from the reviewed toolchain lock\n' >&2
    exit 1
fi

grep -Fq '@fullofcaffeine' "$repository_root/.github/CODEOWNERS"
grep -Fq 'fullofcaffeine/beadshx/security/advisories/new' "$repository_root/SECURITY.md"
grep -Fq 'generate-bootstrap.sh' "$repository_root/scripts/beadshx/package-bootstrap.sh"
if grep -Fq '[[ -x "$repository_root/build/bin/bdhx" ]]' \
    "$repository_root/scripts/beadshx/package-bootstrap.sh"; then
    printf 'package command must not reuse a merely present bootstrap binary\n' >&2
    exit 1
fi

if grep -Eq '(^|[[:space:]])git add([[:space:]]|$)' \
    "$repository_root/scripts/beadshx/check-staged-go.sh"; then
    printf 'staged Go check must never update the index\n' >&2
    exit 1
fi

test_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-repository-safety.XXXXXX")"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT

init_fixture() {
    local fixture="$1"
    git -C "$fixture" init --quiet
    git -C "$fixture" config user.email safety@example.invalid
    git -C "$fixture" config user.name 'Repository safety test'
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        printf 'expected command to fail:' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
        exit 1
    fi
}

path_fixture="$test_root/paths"
mkdir -p "$path_fixture/docs"
init_fixture "$path_fixture"
printf 'safe\n' >"$path_fixture/README.md"
printf 'safe\n' >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- README.md docs/note.md
git -C "$path_fixture" commit --quiet -m baseline

printf '/%s/%s/private/build\n' Users alice >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture"
git -C "$path_fixture" reset --hard --quiet HEAD

printf '++ /%s/%s/private/build\n' Users alice >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture"
git -C "$path_fixture" reset --hard --quiet HEAD

printf '"cache": "C:%sUsers%salice%sprivate"\n' '\\' '\\' '\\' \
    >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture"
git -C "$path_fixture" reset --hard --quiet HEAD

newline_path=$'docs/note\nname.md'
printf '/%s/%s/private/build\n' home alice >"$path_fixture/$newline_path"
git -C "$path_fixture" add -- ":(literal)$newline_path"
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture"
git -C "$path_fixture" reset --hard --quiet HEAD

printf '%s\n' '../../outside-repository' >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture"
git -C "$path_fixture" reset --hard --quiet HEAD

printf '%s\n' '../README.md' >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture" >/dev/null
git -C "$path_fixture" commit --quiet -m safe-relative-path
safe_revision="$(git -C "$path_fixture" rev-parse HEAD)"
printf '/%s/%s/%s/%s/private\n' private var folders alice \
    >"$path_fixture/docs/note.md"
git -C "$path_fixture" add -- docs/note.md
git -C "$path_fixture" commit --quiet -m unsafe-path
expect_failure python3 "$repository_root/scripts/beadshx/check_local_paths_staged.py" \
    --repository "$path_fixture" --range "$safe_revision..HEAD"

go_fixture="$test_root/go-authority"
mkdir -p "$go_fixture/scripts/beadshx" "$go_fixture/engdocs/beadshx/program"
init_fixture "$go_fixture"
cp "$repository_root/scripts/beadshx/check-staged-go.sh" \
    "$go_fixture/scripts/beadshx/check-staged-go.sh"
go_toolchain="$(jq -er '.common.go' "$locks")"
jq -n --arg go "$go_toolchain" '{common:{go:$go}}' \
    >"$go_fixture/engdocs/beadshx/program/toolchain-locks.json"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'if [[ -n "${MUTATE_PATH:-}" ]]; then' \
    '    printf "package main\\n\\nvar concurrent = true\\n" >"$MUTATE_PATH"' \
    'fi' >"$go_fixture/scripts/beadshx/run-golangci.sh"
chmod +x "$go_fixture/scripts/beadshx/check-staged-go.sh" \
    "$go_fixture/scripts/beadshx/run-golangci.sh"
printf 'module example.invalid/safety\n\ngo 1.26\n' >"$go_fixture/go.mod"
printf 'package main\n\nfunc main() {}\n' >"$go_fixture/main.go"
git -C "$go_fixture" add -- .
git -C "$go_fixture" commit --quiet -m baseline

victim="$test_root/victim.go"
printf 'package victim\n\nvar Safe = true\n' >"$victim"
victim_hash="$(shasum -a 256 "$victim" | awk '{print $1}')"
ln -s "$victim" "$go_fixture/linked.go"
git -C "$go_fixture" add -- linked.go
expect_failure "$go_fixture/scripts/beadshx/check-staged-go.sh"
[[ "$(shasum -a 256 "$victim" | awk '{print $1}')" == "$victim_hash" ]]
git -C "$go_fixture" reset --hard --quiet HEAD

printf 'package main\n\nvar Literal = true\n' >"$go_fixture/wild*.go"
printf 'package main\n\nvar Secret = true\n' >"$go_fixture/wild-secret.go"
git -C "$go_fixture" add -- ':(literal)wild*.go'
"$go_fixture/scripts/beadshx/check-staged-go.sh" >/dev/null
if git -C "$go_fixture" ls-files --error-unmatch -- wild-secret.go >/dev/null 2>&1; then
    printf 'staged Go check absorbed a wildcard-matching untracked file\n' >&2
    exit 1
fi
git -C "$go_fixture" reset --hard --quiet HEAD

printf 'package main\n\nvar Staged = true\n' >"$go_fixture/main.go"
git -C "$go_fixture" add -- main.go
index_before="$(git -C "$go_fixture" write-tree)"
expect_failure env MUTATE_PATH="$go_fixture/main.go" \
    "$go_fixture/scripts/beadshx/check-staged-go.sh"
[[ "$(git -C "$go_fixture" write-tree)" == "$index_before" ]]
if git -C "$go_fixture" diff --quiet -- main.go; then
    printf 'concurrent Go edit did not remain unstaged\n' >&2
    exit 1
fi
git -C "$go_fixture" reset --hard --quiet HEAD

git -C "$go_fixture" mv main.go renamed.go
"$go_fixture/scripts/beadshx/check-staged-go.sh" >/dev/null

ignore_fixture="$test_root/gitleaks-ignore"
mkdir -p "$ignore_fixture/engdocs/beadshx/program"
cp "$repository_root/.gitleaksignore" "$ignore_fixture/.gitleaksignore"
cp "$repository_root/engdocs/beadshx/program/gitleaks-ignore-contract.json" \
    "$ignore_fixture/engdocs/beadshx/program/gitleaks-ignore-contract.json"
while IFS= read -r source; do
    mkdir -p "$ignore_fixture/$(dirname "$source")"
    cp "$repository_root/$source" "$ignore_fixture/$source"
done < <(jq -r '.exceptions[].fingerprint | sub(":[^:]+:[^:]+$"; "")' \
    "$repository_root/engdocs/beadshx/program/gitleaks-ignore-contract.json" | sort -u)
python3 "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$ignore_fixture" >/dev/null
first_fingerprint="$(jq -r '.exceptions[0].fingerprint' \
    "$repository_root/engdocs/beadshx/program/gitleaks-ignore-contract.json")"
first_path="${first_fingerprint%:*:*}"
first_line="${first_fingerprint##*:}"
python3 - "$ignore_fixture/$first_path" "$first_line" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
line = int(sys.argv[2]) - 1
lines = path.read_bytes().splitlines(keepends=True)
lines[line] = b"changed fixture bytes\n"
path.write_bytes(b"".join(lines))
PY
expect_failure python3 \
    "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$ignore_fixture"
cp "$repository_root/$first_path" "$ignore_fixture/$first_path"
printf '%s\n' 'new/file.txt:generic-api-key:1' >>"$ignore_fixture/.gitleaksignore"
expect_failure python3 \
    "$repository_root/scripts/beadshx/check_gitleaks_ignore_contract.py" \
    --repository "$ignore_fixture"

GOWORK=off GOTOOLCHAIN="$go_toolchain" go test \
    "$repository_root/scripts/beadshx/package-bootstrap" >/dev/null

printf 'repository safety policy: PASS\n'
