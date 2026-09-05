#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

plan="compatibility/output-contracts/plan.json"
target_commit="$(jq -er '.compatibilityTarget.commit' "$plan")"
inventory_path="$(jq -er '.authorities.commandTree.path' "$plan")"
corpus_path="$(jq -er '.authorities.jsonCorpus.manifestPath' "$plan")"

digest_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

jq -e '
    .schemaVersion == 1 and
    .compatibilityTarget.project == "Beads" and
    .compatibilityTarget.version == "v1.2.1" and
    .status == "planned" and
    (.fieldClasses | keys | sort) == ["presentationOnly", "stable", "volatile"] and
    (.presentationCases | length) == 6 and
    ([.presentationCases[].id] | length) == ([.presentationCases[].id] | unique | length) and
    all(.presentationCases[];
        (.status == "pending" or .status == "complete") and
        .executionOwner == "BHX-M06" and
        (.args | type) == "array" and
        (.covers | length) > 0 and
        (.fieldClasses | length) > 0 and
        all(.fieldClasses[]; . == "stable" or . == "volatile" or . == "presentationOnly") and
        (.sourceEvidence | length) > 0 and
        all(.endpoints[]; . == "pipe" or . == "terminal")) and
    ([.presentationCases[] | select(.status == "complete") | .id] ==
        ["legacy-json-stderr-notice"]) and
    (.presentationCases[] | select(.id == "legacy-json-stderr-notice") |
        .evidence == ["scripts/beadshx/test-parity-smoke.sh"]) and
    (.gaps | length) > 0 and
    all(.gaps[]; .status == "pending")
' "$plan" >/dev/null

git cat-file -e "$target_commit^{commit}"

[[ "$(digest_file "$inventory_path")" == \
    "$(jq -er '.authorities.commandTree.sha256' "$plan")" ]]
[[ "$(digest_file "$corpus_path")" == \
    "$(jq -er '.authorities.jsonCorpus.sha256' "$plan")" ]]
[[ "$(git show "$target_commit:$corpus_path" | shasum -a 256 | awk '{print $1}')" == \
    "$(jq -er '.authorities.jsonCorpus.sha256' "$plan")" ]]

jq -e '
    .schema_version == 1 and
    .generated_by == "cmd/bd/protocol TestCorpusGolden" and
    (.blobs | length) == 34 and
    ([.blobs | keys[] | select(startswith("flat/"))] | length) == 17 and
    ([.blobs | keys[] | select(startswith("envelope/"))] | length) == 17
' "$corpus_path" >/dev/null

while IFS=$'\t' read -r blob expected; do
    artifact="cmd/bd/protocol/testdata/corpus/$blob.json"
    [[ -f "$artifact" ]]
    [[ "$(digest_file "$artifact")" == "$expected" ]]
done < <(jq -r '.blobs | to_entries[] | [.key, .value.sha256] | @tsv' "$corpus_path")

for required_path in \
    "$(jq -er '.authorities.jsonCorpus.catalogPath' "$plan")" \
    "$(jq -er '.authorities.differentialRunner.path' "$plan")" \
    "$(jq -er '.authorities.differentialRunner.catalogPath' "$plan")"; do
    [[ -e "$required_path" ]]
done

while IFS= read -r command_id; do
    gzip -dc "$inventory_path" | jq -e --arg commandId "$command_id" \
        'any(.snapshots[].commands[]; .id == $commandId)' >/dev/null
done < <(jq -r '.presentationCases[].commandId' "$plan" | sort -u)

while IFS= read -r source_path; do
    [[ -f "$source_path" ]]
done < <(jq -r '.presentationCases[].sourceEvidence[]' "$plan" | sort -u)

printf 'output compatibility plan: PASS (34 corpus blobs; 6 presentation cases; 4 explicit gaps)\n'
