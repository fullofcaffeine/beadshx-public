# ADR 0005: TaskPort is the neutral task boundary

Status: accepted for implementation.

## Decision

Expose the small provider-neutral task facts and operations needed by Caf and
future coordination through TaskPort. Keep Beads-specific data in typed
provider extensions or native evidence.

## Alternatives considered

A universal task schema would copy provider semantics. Direct database access
from Caf would bypass native authority. An arbitrary metadata bag would erase
the type boundary.

## Authority boundary

BeadsHX owns its provider adapter; the selected native database owns task
truth. TaskPort owns only the neutral contract. Graph and CML consumers cannot
mutate through projections.

## Removal test and risks

Remove a neutral field when no independent consumer needs its shared meaning.
Add one only after another provider proves it. Reopen the boundary if real
conformance cannot express the live Caf workflow without provider leakage.
