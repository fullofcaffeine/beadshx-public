# Compatibility exception policy

The completion definition in `beadshx-complete-port-prd.md` is the program
contract. Missing evidence is not a green result, and a milestone cannot infer
completion from a successful build or a smaller workflow profile.

An exception must be a visible compatibility divergence. It records:

- affected command, capability, state, mode, and platform;
- user and migration impact;
- reproducing fixture and tests;
- reason the pinned upstream behavior is not implemented unchanged;
- requester disposition and decision date;
- owner, review trigger, and removal or renewal condition;
- rollback and upstream fallback procedure.

Exceptions live in the compatibility manifest and generated report. They do
not hide an unknown or delegated surface, broaden another platform's evidence,
or waive production-data safety, native readback, licensing, provenance, or
recovery requirements.

## Recorded exceptions

Until the generated compatibility manifest exists (BHX-M02-10), each approved
exception is recorded here.

### Legacy-only workspaces refuse store commands

- **Affected:** `bdhx where` and every command that reads the database, in a
  workspace whose `.beads` directory has a valid legacy `config.json` and no
  `metadata.json`. This applies when the current directory, `-C`,
  `BEADS_DIR`, a `--db` path or a redirect selects the workspace, in every
  storage mode and on every platform of the read-only build.
- **User impact:** these commands exit 1 with `Error: <command> is not
  available yet when the workspace has only a legacy config.json in this
  build`, or the same message as a JSON error document with `--json`.
  Upstream bd v1.2.1 rewrites `config.json` as `metadata.json` and runs the
  command. `version`, help pages and unknown commands match upstream. With a
  `--db` path, upstream also rewrites the file for `version` and
  `bd help <command>`; `bdhx` prints the same output and writes nothing.
- **Migration impact:** none. `bdhx` leaves `config.json` in place.
- **Fixture and tests:** the `legacy-config-*` cases in
  `scripts/beadshx/test-parity-smoke.sh`, and the legacy-config tests and the
  `configfile.Load(` guard in
  `internal/beadshx/workspacefacade/facade_test.go`.
- **Reason:** the migration is a persistent write, and the M08 read-only
  profile makes none. Migration belongs to M12.
- **Disposition:** approved by the owner, fullofcaffeine, on 2026-11-22,
  including the refusal wording and the removal milestone (beadshx-m08-03.3).
- **Owner, review trigger and removal condition:** fullofcaffeine. Review
  when M12 (schema, migration, backup, doctor and recovery parity) starts.
  Remove the refusal when M12 ports the legacy config migration, and turn the
  `legacy-config-*` refusal cases into exact comparisons with upstream.
- **Rollback and upstream fallback:** run the pinned upstream `bd` once in the
  workspace with a command that opens the store, such as `bd where`. It
  migrates the file, and `bdhx` then reads the workspace normally.
