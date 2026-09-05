#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

plan="compatibility/effect-contracts/plan.json"
storage_plan="$(jq -er '.authorities.commandProfiles' "$plan")"
inventory_path="$(jq -er '.authorities.commandTree' "$plan")"
target_commit="$(jq -er '.compatibilityTarget.commit' "$plan")"

jq -e '
    .schemaVersion == 1 and
    .compatibilityTarget.project == "Beads" and
    .compatibilityTarget.version == "v1.2.1" and
    .status == "planned" and
    (.ownershipRule | test("Authored Haxe owns command policy")) and
    (.recipeRule | test("ordered effect recipe")) and
    (.effectFamilies | sort) == [
        "credential", "doltVersionControl", "hostFilesystem",
        "hostGit", "network", "process"
    ] and
    (.rollbackClasses | sort) == [
        "atomic_replace", "best_effort_cleanup", "compensating_action",
        "irreversible", "not_applicable", "remote_indeterminate",
        "restore_from_backup", "transaction_rollback"
    ] and
    (.lifecyclePhases | sort) == [
        "after_commit", "authorize", "cleanup", "discover",
        "execute", "prepare", "publish"
    ] and
    ([.effects[].id] | length) == 21 and
    ([.effects[].id] | length) == ([.effects[].id] | unique | length) and
    ([.commandRecipes[].profileId] | length) == 13 and
    ([.commandRecipes[].profileId] | length) ==
        ([.commandRecipes[].profileId] | unique | length) and
    ([.sourceCensuses[].id] | sort) == [
        "child-process-call-sites", "filesystem-call-sites",
        "network-boundary-call-sites"
    ] and
    all(.sourceCensuses[];
        (.pattern | length) > 0 and
        .expectedCount > 0 and
        (.disposition | length) > 0) and
    ([.sourceScopes[].id] | length) ==
        ([.sourceScopes[].id] | unique | length) and
    all(.sourceScopes[];
        (.censusId | length) > 0 and
        (.pathRegex | length) > 0 and
        (.owner | length) > 0 and
        (.effectIds | length) > 0 and
        (.disposition == "semantic-extraction" or
         .disposition == "target-adapter" or
         .disposition == "evidence-only")) and
    (([.sourceScopes[].censusId] | unique) -
        [.sourceCensuses[].id]) == [] and
    (([.sourceScopes[].effectIds[]] | unique) -
        [.effects[].id]) == [] and
    ([.delegatedPrograms[]] | sort) == [
        "bd-metrics-child", "credential-helper", "dolt", "editor", "gh",
        "git", "gt", "hook", "mail", "pager", "platform-utility",
        "shell-helper"
    ] and
    ([.externalServices[]] | sort) == [
        "ai-provider", "azure-devops", "azure-storage", "dolthub", "github",
        "gitlab", "google-cloud", "jira", "linear", "local-file-remote",
        "metrics-endpoint", "notion", "oci", "opentelemetry-collector",
        "pypi", "release-service", "s3-compatible"
    ] and
    ([.platformProfiles | keys[]] | sort) == [
        "dolt-native", "native-process", "native-service", "portable-file",
        "remote-client"
    ] and
    all(.platformProfiles[];
        (keys | sort) == [
            "cgo", "linux", "macos", "nonCgo", "unix", "wasm", "windows"
        ] and all(.[]; strings and length > 0)) and
    all(.effects[];
        (.id | length) > 0 and
        (.family as $value | $value != null) and
        (.commandProfiles | length) > 0 and
        (.phases | length) > 0 and
        (.storageSteps | length) > 0 and
        (.semanticOwner | length) > 0 and
        (.nativeOwner | length) > 0 and
        ((.delegatedOwner == null) or (.delegatedOwner | length) > 0) and
        (.action | length) > 0 and
        (.target | length) > 0 and
        (.scope | length) > 0 and
        (.lifetime | length) > 0 and
        (.classification == "read" or .classification == "mutation") and
        (.preconditions | length) > 0 and
        (.consent | length) > 0 and
        (.authorityBoundary | length) > 0 and
        (.atomicity | length) > 0 and
        (.idempotence | length) > 0 and
        (.retry | length) > 0 and
        (.interruption | length) > 0 and
        (.rollbackClass | length) > 0 and
        (.recovery | length) > 0 and
        (.failureResult | length) > 0 and
        (.partialEffectWindow | length) > 0 and
        (.externalVisibility | length) > 0 and
        (.credentials | keys | sort) == [
            "childInheritance", "destination", "redaction", "source"
        ] and
        all(.credentials[]; strings and length > 0) and
        (.process | keys | sort) == [
            "cancellation", "cleanup", "signal", "timeout"
        ] and
        all(.process[]; strings and length > 0) and
        (.testSeam | length) > 0 and
        (.observer | length) > 0 and
        (.platformProfile | length) > 0 and
        (.platformResult | length) > 0 and
        (.sourceEvidence | length) > 0 and
        (.focusedTest | length) > 0 and
        has("waiver")) and
    (([.effects[].family] | unique) - .effectFamilies) == [] and
    (([.effects[].rollbackClass] | unique) - .rollbackClasses) == [] and
    (([.effects[].phases[]] | unique) - .lifecyclePhases) == [] and
    (([.effects[].storageSteps[]] | unique) - .storageRecipeSteps) == [] and
    (([.effects[].platformProfile] | unique) - (.platformProfiles | keys)) == [] and
    all(.commandRecipes[];
        (.negativeEvidence == null or (.negativeEvidence | length) > 0) and
        (.steps | length) > 0 and
        ([.steps[].order] == [range(1; (.steps | length) + 1)]) and
        all(.steps[];
            (.condition | length) > 0 and
            (.effectId | length) > 0 and
            (.phase | length) > 0 and
            (.storageStep | length) > 0)) and
    (. as $plan |
        (reduce range(0; (.lifecyclePhases | length)) as $index ({};
            .[$plan.lifecyclePhases[$index]] = $index)) as $phaseRank |
        all(.commandRecipes[];
            ([.steps[].phase | $phaseRank[.]] as $ranks |
             all(range(1; ($ranks | length));
                 $ranks[.] >= $ranks[. - 1])))) and
    all(.gaps[]; .status == "pending" and (.owner | length) > 0)
' "$plan" >/dev/null

git cat-file -e "$target_commit^{commit}"
[[ -f "$storage_plan" ]]
[[ -f "$inventory_path" ]]

planned_profiles="$(jq -r '.commandRecipes[].profileId' "$plan" | sort -u)"
storage_profiles="$(jq -r '.commandProfiles[].id' "$storage_plan" | sort -u)"
if [[ "$planned_profiles" != "$storage_profiles" ]]; then
    printf 'effect recipe profiles drifted from storage profiles\n' >&2
    diff -u <(printf '%s\n' "$storage_profiles") \
        <(printf '%s\n' "$planned_profiles") >&2 || true
    exit 1
fi

command_count="$(gzip -dc "$inventory_path" |
    jq '[.snapshots[].commands[].id] | unique | length')"
if [[ "$command_count" -ne 305 ]]; then
    printf 'effect contract command authority has %s commands; expected 305\n' \
        "$command_count" >&2
    exit 1
fi

while IFS= read -r effect_id; do
    declared_profiles="$(jq -r --arg effect "$effect_id" '
        .effects[] | select(.id == $effect) | .commandProfiles[]
    ' "$plan" | sort -u)"
    recipe_profiles="$(jq -r --arg effect "$effect_id" '
        .commandRecipes[] |
        select(any(.steps[]; .effectId == $effect)) |
        .profileId
    ' "$plan" | sort -u)"
    if [[ "$declared_profiles" != "$recipe_profiles" ]]; then
        printf 'effect %s command-profile bindings drifted\n' "$effect_id" >&2
        diff -u <(printf '%s\n' "$declared_profiles") \
            <(printf '%s\n' "$recipe_profiles") >&2 || true
        exit 1
    fi
done < <(jq -r '.effects[].id' "$plan")

while IFS=$'\x1f' read -r profile_id effect_id phase storage_step; do
    if ! jq -e --arg effect "$effect_id" --arg phase "$phase" \
        --arg storage "$storage_step" '
        any(.effects[];
            .id == $effect and
            (.phases | index($phase)) != null and
            (.storageSteps | index($storage)) != null)
    ' "$plan" >/dev/null; then
        printf 'recipe %s uses an undeclared effect phase or storage step: %s %s %s\n' \
            "$profile_id" "$effect_id" "$phase" "$storage_step" >&2
        exit 1
    fi
done < <(jq -r '
    .commandRecipes[] as $recipe |
    $recipe.steps[] |
    [$recipe.profileId, .effectId, .phase, .storageStep] | join("\u001f")
' "$plan")

while IFS= read -r source_path; do
    git cat-file -e "$target_commit:$source_path"
done < <(jq -r '[.effects[].sourceEvidence[], .authorities.httpSpec,
    .authorities.ignoreTemplate] | unique[]' "$plan")

for source_path in \
    internal/configfile/credentials_unix.go \
    internal/configfile/credentials_windows.go \
    internal/doltserver/doltserver_unix.go \
    internal/doltserver/doltserver_windows.go \
    internal/hooks/hooks_unix.go \
    internal/hooks/hooks_windows.go \
    internal/hooks/hooks_wasm.go \
    internal/procid/procid_darwin.go \
    internal/procid/procid_linux.go \
    internal/procid/procid_windows.go \
    internal/storage/dbproxy/proxy/endpoint_unix.go \
    internal/storage/dbproxy/proxy/endpoint_windows.go; do
    git cat-file -e "$target_commit:$source_path"
done

http_spec="$(jq -er '.authorities.httpSpec' "$plan")"
http_operations="$(git show "$target_commit:$http_spec" |
    grep -c -E '^[[:space:]]+operationId:')"
if [[ "$http_operations" -ne 41 ]]; then
    printf 'HTTP effect surface has %s operations; expected 41\n' \
        "$http_operations" >&2
    exit 1
fi

ignore_template="$(jq -er '.authorities.ignoreTemplate' "$plan")"
ignore_source="$(git show "$target_commit:$ignore_template")"
for artifact in \
    '.beads-credential-key' '.dolt' '.db' '.lock' '.log' '.pid' \
    '.sock' 'backup' 'metadata.json' 'redirect'; do
    if ! grep -F "$artifact" <<<"$ignore_source" >/dev/null; then
        printf 'ignore authority no longer names runtime artifact: %s\n' \
            "$artifact" >&2
        exit 1
    fi
done

while IFS=$'\x1f' read -r census_id pattern expected_count; do
    census_sources=()
    while IFS= read -r source_path; do
        census_sources+=("$source_path")
    done < <({
        git grep -lE "$pattern" "$target_commit" -- \
            '*.go' '*.sh' ':!*_test.go' ':!vendor/**' || true
    } | sed "s/^$target_commit://" | sort -u | sed '/^$/d')
    actual_count="${#census_sources[@]}"
    if [[ "$actual_count" -ne "$expected_count" ]]; then
        printf '%s census has %s production sources; expected %s\n' \
            "$census_id" "$actual_count" "$expected_count" >&2
        exit 1
    fi

    for source_path in "${census_sources[@]}"; do
        match_count=0
        while IFS= read -r path_regex; do
            if [[ "$source_path" =~ $path_regex ]]; then
                match_count=$((match_count + 1))
            fi
        done < <(jq -r --arg census "$census_id" '
            .sourceScopes[] | select(.censusId == $census) | .pathRegex
        ' "$plan")
        if [[ "$match_count" -ne 1 ]]; then
            printf '%s source matches %s semantic scopes: %s\n' \
                "$census_id" "$match_count" "$source_path" >&2
            exit 1
        fi
    done

    while IFS=$'\x1f' read -r scope_id path_regex; do
        scope_count=0
        for source_path in "${census_sources[@]}"; do
            if [[ "$source_path" =~ $path_regex ]]; then
                scope_count=$((scope_count + 1))
            fi
        done
        if [[ "$scope_count" -eq 0 ]]; then
            printf '%s source scope has no obligations: %s\n' \
                "$census_id" "$scope_id" >&2
            exit 1
        fi
    done < <(jq -r --arg census "$census_id" '
        .sourceScopes[] | select(.censusId == $census) |
        [.id, .pathRegex] | join("\u001f")
    ' "$plan")
done < <(jq -r '.sourceCensuses[] |
    [.id, .pattern, .expectedCount] | join("\u001f")' "$plan")

printf 'native effect contracts: PASS (305 commands; 13 recipes; 21 semantic effects; 6 effect families; 41 HTTP operations; 3 explicit gaps)\n'
