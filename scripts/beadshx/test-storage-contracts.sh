#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

plan="compatibility/storage-contracts/plan.json"
target_commit="$(jq -er '.compatibilityTarget.commit' "$plan")"
inventory_path="$(jq -er '.authorities.commandTree' "$plan")"

jq -e '
    .schemaVersion == 1 and
    .compatibilityTarget.project == "Beads" and
    .compatibilityTarget.version == "v1.2.1" and
    .status == "planned" and
    (.ownershipRule | test("smallest semantic application capability")) and
    (.commandResolution | test("first path segment")) and
    (.haxeBoundary | test("Authored Haxe owns typed application capabilities")) and
    ([.commandProfiles[].id] | length) == ([.commandProfiles[].id] | unique | length) and
    ([.commandProfiles[].roots[]] | length) == ([.commandProfiles[].roots[]] | unique | length) and
    all(.commandProfiles[];
        (.roots | length) > 0 and
        (.capabilities | length) > 0 and
        (.transactionRequirements | length) > 0) and
    (([.commandProfiles[].capabilities[]] | unique) -
        (.capabilities | keys)) == [] and
    (([.commandProfiles[].transactionRequirements[]] | unique) -
        (.transactionRequirements | keys)) == [] and
    ([.backendLegs[].id] | sort) == ["dolt", "embeddeddolt", "uow"] and
    all(.backendLegs[];
        (.sourceEvidence | length) > 0 and
        (.callbackPolicy | length) > 0 and
        (.publication | length) > 0 and
        (.journal | length) > 0 and
        (.hooks | length) > 0) and
    ([.batchSemantics[].id] | sort) == ["batch-apply", "batch-close", "batch-create"] and
    .directSqlCensus.expectedTotal ==
        ([.directSqlCensus.scopes[].expectedCount] | add) and
    ([.directSqlCensus.scopes[].id] | length) ==
        ([.directSqlCensus.scopes[].id] | unique | length) and
    all(.gaps[]; .status == "pending")
' "$plan" >/dev/null

git cat-file -e "$target_commit^{commit}"
[[ -f "$inventory_path" ]]

command_count="$(gzip -dc "$inventory_path" | jq '[.snapshots[].commands[].id] | unique | length')"
if [[ "$command_count" -ne 305 ]]; then
    printf 'storage capability inventory has %s commands; expected 305\n' "$command_count" >&2
    exit 1
fi

inventory_roots="$({
    gzip -dc "$inventory_path" | jq -r '
        [.snapshots[].commands[].id] | unique[] |
        if . == "cmd:bd" then "<root>"
        else sub("^cmd:bd/"; "") | split("/")[0]
        end
    '
} | sort -u)"
planned_roots="$(jq -r '[.commandProfiles[].roots[]] | unique[]' "$plan" | sort -u)"
if [[ "$inventory_roots" != "$planned_roots" ]]; then
    printf 'storage capability command-root coverage drifted\n' >&2
    diff -u <(printf '%s\n' "$inventory_roots") <(printf '%s\n' "$planned_roots") >&2 || true
    exit 1
fi

registry_path="$(jq -r '.authorities.contractLegRegistry' "$plan")"
registered_legs="$(
    git show "$target_commit:$registry_path" |
        sed -n 's/.*registerContractLeg(contractLeg{name: "\([^"]*\)".*/\1/p' |
        sort -u
)"
planned_legs="$(jq -r '.backendLegs[].id' "$plan" | sort -u)"
if [[ "$registered_legs" != "$planned_legs" ]]; then
    printf 'registered storage legs drifted\n' >&2
    diff -u <(printf '%s\n' "$registered_legs") <(printf '%s\n' "$planned_legs") >&2 || true
    exit 1
fi

while IFS= read -r source_path; do
    git cat-file -e "$target_commit:$source_path"
done < <(jq -r '
    [.authorities.storageInterface,
     .authorities.contractLegRegistry,
     .authorities.contractLegWiring,
     .authorities.hookBoundary,
     .authorities.transactionSources[],
     .backendLegs[].sourceEvidence[],
     .batchSemantics[].sourceEvidence[]] | unique[]
' "$plan")

sql_sources=()
while IFS= read -r source_path; do
    sql_sources+=("$source_path")
done < <(
    git grep -lE "$(jq -r '.directSqlCensus.searchPattern' "$plan")" \
        "$target_commit" -- \
        "$(jq -r '.directSqlCensus.sourceGlob' "$plan")" \
        ":!$(jq -r '.directSqlCensus.excludedGlob' "$plan")" |
        sed "s/^$target_commit://" |
        sort -u
)

expected_total="$(jq -r '.directSqlCensus.expectedTotal' "$plan")"
if [[ "${#sql_sources[@]}" -ne "$expected_total" ]]; then
    printf 'direct-SQL census has %d sources; expected %s\n' \
        "${#sql_sources[@]}" "$expected_total" >&2
    exit 1
fi

for source_path in "${sql_sources[@]}"; do
    match_count=0
    while IFS=$'\x1f' read -r scope_id path_regex _; do
        if [[ "$source_path" =~ $path_regex ]]; then
            match_count=$((match_count + 1))
        fi
    done < <(jq -r '.directSqlCensus.scopes[] | [.id, .pathRegex, .expectedCount] | join("\u001f")' "$plan")
    if [[ "$match_count" -ne 1 ]]; then
        printf 'direct-SQL source matches %d scopes: %s\n' "$match_count" "$source_path" >&2
        exit 1
    fi
done

while IFS=$'\x1f' read -r scope_id path_regex expected_count; do
    actual_count=0
    for source_path in "${sql_sources[@]}"; do
        if [[ "$source_path" =~ $path_regex ]]; then
            actual_count=$((actual_count + 1))
        fi
    done
    if [[ "$actual_count" -ne "$expected_count" ]]; then
        printf 'direct-SQL scope %s has %d sources; expected %s\n' \
            "$scope_id" "$actual_count" "$expected_count" >&2
        exit 1
    fi
done < <(jq -r '.directSqlCensus.scopes[] | [.id, .pathRegex, .expectedCount] | join("\u001f")' "$plan")

printf 'storage capability plan: PASS (305 commands; 13 profiles; 3 backend legs; 209 direct-SQL sources; 5 explicit gaps)\n'
