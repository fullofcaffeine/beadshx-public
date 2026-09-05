# Production data safety

BeadsHX compatibility work intentionally exercises writes, migrations,
concurrency, recovery, and faults. Those tests can damage real work if their
workspace boundary is wrong.

## Required boundary

Every automated or manual destructive scenario must use a newly created
temporary directory. The directory must contain a marker named
`.beadshx-disposable-fixture` before the first mutation. Both `bd init` and all
later commands run from inside that directory.

Do not treat `BEADS_DB`, a copied command line, a different Git branch, or a
generated database name as sufficient isolation. The workspace directory is
part of Beads behavior.

The test harness must reject:

- the BeadsHX source repository;
- a sibling source checkout;
- a directory without the disposable marker;
- a primary database or backup destination supplied through ambient state;
- a schema-skew bypass or an unreviewed Beads executable.

## Mutation evidence

Before migration, destructive recovery, or dogfood writes, preserve a verified
backup outside the source repository. After every candidate mutation, read the
logical result through the native authority. Process exit, stdout, a graph
projection, or a receipt proposal alone does not prove the mutation happened.

Early stages use this order:

1. read-only oracle and candidate behavior in disposable fixtures;
2. candidate writes in disposable fixtures with cross-binary readback;
3. copied or explicitly selected read-only real workspaces;
4. non-critical dogfood with verified backup and immediate upstream fallback;
5. primary workflow only after the documented cutover and rollback gates pass.

No stage promotes itself. Record the exact source, database revision, backup,
open defects, and rollback path before promotion.
