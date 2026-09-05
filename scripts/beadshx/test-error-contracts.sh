#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

plan="compatibility/error-contracts/plan.json"
target_commit="$(jq -er '.compatibilityTarget.commit' "$plan")"
inventory_path="$(jq -er '.authorities.commandTree' "$plan")"

jq -e '
    .schemaVersion == 1 and
    .compatibilityTarget.project == "Beads" and
    .compatibilityTarget.version == "v1.2.1" and
    .status == "planned" and
    (.classificationRule | test("Never classify by exit number alone")) and
    (.goTypePolicy | test("implementation evidence only")) and
    (.semanticClasses | keys | sort) == [
        "cancellation", "conflict", "deadline", "internalDefect",
        "partialSuccess", "semantic", "storage", "success", "usage"
    ] and
    ([.exitObservations[].id] | length) == ([.exitObservations[].id] | unique | length) and
    ([.exitObservations[].code] | unique | sort) == [0, 1, 2, 3, 4, 10, 11, 12, 13, 75, 130] and
    ([.exitObservations[] | select(.code == 2)] | length) >= 3 and
    ([.passthroughExitPolicies[].id] | sort) == [
        "hooks-run-child", "mail-delegate-child", "metrics-flusher-child"
    ] and
    ([.diagnosticRoutes[].id] | length) == ([.diagnosticRoutes[].id] | unique | length) and
    ([.signalFamilies[].id] | sort) == [
        "interactive-prompt", "list-watch-and-display",
        "root-graceful-shutdown", "serve"
    ] and
    all(.signalFamilies[]; .candidateStatus == "pending") and
    ([.representativeCases[].id] | length) == ([.representativeCases[].id] | unique | length) and
    all(.representativeCases[];
        .candidateStatus == "pending" and
        (.sourceEvidence | length) > 0 and
        (.persistentState == "unchanged" or
         .persistentState == "partial" or
         .persistentState == "changed-before-cancel")) and
    all(.gaps[]; .status == "pending") and
    (([.exitObservations[].classes[], .representativeCases[].class, .gaps[].class] | unique | sort) ==
     (.semanticClasses | keys | sort))
' "$plan" >/dev/null

git cat-file -e "$target_commit^{commit}"
[[ -f "$inventory_path" ]]
[[ -f "$(jq -er '.authorities.outputPlan' "$plan")" ]]

while IFS= read -r command_id; do
    gzip -dc "$inventory_path" | jq -e --arg commandId "$command_id" \
        'any(.snapshots[].commands[]; .id == $commandId)' >/dev/null
done < <(jq -r '
    [.exitObservations[].commandIds[]?,
     .passthroughExitPolicies[].commandIds[]?,
     .representativeCases[].commandId] | unique[]
' "$plan")

while IFS= read -r source_path; do
    git cat-file -e "$target_commit:$source_path"
done < <(jq -r '
    [.authorities.protocolTests[],
     .authorities.routingSources[],
     .exitObservations[].sourceEvidence[],
     .passthroughExitPolicies[].sourceEvidence[],
     .diagnosticRoutes[].sourceEvidence[],
     .signalFamilies[].sourceEvidence[],
     .representativeCases[].sourceEvidence[]] | unique[]
' "$plan")

printf 'error compatibility plan: PASS (11 fixed exit codes; 3 passthrough policies; 6 representative cases; 5 explicit gaps)\n'
