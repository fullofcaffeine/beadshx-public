# ADR 0004: Side-by-side upstream oracle

Status: accepted for implementation.

## Decision

Keep an exact v1.2.1 oracle named `bd-upstream` beside the candidate `bdhx`.
Run differential scenarios in separate identical disposable workspaces and use
opposite-binary readback for writes.

## Alternatives considered

Snapshots alone miss persistent effects. Delegating unfinished commands hides
coverage gaps. Replacing `bd` early makes rollback and diagnosis unsafe.

## Authority boundary

The pinned binary is expected-behavior evidence, not BeadsHX implementation.
The candidate owns no compatibility claim until process and logical-state
evidence agree or a visible divergence is approved.

## Removal test and risks

The oracle can stop being an operational fallback only after the release soak
and rollback gates; retain its source and evidence afterward. Reopen the pin
only through the next-target upgrade process. Risks include fixture asymmetry
and overbroad normalization; hashed cloning and explicit field normalizers
control them.
