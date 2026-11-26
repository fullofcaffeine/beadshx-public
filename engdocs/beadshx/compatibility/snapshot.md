# Snapshot extension

`bdhx snapshot` prints a read-only snapshot of every issue in an embedded
workspace. Upstream `bd` v1.2.1 has no such command, so this is a recorded
extension ([exceptions.md](../program/exceptions.md)). The root help does not
list it; `bdhx snapshot --help` describes it. It takes only the global
selection inputs (`-C`, `--db`, `BEADS_DIR`, `BEADS_DB`).

## Format

The artifact uses schema `beadshx-task-snapshot/1`. It is JSON Lines in
UTF-8, with a line feed after every line:

- Line 1 is a header. Its keys are in byte order: `_dolt_branch`
  (`active_branch()`), `_dolt_commit` (`DOLT_HASHOF('HEAD')`), `_dolt_state`
  (`DOLT_HASHOF_DB()`), `_project_id` (left out when the database has none),
  `_records` (the number of issue lines), `_schema`, `_scope` (`all-issues`)
  and `_sort` (`id-bytewise`).
- Every other line is the line that upstream `bd export --all` prints for one
  issue, including wisps, templates, gates and other infrastructure types,
  sorted by issue ID in byte order. Memories and config rows are not
  included.

## Guarantees

The command reads everything in one Dolt read transaction, which it rolls
back. It writes no file and no database row, and stdout stays empty until the
whole snapshot is read. The same `_dolt_state` gives the same bytes in every
directory, time zone and locale. A change to a wisp, which Dolt never
commits, also moves `_dolt_state`. The artifact holds no config row, remote
URL, credential, environment value, path, actor, host name, time of capture
or `bdhx` version. Errors go to stderr and exit with code 1, also with
`--json`.

`snapshot` reads embedded workspaces only (see
[Known limits](limits.md#server-mode-proxied-and-shared-server-workspaces)).

`snapshot` opens the database like a plain upstream command. So on a
database behind the binary it stops with upstream's read-only error, and
when the workspace has a Dolt remote it stops with upstream's
remote-migrate gate message instead (see
[Storage modes](storage-modes.md)).

## Use

Choose the file yourself, for example in a git-ignored build directory such
as `build/caf/`: `bdhx snapshot > build/caf/tasks.jsonl`. Never write it
under `.beads/`, where upstream keeps its own `issues.jsonl`. The artifact
holds the task text, so do not commit it to a public repository. Upstream
`bd import` skips the header line, so `bd import <artifact>` restores the
issues into a fresh workspace. Upstream import drops a dependency between a
wisp and a durable issue.
