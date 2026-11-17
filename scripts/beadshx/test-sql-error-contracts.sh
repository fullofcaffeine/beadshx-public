#!/usr/bin/env bash
set -euo pipefail

mode=default
if [[ $# -gt 1 || ( $# -eq 1 && -z "$1" ) ]]; then
    printf 'usage: %s [--scalar-labels|--embedded-comments]\n' "$0" >&2
    exit 2
fi
case "${1:-}" in
    "") ;;
    --scalar-labels) mode=scalar_label_details ;;
    --embedded-comments) mode=embedded_comment_details ;;
    *)
        printf 'usage: %s [--scalar-labels|--embedded-comments]\n' "$0" >&2
        exit 2
        ;;
esac

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-sql-errors.XXXXXX")"
guard="$repository_root/scripts/beadshx/assert-disposable-workspace.sh"
# SQL mocks never need ambient workspace/database selection.
unset BEADS_DB BEADS_DIR BD_DB GT_ROOT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GOWORK=off
touch "$fixture_root/.beadshx-disposable-fixture"
"$guard" "$fixture_root" >/dev/null
cleanup() {
    local status=$?
    if [[ "$status" == 0 ]]; then
        "$guard" "$fixture_root" >/dev/null
        rm -rf -- "$fixture_root"
    else
        printf 'SQL contract failure; disposable evidence retained: %s\n' "$fixture_root" >&2
    fi
    exit "$status"
}
trap cleanup EXIT

# Copy current authored inputs, including uncommitted new contracts and embedded
# resources. NUL-delimited Git paths preserve spaces/newlines; ignored private
# data and the primary database never enter the fixture. Generated ownership
# starts fresh, including the module-root compiler license artifacts.
python3 - "$repository_root" "$fixture_root" <<'PY'
from pathlib import Path
import shutil
import subprocess
import sys

source, fixture = map(Path, sys.argv[1:])
excluded = {".git", ".beads", ".playwright-mcp", ".toolchains", "node_modules", "generated", "LICENSES"}
paths = subprocess.check_output([
    "git", "-C", str(source), "ls-files", "--cached", "--others",
    "--exclude-standard", "-z",
]).split(b"\0")
for raw in paths:
    if not raw:
        continue
    relative = Path(raw.decode("utf-8", errors="surrogateescape"))
    if relative.parts[0] in excluded:
        continue
    original = source / relative
    if not original.is_file() and not original.is_symlink():
        continue  # Deleted working-tree files are not build inputs.
    target = fixture / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, target, follow_symlinks=False)
# Setup owns these admitted dependencies. This runner only reads them: no
# package installation or compiler checkout mutation is performed here.
for relative in ("node_modules", ".toolchains/haxe.go"):
    dependency = source / relative
    if not dependency.is_dir():
        raise SystemExit("SQL contracts require repository toolchain setup")
    target = fixture / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.symlink_to(dependency.resolve(), target_is_directory=True)
# This optional local build input is intentionally ignored by Git.
if (source / ".buildflags").is_file():
    shutil.copy2(source / ".buildflags", fixture / ".buildflags")
PY

cd "$fixture_root"
GOTOOLCHAIN="$(jq -er '.common.go' engdocs/beadshx/program/toolchain-locks.json)"
export GOTOOLCHAIN
# Native observers are copied only after their own generation. Each explicit
# mode owns a fresh output tree, so neither observer can leak into another build.
if [[ "$mode" != default ]]; then
    npx --no-install haxe "test/$mode/compile.hxml" -D go_no_build
    if [[ "$mode" == scalar_label_details ]]; then
        cp -f test/scalar_label_details/native_test.go.in generated/go/bdhx/scalar_label_test.go
        # The scalar module includes its embedded connector, so Go requires
        # CGO even though this observer uses only a mock transaction.
        CGO_ENABLED=1 go test -tags=gms_pure_go -run '^TestScalarLabelAssembly$' -count=1 -timeout=300s ./generated/go/bdhx
    else
        cp -f test/embedded_comment_details/native_test.go.in generated/go/bdhx/embedded_comment_test.go
        # Preserve admitted build caches while the real driver and its tests
        # receive an owned home/config directory, never maintainer settings.
        native_mod_cache="$(go env GOMODCACHE)"
        native_build_cache="$(go env GOCACHE)"
        mkdir -p "$fixture_root/home" "$fixture_root/config"
        env HOME="$fixture_root/home" USERPROFILE="$fixture_root/home" \
            XDG_CONFIG_HOME="$fixture_root/config" GIT_CONFIG_NOSYSTEM=1 \
            GIT_CONFIG_GLOBAL="$fixture_root/gitconfig" \
            GOMODCACHE="$native_mod_cache" GOCACHE="$native_build_cache" \
            CGO_ENABLED=1 go test -tags=gms_pure_go -run '^TestEmbeddedCommentDetails$' -count=1 -timeout=300s ./generated/go/bdhx
    fi
    exit 0
fi

# Each comment oracle writes fresh observations through the pinned native owner.
# Compare parsed, ordered objects and the independent case count: exit zero alone
# cannot prove the Haxe reader returned the same comments and errors.
compare_comment_contract() {
    local contract="$1" observation_variable="$2" observer_test="$3" cases="$4"
    local expected="$fixture_root/$contract-native.jsonl" actual="$fixture_root/$contract-haxe.jsonl"
    env "$observation_variable=$expected" go test -tags=gms_pure_go ./test/sql_comment_reader -run "^$observer_test$" -count=1
    go run -tags=gms_pure_go ./generated/go/bdhx > "$actual"
    python3 - "$expected" "$actual" "$cases" <<'PY_COMPARE'
import json
from pathlib import Path
import sys

expected_path, actual_path = map(Path, sys.argv[1:3])
cases = int(sys.argv[3])
expected = [json.loads(line) for line in expected_path.read_text().splitlines()]
actual = [json.loads(line) for line in actual_path.read_text().splitlines()]
# Re-encode after parsing so object key order is irrelevant but JSON types
# remain distinct (Python otherwise considers false equal to integer zero).
expected_value = json.dumps(expected, sort_keys=True, separators=(",", ":"))
actual_value = json.dumps(actual, sort_keys=True, separators=(",", ":"))
if len(expected) != cases or len(actual) != cases or expected_value != actual_value:
    raise SystemExit(f"comment contract mismatch: expected {cases} ordered cases, got native={len(expected)} Haxe={len(actual)}")
PY_COMPARE
}

# Synthetic errors, sqlmock, and JSON rendering never open a real database.
for contract in storage_errors storage_relation_errors storage_summary_errors render_metadata raw_metadata_output nullable_issue_strings native_issue_math sql_comment_reader sql_comment_details complete_issue_row; do
    npx --no-install haxe "test/$contract/compile.hxml" -D go_no_build
    # This authored Go observer checks the generated Haxe boundary directly.
    # Keep this contract last so its test cannot leak into another generation.
    if [[ "$contract" == complete_issue_row ]]; then
        cp -f test/complete_issue_row/native_test.go.in generated/go/bdhx/complete_row_test.go
    fi
    go test -tags=gms_pure_go ./generated/go/bdhx
    case "$contract" in
        sql_comment_reader) compare_comment_contract "$contract" BEADSHX_COMMENT_OBSERVATIONS TestPinnedCommentReadObserver 21 ;;
        sql_comment_details) compare_comment_contract "$contract" BEADSHX_COMMENT_DETAIL_OBSERVATIONS TestPinnedCommentDetailObserver 25 ;;
        *) go run -tags=gms_pure_go ./generated/go/bdhx ;;
    esac
done
