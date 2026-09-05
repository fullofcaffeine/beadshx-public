#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
descriptor="${BEADSHX_CAF_INTENT:-$repository_root/caf/providers/beadshx-task-port.intent.json}"
locks="$repository_root/engdocs/beadshx/program/source-locks.json"

case "$descriptor" in
	/*) ;;
	*) descriptor="$repository_root/$descriptor" ;;
esac

jq -e '
  keys == ["authority", "claims", "effectUpperBounds", "exactSourceIntent", "fallback", "futureEvidenceExpectations", "identity", "proposedTaskPortCapabilities", "schema", "schemaVersion", "selection"] and
  .schema == "beadshx.caf-provider-intent" and
  .schemaVersion == 1 and
  .authority == "authored-intent-only" and
  .identity.providerId == "caf.provider.task-port.beadshx-candidate" and
  .identity.product == "BeadsHX" and
  .identity.sourceRepository == "https://github.com/fullofcaffeine/beadshx.git" and
  .selection == {status:"unselected", activation:"none", execution:"none"} and
  .exactSourceIntent.beadshxRevision == "exact-release-commit-required" and
  .exactSourceIntent.sourceLock == "engdocs/beadshx/program/source-locks.json" and
  .proposedTaskPortCapabilities == [
    {id:"caf.capability.task-port-read-model", version:1},
    {id:"caf.capability.task-port-mutation-contracts", version:1},
    {id:"caf.capability.task-port-beads-writer", version:2}
  ] and
  .effectUpperBounds == [
    "caf.effect.task-port.claim",
    "caf.effect.task-port.append-evidence",
    "caf.effect.task-port.close"
  ] and
  .fallback == {binary:"bd-upstream", policy:"direct-pinned-upstream", automaticDelegation:false} and
  .futureEvidenceExpectations == [
    "exact-provider-source-lock",
    "task-port-contract-conformance",
    "read-before-write-read-after",
    "native-task-readback",
    "effect-policy-approval",
    "terminal-action-receipt",
    "fallback-parity-evidence",
    "reversible-removal"
  ] and
  .claims == {
    installation:false,
    availability:false,
    selection:false,
    permission:false,
    execution:false,
    taskState:false,
    effectSuccess:false,
    receiptSuccess:false
  }
' "$descriptor" >/dev/null || {
	printf 'Caf provider intent does not match the no-effect authored contract: %s\n' "$descriptor" >&2
	exit 1
}

jq -e --slurpfile locks "$locks" '
  .exactSourceIntent.compatibilityTarget == ($locks[0].compatibilityTarget | {version, commit}) and
  .exactSourceIntent.cafeteraContract.commit == $locks[0].cafetera.liveStartingCommit and
  .exactSourceIntent.compiler.commit == $locks[0].compiler.requiredCommit
' "$descriptor" >/dev/null

if jq -e '
  [paths(scalars) as $path |
    ($path[-1] | tostring | ascii_downcase) as $key |
    select($key == "taskid" or $key == "taskstatus" or $key == "hostname" or
      $key == "hostpath" or $key == "localpath" or $key == "commandresult" or
      $key == "receiptid" or $key == "receiptstatus" or $key == "runtimefacts")
  ] | length > 0
' "$descriptor" >/dev/null; then
	printf 'Caf provider intent contains an observed task, host, command, or receipt field\n' >&2
	exit 1
fi

if jq -e '[.. | strings | select(startswith("/") or test("^[A-Za-z]:[\\\\/]"))] | length > 0' "$descriptor" >/dev/null; then
	printf 'Caf provider intent contains a machine-local absolute path\n' >&2
	exit 1
fi

relative_descriptor="${descriptor#"$repository_root/"}"
if [[ "$relative_descriptor" == "$descriptor" ]]; then
	relative_descriptor="caf/providers/beadshx-task-port.intent.json"
fi
if git -C "$repository_root" grep -l -F "$relative_descriptor" -- \
	compile.bootstrap.hxml src native generated release scripts/beadshx/package-bootstrap 2>/dev/null | \
	grep -v '^scripts/beadshx/check-caf-provider-intent\.sh$' >/dev/null; then
	printf 'Caf provider intent is referenced by a runtime, compiler, or package input\n' >&2
	exit 1
fi

printf 'Caf provider authored intent: PASS (unselected and non-executing)\n'
