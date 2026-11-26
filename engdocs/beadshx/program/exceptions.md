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

The compatibility manifest (`compatibility/manifests/beads-v1.2.1.json`,
BHX-M02-10) records each approved exception below as a waiver. These records
remain the approval source that the waivers cite.

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

### `bdhx snapshot` is a hidden BeadsHX extension

- **Affected:** a new command, `bdhx snapshot`, in embedded workspaces of the
  read-only build, on every platform. Upstream bd v1.2.1 has no such command:
  `bd snapshot` prints `Error: unknown command "snapshot" for "bd"`. The
  command is hidden: the root help does not list it, so the root help stays
  byte-equal to upstream. `bdhx` has no completion command yet; a port of
  upstream's must leave `snapshot` out. `bdhx snapshot --help` and
  `bdhx help snapshot` print its help.
- **User impact:** the command prints a read-only task snapshot artifact on
  stdout, schema `beadshx-task-snapshot/1` (JSON Lines). Line 1 is a header
  with the Dolt revision of the read (`_dolt_branch`, `_dolt_commit`,
  `_dolt_state`, `_project_id`, `_records`, `_schema`, `_scope`, `_sort`).
  Every other line is the line that upstream `bd export --all` prints for one
  issue, sorted by issue ID in byte order. It writes no file and no database
  row. It refuses server-mode, shared-server, proxied and `--global`
  workspaces, and prints errors on stderr only, also with `--json`. The
  artifact holds the task text, so it must not go to a public repository.
- **Migration impact:** none. The artifact is derived; delete it at any time
  and run the command again.
- **Fixture and tests:** `scripts/beadshx/test-snapshot.sh` (the spec's
  acceptance tests a to i), `scripts/beadshx/test-export-read.sh` (the Haxe
  export read against upstream `bd export --all`), and the
  `snapshot-extension` case in `scripts/beadshx/test-parity-smoke.sh`, which
  exempts this one name from the unknown-command comparison.
- **Reason:** BHX-M08-09 asks for an optional deterministic task snapshot with
  the native revision, for parity, Caf and recovery consumers. Upstream has
  no command that gives the issue records together with the revision they
  come from.
- **Disposition:** approved by the owner, fullofcaffeine, on 2026-11-22, as
  spec v1 of BHX-M08-09, including the name, the hidden command and the
  all-issues record set.
- **Owner, review trigger and removal condition:** fullofcaffeine. Review when
  upstream adds a `snapshot` command, when the Caf consumers (M10-11, M19-03,
  M19-05) start to read the artifact, and before any change to the header
  keys, the record set, the record encoding or the order, which needs a new
  `_schema` number. Rename the command if upstream takes the name.
- **Rollback and upstream fallback:** upstream `bd export --all` prints the
  same issue lines, in another order and with memory lines. Without the
  command, nothing reads the artifact yet; `bd-upstream import` restores a
  workspace from it (upstream import skips the header line).
