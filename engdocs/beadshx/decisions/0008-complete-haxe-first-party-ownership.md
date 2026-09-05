# ADR 0008: Complete Haxe ownership of first-party Beads code

Status: accepted by the requester for implementation. This does not admit a
release.

## Decision

Port every upstream Beads first-party Go implementation package to authored
Haxe. An exported Beads API is useful as temporary oracle or tracer scaffolding,
but it is not a permanent library boundary. Release paths must not import or
link upstream Beads command, issueops, storage, unit-of-work, domain,
configuration, sync, integration, or rendering implementations.

Haxe can consume the Go standard library and independent third-party packages,
including Cobra and Dolt drivers, through precise externs. Haxe owns their
lifecycle and all Beads-facing behavior. If haxe.go cannot express a required
exported API safely, first reduce the gap to a library-neutral fixture, then fix
the compiler, staged Go SDK, or extern tooling through its normal worktree and
PR flow. Merge that fix before BeadsHX advances its compiler lock and proves the
original path.

## Alternatives considered

Keeping upstream Beads packages behind externs would exercise interop but leave
part of the product unported. Handwritten Go facades around first-party Beads
code would preserve the same split under a smaller name. Reimplementing Cobra,
Dolt, SQL drivers, CGO, and unrelated SDKs would waste effort and make those
independent libraries harder to update. Bypassing Go visibility would be unsafe
and would make generated Go invalid by construction.

## Authority boundary

Authored Haxe owns all Beads behavior, storage coordination, transactions,
commands, protocols, and operational policy. The Beads-compatible Dolt database
remains mutable task authority. Standard-library and independent third-party Go
packages own only their documented mechanics and are reached through precise
externs. Generated Go is disposable compiler output. The pinned upstream source
and binary are compatibility oracles, never release implementations.

## Migration and release test

Existing first-party Go facades and externs are removal-tracked migration
scaffolding. A vertical slice can use them to prove behavior or a haxe.go ABI,
but that evidence cannot close the final port task. Release qualification must
inspect imports and linked symbols and prove that no upstream Beads first-party
implementation is reachable.

## Risks and reopening conditions

The main risks are underestimating storage and lifecycle behavior, duplicating
third-party libraries in Haxe, and hiding compiler gaps in consumer wrappers.
Disposable database fixtures, native readback, differential tests, compiler
fixtures, and dependency guards control those risks. Reopen this decision only
with an explicit requester decision that names a specific first-party package,
why it cannot be ported, the compatibility and maintenance impact, and its
removal condition.
