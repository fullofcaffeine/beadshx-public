#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

mode="${1:-check}"
plan="compatibility/schema-migrations/plan.json"
target_commit="$(jq -er '.compatibilityTarget.commit' "$plan")"

if [[ "$mode" != "check" && "$mode" != "pairs" ]]; then
    printf 'usage: %s {check|pairs}\n' "$0" >&2
    exit 2
fi

jq -e '
    .schemaVersion == 1 and
    .compatibilityTarget.version == "v1.2.1" and
    .status == "planned" and
    (.derivationRule | test("frozen up migration")) and
    ([.lanes[].id] | sort) == ["ignored", "main"] and
    ([.lanes[].latestVersion] | add) == 89 and
    ([.lanes[].upFileCount] | add) == 89 and
    ([.applicationNodes[].id] | length) ==
        ([.applicationNodes[].id] | unique | length) and
    ((.productionOrder - [.applicationNodes[].id]) == []) and
    ([.repairBindings[].beforeVersion] | sort) == [40, 41, 47, 53, 58] and
    ([.schemaObservers[]] | length) == 8 and
    .determinism.convergenceFloorMainVersion == 43 and
    (([.determinism.replicatedStoredValueRisk[],
       .determinism.queryTimeOnly[],
       .determinism.cloneLocalOnly[]] | length) ==
     .determinism.allowlistedFileCount) and
    ([.testPairFamilies[].id] | sort) == [
        "adjacent-ignored", "adjacent-main", "binary-schema-guard",
        "fresh-to-latest", "historical-release-to-latest",
        "legacy-sqlite-to-current-dolt", "mixed-cursor-and-remote",
        "repair-state-to-latest"
    ] and
    ((.explicitTestCases | keys) - [.testPairFamilies[].id]) == [] and
    ((.testPairFamilyOutcomes | keys) == (.explicitTestCases | keys)) and
    (((.testPairOutcomeOverrides | keys) -
      [.explicitTestCases[][]]) == []) and
    ([.reversibilityPolicy.irreversible[].node,
      .reversibilityPolicy.conditional[].node] | length) ==
        ([.reversibilityPolicy.irreversible[].node,
          .reversibilityPolicy.conditional[].node] | unique | length) and
    all(.gaps[]; .status == "pending")
' "$plan" >/dev/null

git cat-file -e "$target_commit^{commit}"

while IFS= read -r source_path; do
    git cat-file -e "$target_commit:$source_path"
done < <(jq -r '[.authorities[], .applicationNodes[].source] | unique[]' "$plan")

node_ids_file="$(mktemp "${TMPDIR:-/tmp}/beadshx-schema-nodes.XXXXXX")"
pairs_file="$(mktemp "${TMPDIR:-/tmp}/beadshx-schema-pairs.XXXXXX")"
trap 'rm -f -- "$node_ids_file" "$pairs_file"' EXIT

while IFS=$'\x1f' read -r lane directory latest up_count down_count; do
    paths=()
    while IFS= read -r path; do
        paths+=("$path")
    done < <(
        git ls-tree -r --name-only "$target_commit" "$directory" |
            if [[ "$lane" == "main" ]]; then
                awk -v root="$directory/" '
                    index($0, root) == 1 && index(substr($0, length(root) + 1), "/") == 0
                '
            else
                awk -v root="$directory/" 'index($0, root) == 1'
            fi |
            grep -E '/[0-9]{4}_[^/]+\.up\.sql$' |
            sort
    )

    if [[ "${#paths[@]}" -ne "$up_count" || "$up_count" -ne "$latest" ]]; then
        printf '%s lane has %d up files; expected %s through version %s\n' \
            "$lane" "${#paths[@]}" "$up_count" "$latest" >&2
        exit 1
    fi

    actual_down=0
    missing_versions=()
    version=1
    for path in "${paths[@]}"; do
        basename="${path##*/}"
        file_version="${basename%%_*}"
        expected_version="$(printf '%04d' "$version")"
        if [[ "$file_version" != "$expected_version" ]]; then
            printf '%s lane version gap: got %s; expected %s\n' \
                "$lane" "$file_version" "$expected_version" >&2
            exit 1
        fi

        printf '%s:%s\n' "$lane" "$file_version" >>"$node_ids_file"
        git show "$target_commit:$path" | shasum -a 256 >/dev/null

        down_path="${path%.up.sql}.down.sql"
        if git cat-file -e "$target_commit:$down_path" 2>/dev/null; then
            actual_down=$((actual_down + 1))
        else
            missing_versions+=("$version")
        fi
        version=$((version + 1))
    done

    if [[ "$actual_down" -ne "$down_count" ]]; then
        printf '%s lane has %d down files; expected %s\n' \
            "$lane" "$actual_down" "$down_count" >&2
        exit 1
    fi
    planned_missing="$(jq -c --arg lane "$lane" '.lanes[] | select(.id == $lane) | .missingDownVersions' "$plan")"
    actual_missing="$(printf '%s\n' "${missing_versions[@]}" | jq -Rsc 'split("\n") | map(select(length > 0) | tonumber)')"
    if [[ "$actual_missing" != "$planned_missing" ]]; then
        printf '%s lane missing-down set drifted\n' "$lane" >&2
        exit 1
    fi
done < <(jq -r '.lanes[] | [.id, .directory, .latestVersion, .upFileCount, .downFileCount] | join("\u001f")' "$plan")

sort -u -o "$node_ids_file" "$node_ids_file"
while IFS= read -r classified_node; do
    if ! grep -Fqx "$classified_node" "$node_ids_file"; then
        printf 'reversibility record names no migration node: %s\n' "$classified_node" >&2
        exit 1
    fi
done < <(jq -r '[.reversibilityPolicy.irreversible[].node, .reversibilityPolicy.conditional[].node] | unique[]' "$plan")

while IFS= read -r deterministic_node; do
    if ! grep -Fqx "$deterministic_node" "$node_ids_file"; then
        printf 'determinism record names no migration node: %s\n' "$deterministic_node" >&2
        exit 1
    fi
done < <(jq -r '[.determinism.replicatedStoredValueRisk[], .determinism.queryTimeOnly[], .determinism.cloneLocalOnly[]] | unique[]' "$plan")

repair_source="$(jq -r '.authorities.repairs' "$plan")"
while IFS=$'\x1f' read -r before_version function_name; do
    if ! git grep -q -E "func ${function_name}\\(" "$target_commit" -- internal/storage/schema; then
        printf 'repair binding function is absent: %s\n' "$function_name" >&2
        exit 1
    fi
    if ! git show "$target_commit:$repair_source" |
        grep -F -- "{\"schema_migrations\", $before_version}: $function_name" >/dev/null; then
        printf 'repair binding is absent for main version %s: %s\n' \
            "$before_version" "$function_name" >&2
        exit 1
    fi
done < <(jq -r '.repairBindings[] | [.beforeVersion, .function] | join("\u001f")' "$plan")
git cat-file -e "$target_commit:$repair_source"

allowlist_path="$(jq -r '.authorities.nondeterminismAllowlist' "$plan")"
allowlist_count="$(git show "$target_commit:$allowlist_path" | awk 'NF > 0 && $1 !~ /^#/ {count++} END {print count + 0}')"
if [[ "$allowlist_count" -ne "$(jq -r '.determinism.allowlistedFileCount' "$plan")" ]]; then
    printf 'migration nondeterminism allowlist count drifted: %s\n' "$allowlist_count" >&2
    exit 1
fi
allowlisted_nodes="$(
    git show "$target_commit:$allowlist_path" |
        awk 'NF > 0 && $1 !~ /^#/ {
            path = $1
            lane = "main"
            if (path ~ /^ignored\//) {
                lane = "ignored"
                sub(/^ignored\//, "", path)
            }
            print lane ":" substr(path, 1, 4)
        }' |
        sort -u
)"
planned_determinism_nodes="$(jq -r '[.determinism.replicatedStoredValueRisk[], .determinism.queryTimeOnly[], .determinism.cloneLocalOnly[]] | unique[]' "$plan" | sort -u)"
if [[ "$allowlisted_nodes" != "$planned_determinism_nodes" ]]; then
    printf 'migration nondeterminism classifications drifted\n' >&2
    exit 1
fi

historical_workflow="$(jq -r '.authorities.historicalWorkflow' "$plan")"
while IFS= read -r version_name; do
    if ! git show "$target_commit:$historical_workflow" |
        grep -F -- "version: $version_name" >/dev/null; then
        printf 'historical migration fixture is absent: %s\n' "$version_name" >&2
        exit 1
    fi
done < <(jq -r '.explicitTestCases["historical-release-to-latest"][]' "$plan")

emit_pair() {
    local pair_id="$1"
    local family="$2"
    local from_state="$3"
    local to_state="$4"
    local construction="$5"
    local observer="$6"
    jq -cn \
        --arg id "$pair_id" \
        --arg family "$family" \
        --arg from "$from_state" \
        --arg to "$to_state" \
        --arg construction "$construction" \
        --arg observer "$observer" \
        '{id:$id, family:$family, from:$from, to:$to,
          construction:$construction, observer:$observer}' >>"$pairs_file"
}

while IFS=$'\x1f' read -r lane latest family; do
    version=1
    while [[ "$version" -le "$latest" ]]; do
        previous=$((version - 1))
        emit_pair \
            "${family}-$(printf '%04d' "$previous")-$(printf '%04d' "$version")" \
            "$family" "$lane:$previous" "$lane:$version" \
            "$(jq -r --arg family "$family" '.testPairFamilies[] | select(.id == $family) | .construction' "$plan")" \
            "$(jq -r --arg family "$family" '.testPairFamilies[] | select(.id == $family) | .observer' "$plan")"
        version=$((version + 1))
    done
done < <(jq -r '.lanes[] | [.id, .latestVersion, ("adjacent-" + .id)] | join("\u001f")' "$plan")

while IFS=$'\x1f' read -r family case_id; do
    construction="$(jq -r --arg family "$family" '.testPairFamilies[] | select(.id == $family) | .construction' "$plan")"
    observer="$(jq -r --arg family "$family" '.testPairFamilies[] | select(.id == $family) | .observer' "$plan")"
    outcome="$(jq -r --arg family "$family" --arg caseId "$case_id" \
        '.testPairOutcomeOverrides[$caseId] // .testPairFamilyOutcomes[$family]' "$plan")"
    emit_pair "$family-$case_id" "$family" "$case_id" "$outcome" "$construction" "$observer"
done < <(jq -r '.explicitTestCases | to_entries[] | .key as $family | .value[] | [$family, .] | join("\u001f")' "$plan")

pair_count="$(wc -l <"$pairs_file" | tr -d ' ')"
if [[ "$pair_count" -ne 128 ]]; then
    printf 'generated %s migration test pairs; expected 128\n' "$pair_count" >&2
    exit 1
fi
jq -se '
    length == 128 and
    ([.[].id] | length) == ([.[].id] | unique | length) and
    all(.[];
        (.id | length) > 0 and
        (.family | length) > 0 and
        (.from | length) > 0 and
        (.to | length) > 0 and
        (.construction | length) > 0 and
        (.observer | length) > 0)
' "$pairs_file" >/dev/null

if [[ "$mode" == "pairs" ]]; then
    jq -s --arg target "$target_commit" \
        '{schemaVersion:1, compatibilityTargetCommit:$target, pairs:.}' \
        "$pairs_file"
else
    printf 'schema migration graph: PASS (89 numbered nodes; 24 application nodes; 128 generated test pairs; 7 irreversible transitions; 3 explicit gaps)\n'
fi
