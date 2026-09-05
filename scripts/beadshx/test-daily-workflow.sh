#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

require_approved=false
case "${1:-}" in
"") ;;
--require-approved) require_approved=true ;;
*)
    printf 'usage: %s [--require-approved]\n' "$0" >&2
    exit 2
    ;;
esac

validate_profile() (
    set -e
    local profile="$1"
    local inventory output_plan error_plan storage_plan effect_plan target_commit

    inventory="$(jq -er '.authorities.commandInventory' "$profile")"
    output_plan="$(jq -er '.authorities.outputContracts' "$profile")"
    error_plan="$(jq -er '.authorities.errorContracts' "$profile")"
    storage_plan="$(jq -er '.authorities.storageContracts' "$profile")"
    effect_plan="$(jq -er '.authorities.effectContracts' "$profile")"
    target_commit="$(jq -er '.compatibilityTarget.commit' "$profile")"

    jq -e --argjson requireApproved "$require_approved" '
        .schemaVersion == 1 and
        .compatibilityTarget == {
            project: "Beads",
            version: "v1.2.1",
            commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"
        } and
        (.authorities | keys | sort) == [
            "commandInventory", "effectContracts", "errorContracts",
            "outputContracts", "storageContracts"
        ] and
        .scope.d0IsFullCompatibility == false and
        .scope.unassignedInventoryCommandsRemainRequired == true and
        (.scope.writeStagePrerequisite | length) > 0 and
        (.privacySafeEvidence | keys | sort) == [
            "ambiguousRootInvocationCount", "candidateInvocationCount",
            "coarseWindow", "collectionDate", "rankingDecision",
            "recognizedCommandCounts", "sourceClass"
        ] and
        .privacySafeEvidence.collectionDate == "2026-08-15" and
        .privacySafeEvidence.coarseWindow == "2025-12 through 2026-08" and
        .privacySafeEvidence.candidateInvocationCount == 51 and
        .privacySafeEvidence.ambiguousRootInvocationCount == 12 and
        .privacySafeEvidence.recognizedCommandCounts == {
            doctor: 2, init: 10, list: 1, migrate: 2, prime: 4,
            ready: 1, setup: 4, show: 1, upgrade: 3
        } and
        .daily.id == "D0" and
        .daily.priority == "automation-first" and
        (.daily.commands | length) == 24 and
        (.daily.commands | unique | length) == 24 and
        (.daily.flags | length) == 24 and
        (.daily.flags | unique | length) == 24 and
        (.daily.outputCaseIds | length) == 3 and
        (.daily.outputCaseIds | unique | length) == 3 and
        (.daily.errorCaseIds | length) == 5 and
        (.daily.errorCaseIds | unique | length) == 5 and
        (.daily.storageProfileIds | length) == 5 and
        (.daily.storageProfileIds | unique | length) == 5 and
        .daily.effectRecipeIds == .daily.storageProfileIds and
        .next.id == "D1" and
        (.next.commands | length) == 18 and
        (.next.commands | unique | length) == 18 and
        ((.daily.commands - .next.commands) | length) ==
            (.daily.commands | length) and
        .remaining == {
            id: "D2",
            definition: "Every command in the pinned inventory that is not assigned to D0 or D1."
        } and
        .decisions.syncTier == "D1" and
        (.decisions.backupTreatment | test("prerequisite")) and
        (.decisions.repositoryWorkflowAddition | test("Heartbeat")) and
        (.approval | keys | sort) == ["date", "role", "status"] and
        .approval.role == "repository owner" and
        (.approval.status == "pending" or .approval.status == "approved") and
        (if .approval.status == "approved"
         then (.approval.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
         else .approval.date == null
         end) and
        (($requireApproved | not) or .approval.status == "approved")
    ' "$profile" >/dev/null

    [[ -f "$inventory" && -f "$output_plan" && -f "$error_plan" &&
        -f "$storage_plan" && -f "$effect_plan" ]]
    git cat-file -e "$target_commit^{commit}"

    for authority in "$output_plan" "$error_plan" "$storage_plan" "$effect_plan"; do
        jq -e --arg commit "$target_commit" \
            '.compatibilityTarget.commit == $commit' "$authority" >/dev/null
    done

    local inventory_commands inventory_flags daily_commands next_commands
    inventory_commands="$(gzip -dc "$inventory" |
        jq -r '[.snapshots[].commands[].id] | unique[]' | sort)"
    inventory_flags="$(gzip -dc "$inventory" |
        jq -r '[.snapshots[].flagDeclarations[].id] | unique[]' | sort)"
    daily_commands="$(jq -r '.daily.commands[]' "$profile" | sort)"
    next_commands="$(jq -r '.next.commands[]' "$profile" | sort)"

    while IFS= read -r command_id; do
        grep -Fx "$command_id" <<<"$inventory_commands" >/dev/null
    done <<<"$daily_commands"
    while IFS= read -r command_id; do
        grep -Fx "$command_id" <<<"$inventory_commands" >/dev/null
    done <<<"$next_commands"
    while IFS= read -r flag_id; do
        grep -Fx "$flag_id" <<<"$inventory_flags" >/dev/null
    done < <(jq -r '.daily.flags[]' "$profile")

    while IFS= read -r command_id; do
        gzip -dc "$inventory" | jq -e --arg command "$command_id" '
            [.snapshots[] | select(.activation == "normal") |
             any(.commands[]; .id == $command and .runnable)] == [true, true]
        ' >/dev/null
    done <<<"$daily_commands"

    while IFS= read -r case_id; do
        jq -e --arg caseId "$case_id" --slurpfile profile "$profile" '
            any(.presentationCases[];
                .commandId as $commandId |
                .id == $caseId and
                ($profile[0].daily.commands | index($commandId)) != null)
        ' "$output_plan" >/dev/null
    done < <(jq -r '.daily.outputCaseIds[]' "$profile")

    while IFS= read -r case_id; do
        jq -e --arg caseId "$case_id" --slurpfile profile "$profile" '
            any(.representativeCases[];
                .commandId as $commandId |
                .id == $caseId and
                ($profile[0].daily.commands | index($commandId)) != null)
        ' "$error_plan" >/dev/null
    done < <(jq -r '.daily.errorCaseIds[]' "$profile")

    local selected_profiles resolved_profiles
    selected_profiles="$(jq -r '.daily.storageProfileIds[]' "$profile" | sort)"
    resolved_profiles="$(jq -r --slurpfile profile "$profile" '
        .commandProfiles[] as $candidate |
        select(any($profile[0].daily.commands[];
            (sub("^cmd:bd/"; "") | split("/")[0]) as $root |
            ($candidate.roots | index($root)) != null)) |
        $candidate.id
    ' "$storage_plan" | sort -u)"
    [[ "$selected_profiles" == "$resolved_profiles" ]]

    while IFS= read -r profile_id; do
        jq -e --arg id "$profile_id" \
            'any(.commandProfiles[]; .id == $id)' "$storage_plan" >/dev/null
        jq -e --arg id "$profile_id" \
            'any(.commandRecipes[]; .profileId == $id)' "$effect_plan" >/dev/null
    done <<<"$selected_profiles"
)

profile="${BEADSHX_PROFILE:-compatibility/daily-workflow/profile.json}"
validate_profile "$profile"

if [[ "${BEADSHX_SKIP_NEGATIVE_TESTS:-false}" != "true" ]]; then
    temporary_directory="$(mktemp -d)"
    trap 'rm -rf "$temporary_directory"' EXIT

    mutations=(
        '.privacySafeEvidence.rawHistory = ["must never be retained"]'
        '.daily.commands += ["cmd:bd/not-real"]'
        '.daily.outputCaseIds += ["not-a-case"]'
        '.scope.d0IsFullCompatibility = true'
        '.next.commands += [.daily.commands[0]]'
    )
    index=0
    for mutation in "${mutations[@]}"; do
        index=$((index + 1))
        mutated="$temporary_directory/profile-$index.json"
        jq "$mutation" "$profile" >"$mutated"
        if BEADSHX_PROFILE="$mutated" BEADSHX_SKIP_NEGATIVE_TESTS=true \
            "$0" >/dev/null 2>&1; then
            printf 'daily workflow validator accepted negative mutation %s\n' \
                "$index" >&2
            exit 1
        fi
    done
fi

printf 'daily workflow compatibility profile: PASS'
if [[ "$(jq -r '.approval.status' "$profile")" == "pending" ]]; then
    printf ' (repository-owner approval pending)'
fi
printf '\n'
