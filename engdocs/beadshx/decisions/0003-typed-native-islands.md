# ADR 0003: Typed native islands

Status: superseded by ADR 0008. Retained as historical context.

## Decision

Every native Go island must be the smallest typed facade for a real Go library,
CGO, platform, callback, concurrency, pointer, or host-export boundary. It must
document inputs, outputs, errors, effects, cancellation, resource ownership,
tests, license duties, and shrink evidence.

## Alternatives considered

Broad Go service layers obscure policy ownership. Raw injection and untyped
maps move errors to runtime. A ban on all native code is incompatible with the
Go ecosystem and the pinned product.

## Authority boundary

Islands translate and execute native mechanics. They cannot select work,
validate product rules, define command meaning, or implement Brew closeout.

## Removal test and risks

Remove or shrink an island when typed haxe.go output passes its conformance and
runtime tests. Reopen the facade shape when two consumers prove a smaller
stable contract. The risk is convenience-driven growth; inventory, size trend,
dependency guards, and per-island review control it.
