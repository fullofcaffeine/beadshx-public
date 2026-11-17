# Direct embedded comment contracts

Run `bash scripts/beadshx/test-sql-error-contracts.sh` after toolchain setup. The wrapper copies authored inputs into a marked temporary workspace. It leaves the source checkout and primary database untouched.

The body observer calls Beads v1.2.1 `GetIssueCommentsInTx` and the detail assembler. It covers 21 cases, including independent wisp routing, literal and empty IDs, native scan types, foreign rows, and query, scan, iteration, and close errors.

The 25 detail cases compare the pinned count SQL and native `int64` scan contract through the detail assembler. They cover best-effort count errors, retained values after close errors, requested body failures, omission, and integer limits. This observer does not inject a fake connection into the real embedded store. The separate `--embedded-comments` gate compares that store with the Haxe paths on the same disposable database.

The wrapper requires fresh observations, exact case counts, JSON types, and record order. Missing, reordered, truncated, or differently typed results fail. The observers skip ordinary `go test` runs unless their capture variable is set. They remain test authorities, not runtime dependencies of the Haxe reader.

Earlier UOW observations are a different contract. They do not establish direct embedded-store parity. These SQL mocks do not qualify database attachment or edge hydration. The native count error is intentionally ignored only at the detail assembly boundary; the nullable scan carrier is not a general replacement for native `*int64` error semantics.
