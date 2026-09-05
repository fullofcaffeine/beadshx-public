# ADR 0002: Dolt remains native storage authority

Status: superseded by ADR 0008. Dolt remains the data authority, but
first-party Beads storage coordination moves to Haxe.

## Decision

Retain upstream Dolt, its driver, transactions, versioning, sync, concurrency,
and recovery behind typed capability facades. Do not expose SQL or Dolt types
to Haxe domain code.

## Alternatives considered

Replacing Dolt would break the primary compatibility contract. Raw SQL in Haxe
would leak storage policy. Copying task truth into CML or a Caf graph would
create competing authorities.

## Authority boundary

The Beads-compatible database owns mutable task state. Haxe owns validated
application intent and postconditions. The native facade owns transaction and
resource lifetime.

## Removal test and risks

Reopen only if the compatibility target itself changes storage authority or a
fully qualified migration is separately approved. The main risks are storage
details leaking upward and output-only parity hiding corruption; dependency
guards, disposable fixtures, and cross-binary readback control them.
