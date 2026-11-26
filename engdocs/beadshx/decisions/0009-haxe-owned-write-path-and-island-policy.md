# ADR 0009: Haxe-owned write path and Go island policy

Status: accepted for implementation. The owner, fullofcaffeine, made this
decision on 2026-11-22.

## Context

M09 adds the first BeadsHX commands that write to a Beads database. ADR 0008
gives authored Haxe all first-party storage coordination and transactions.
Older PRD lines still describe M09 writes "through typed Go adapters" and
storage "behind typed facades". The handwritten Go islands under
`internal/beadshx/` still call upstream Beads storage packages.

The owner asked for a design review of how M09 writes reach the store and of
the islands. The owner then made the decision below. The 2026-11-22 comments
on beadshx-m09-01 (write path) and beadshx-m04-01 (island rule) record it.

## Decision

M09 writes are Haxe-owned. A unit of work in authored Haxe writes through
precise externs over `database/sql` and the Dolt driver.

- No write goes through a handwritten Go island.
- No extern sits over an upstream Beads package.
- Server and proxied writes stay refused in M09.

## Island policy

This is the owner's standing rule for the handwritten Go islands
(`internal/beadshx/readonlyfacade` and `internal/beadshx/workspacefacade`):

1. They are frozen, removal-tracked scaffolding (ADR 0008).
2. The agent may, without an owner question, delete island code, narrow an
   island's API, or fix a divergence from upstream. The change must add no
   exported symbol, no new upstream import, no write-capable call and no
   product rule. It must come with parity cases and a README update.
3. Any change that adds an exported symbol, an upstream import or a
   write-capable call is refused. Port the behavior to Haxe instead.
4. No island may write: no `configfile.Load` and no writable store open.
5. Ratchet: non-test lines under `internal/beadshx/` and its import set may
   only shrink.

`scripts/beadshx/island-guard` enforces the ratchet and rule 4
(beadshx-m08.13). It compares the islands with
`compatibility/native-islands/baseline.json`. The baseline recorded 3,179
non-test lines when the guard landed and records 3,047 now. After a shrink,
the guard fails until the same commit lowers the baseline. Its `--update`
option never raises the baseline. The ratchet covers every non-test Go file
under `internal/beadshx/`, which also holds `gitfacade`, `profilefacade` and
`watchfacade`.

This rule is about the existing islands. AGENTS.md and ADR 0008 still say
when new handwritten Go is allowed.

## Consequences

ADR 0008 governs over the older PRD lines that say "typed Go adapters" or
"typed facades":

- the M09 objective: "Prove that Haxe-owned command behavior can safely
  mutate a real Beads database through typed Go adapters";
- the section 20 default: "Storage: upstream Dolt and storage packages behind
  typed facades".

This record does not edit the PRD, whose bytes `beadshx-prd-sha256.txt`
locks.

The owner set these first steps, in order:

1. Record ADR 0009. Done in this record (beadshx-m09.1).
2. Build one Haxe `EmbeddedSession` module, ported from upstream
   `embeddeddolt` `OpenSQL` (identity, backoff, ping, `USE`) and `withConn`
   (begin, body, commit or rollback, close). Move the 14 duplicated embedded
   open blocks onto it, read-only first, with the parity corpus green.
   The read-only half is done (beadshx-m08-03.10). Every embedded reader opens
   through `src/beadshx/store/EmbeddedSession.hx` with upstream's identity,
   backoff and ping, and reads in a transaction that it rolls back. `USE`, the
   branch head and the commit half of `withConn` are not done, because the
   build has no exec or commit extern yet.
3. Port upstream's schema skew check (`schema.CheckForwardDrift` and
   `CheckBehindDrift`, see beadshx-m12-01) into `EmbeddedSession` before any
   write. Done (beadshx-m08.12). `EmbeddedSession.open` runs the check at the
   first open of each workspace in a process.
4. Build the write-parity harness (beadshx-m09-10) and see it fail. It runs
   the same mutation through `bd-upstream` and `bdhx` on two clones, reads
   both back with the oracle, diffs every table with generated IDs,
   timestamps and hashes normalised, and injects faults. Not done. The logical
   database state comparison for it (beadshx-m06-07) is in progress.
5. Add the `Tx` `ExecContext` and `Commit` externs in one module that only the
   unit of work can reach. Land `label add` as the tracer write. Not started.

## Relation to ADR 0008

ADR 0008 is the parent decision. It gives authored Haxe all storage
coordination and transactions. It makes the existing first-party Go facades
and externs removal-tracked scaffolding, and it rejects handwritten Go facades
around first-party Beads code. This record applies ADR 0008 to the M09 write
path and to the existing islands. It does not change ADR 0008.
