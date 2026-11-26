# Storage modes

A Beads workspace keeps its issues in a Dolt database. Upstream `bd` v1.2.1
can reach that database in four ways, and `bdhx` makes the same choice as
upstream:

- **Embedded mode** is the default. The database lives in
  `.beads/embeddeddolt`, and the command opens it directly.
- **Server mode** connects to a Dolt SQL server, for example when
  `.beads/metadata.json` sets `dolt_mode` to `server` or the `dolt.mode`
  setting is `server`.
- **Shared-server mode** uses one Dolt server under `~/.beads/shared-server`
  for every workspace. It comes from `dolt.shared-server` in `config.yaml`,
  `config.local.yaml` or the user `config.yaml`, or from
  `BEADS_DOLT_SHARED_SERVER` or `BD_DOLT_SHARED_SERVER`.
- **Proxied-server mode** (`dolt_mode: proxied-server`, experimental in
  upstream) runs a proxy and a child Dolt server for each workspace.

`bdhx` reads embedded workspaces with every command. Server-mode and proxied
workspaces work for most commands, and shared-server mode is refused. See
[Limits](limits.md#server-mode-proxied-and-shared-server-workspaces) for the
details. This page describes what matches upstream.

## How the mode and the database name are chosen

The name of the embedded database comes from `BEADS_DOLT_SERVER_DATABASE`,
or else from `dolt_database` in `.beads/metadata.json`, or else it is
`beads`. As in Dolt, the letter case of the name does not matter. A
redirecting workspace can also name the database (see
[Workspace discovery](workspace-discovery.md#redirects)).

Like upstream, `bdhx` matches the `dolt.mode` setting to `server`, and a
`dolt_mode` of `proxied-server` when it decides whether a server host implies
server mode, with Go's `strings.EqualFold`. So `ſerver` (with U+017F) selects
server mode in the setting, but not in `dolt_mode`.

The embedded database name must be an identifier: letters, digits and `_`,
and not a digit first. For any other name, such as `my-db` or `my.db`, every
command that reads the database stops before it reads or writes, as upstream
does. It prints upstream's error, `Error: failed to open database:
embeddeddolt: init schema: embeddeddolt: invalid database name: "my-db"`,
with upstream's hint when the name has a hyphen. With `--readonly` or the
`readonly` setting, the error is `Error: failed to open database:
embeddeddolt: invalid database name: "my-db"`, without the hint. The error is
text in every output mode. `where` prints no stored prefix then.
`DOLT_DBNAME_REPLACE` counts as in upstream: a directory such as `my-db` then
holds the database `my_db`.

## When the embedded database is missing

Upstream creates a missing embedded database, and `bdhx` does not write (see
[Limits](limits.md#embedded-store-layouts)). In the cases below, upstream
fails without a write, and `bdhx` prints the same error:

- With `--readonly` or the `readonly` setting, upstream does not create the
  database and prints its open error. This is also true when the workspace
  has no `.beads/embeddeddolt` directory, as for a `--db` path that names a
  `.beads` directory with only a redirect.
- A directory or a file in `.beads/embeddeddolt` has the name of the missing
  database. This also applies to a directory that a create left unfinished:
  one with Dolt's in-progress marker, or with a `.dolt` directory without its
  `repo_state.json`. Like upstream, `bdhx` then first prints Dolt's
  `level=warning msg="skipping in-progress database directory"` line for
  each marked directory, with the time of the run.

## Workspace without metadata.json

When the selected workspace has no `.beads/metadata.json` and no legacy
`.beads/config.json`, every command that reads the database uses the embedded
database `beads`, as upstream does. Before it opens the database, `bdhx`
prints upstream's `warning: no beads configuration found in <dir>; using
default database name "beads"` on stderr, also with `--json`. With `--db`,
`<dir>` is the directory that upstream derives from the path as given.
Upstream ignores `BEADS_DOLT_SERVER_DATABASE` in this case. `where`,
`version` and help pages print no warning.

When such a workspace also has no `.beads/embeddeddolt` or `.beads/dolt`
directory, no remote Dolt host is set, and no `--db` or `BEADS_DB` path names
the database, upstream finds no database. Then `bdhx` prints only upstream's
`Error: no beads database found` and its hint, as upstream does. This error
comes before the `--global` and `--database` checks, also when
`.beads/metadata.json` exists but the embedded store does not. A `--db` value
that names a database counts as no path.

## Data directory

A data directory that `BEADS_DOLT_DATA_DIR` or `dolt_data_dir` names lets
upstream find the database when `.beads/embeddeddolt` is missing, and `where`
prints it, as in upstream. Upstream's embedded store still opens
`.beads/embeddeddolt`. With `--readonly` or the `readonly` setting, `bdhx`
then prints upstream's `Error: failed to open database: embeddeddolt: no
embedded database at <dir>` error, after the check of the database name.

When a file takes the place of `.beads/embeddeddolt`, both of upstream's
opens fail before they write, and `bdhx` prints the same errors:
`embeddeddolt: open db: <dir>: is a file. need to specify a directory` in
strict read-only mode, and `embeddeddolt: creating data directory: mkdir
<dir>: not a directory`, before the check of the database name, otherwise.

## Schema version check

In an embedded workspace, every command that reads the database first
compares the highest version in the `schema_migrations` table with the
schema version of upstream v1.2.1, v65, as upstream does. `info --whats-new`
and `info --thanks` read nothing, but upstream opens the store first, so they
check too. Errors from the flag parser still come first, and this check comes
before the other checks of the command's arguments.

- When the database is ahead of the binary, the command stops with
  upstream's `schema version mismatch: ... Your bd binary is stale` message
  on stderr, or with that error as JSON on stderr under JSON output, and exit
  code 1.
- When the database is behind the binary, the command stops with upstream's
  `--readonly` error, `Error: failed to open database: schema version
  mismatch: ... the read-only open cannot migrate it ...`, in every output
  mode. Without strict read-only mode, upstream would migrate the database
  (see [Limits](limits.md#writes-and-migration)), unless it has a Dolt remote
  (see [Remote-migrate gate](#remote-migrate-gate)).
- A failed read of the version, for example when a value in the table is not
  a number, stops the command with the same `failed to open database`
  prefix. Without strict read-only mode, upstream's schema initialization
  names itself first, and so does `bdhx`: `Error: failed to open database:
  embeddeddolt: init schema: schema skew check: reading schema_migrations
  version: ...`. With `--readonly` or the `readonly` setting, the error
  starts with `schema skew check:`. A missing or empty table stops the
  command with upstream's `--readonly` error, `schema behind-drift check:
  ...`, also without `--readonly` (see
  [Limits](limits.md#writes-and-migration)).

`BD_IGNORE_SCHEMA_SKEW=1` or `--ignore-schema-skew` prints upstream's warning
instead, and the command reads the database. Like upstream, the command
prints the warning once, also when it reads the database more than once, as
`children`, `ready --gated`, `ready --explain`, `show` with more than one
issue ID, `show --thread`, `--refs` and `--children` do. `list --watch` and
`show --watch` print it once for the whole watch, not again at each refresh.
A few commands still print it again (see
[Limits](limits.md#commands-and-output)). `where` prints no stored prefix
when the check stops, as upstream does. `version` does not check.

### Remote-migrate gate

Without strict read-only mode, upstream does not refuse an embedded database
that is behind the binary. Before it migrates, its store open runs the
remote-migrate gate (#4259), and so does `bdhx`, without a write. The gate
applies only when the database has a Dolt remote and a recorded version.
`BD_IGNORE_SCHEMA_SKEW` does not change it.

- The gate reads only local data: the `dolt_remotes` table, the content
  hashes in `schema_migrations` at `HEAD` and at the cached ref
  `remotes/origin/<branch>`, the commit history and `dolt_status`. It never
  fetches.
- Like upstream, it stops with one of four messages: the default stop, adopt,
  adopt with a fast-forward that would not reach v65, or a fork when the two
  sides applied different content for a migration. The default stop names
  why the smart gate could not do better: no cached ref with content hashes,
  a cached remote behind this clone, a database below v43 at the same version
  as its cached remote, `BD_SMART_GATE=0`, or a `BD_SMART_GATE` value that is
  not a boolean. A `BD_ALLOW_REMOTE_MIGRATE` value that is not a boolean adds
  upstream's note.
- At a stop, the commands that upstream counts as reads by their command name
  (`readOnlyCommands`) print upstream's warning, `Warning: refusing to ...
  Read-only command: continuing on schema vN without migrating ...`, and read
  the database as it is. In `bdhx` these are `comments`, `blocked`, `graph`,
  `show`, `events tail`, `events export`, `dep list`, `label list`,
  `config list` and `config show`. The other reads print the warning and
  refuse (see [Limits](limits.md#writes-and-migration)).
- Every other command, such as `types`, `dep tree`, `info` or `status`, stops
  with the gate's message on stderr, or with its JSON error on stderr under
  JSON output (also with `BD_JSON_ENVELOPE=1`), and exit code 1.

A server-mode workspace never checks an embedded store that it still holds in
`.beads/embeddeddolt`, as upstream never opens that store. Its own check runs
in upstream's server open, which `bdhx` runs in its native code (see
[Limits](limits.md#server-mode-proxied-and-shared-server-workspaces)). When
the server does not answer, the command stops with upstream's connection
error, also with the escape hatch.

## Strict read-only mode

`--readonly` and the `readonly` setting select strict read-only mode. Like
upstream, `--readonly` also takes a value, such as `--readonly=true` or
`--readonly=0`, in every form that Go's `strconv.ParseBool` accepts.
`--readonly=false` turns the `readonly` setting and `BD_READONLY` off for
one command. Any other value stops the command with upstream's flag error.

Like upstream, a command that reads the database refuses strict read-only
mode in a proxied-server workspace, before it starts anything: `Error:
strict readonly is unavailable for dolt proxied-server backend; refusing to
open a store that cannot guarantee mutation-free access`.

## Workspace gate locks

Like upstream, every command that reads the database first takes the
workspace gates: `.beads.gate.lock` beside the `.beads` directory, and the
lock beside the data directory, such as `.beads/embeddeddolt.gate.lock` or
`.beads/dolt.gate.lock`. It tries a shared lock on each lock file once,
without a wait, in path order. While a maintenance command such as `bd init`,
`bd migrate` or `bd backup restore` holds one exclusively, the command stops
with upstream's `Error: a maintenance operation is running on this
workspace; retry when it completes: ...`, which names the lock and its
holder, and exit code 1. With `--json` the error is JSON on stdout.

When the `.beads` directory or the data directory is a symbolic link, for
example for `--db .beads` where `.beads` is a link, the command prints
upstream's `warning: workspace gate unavailable, continuing ungated: ... is a
symlink; ...` on stderr, unless `--quiet`, and reads without the locks.
`bdhx` opens each lock file read-only and holds its lock until it exits.
`where`, `version` and help pages take no lock.

## Server-mode workspace with an old embedded database

A server-mode workspace can still have a `.beads/embeddeddolt` directory
from before. Like upstream, `bdhx` does not read that directory. The commands
that support server mode read the workspace through the server, and the
others report that they are not available yet (see
[Limits](limits.md#server-mode-proxied-and-shared-server-workspaces)).

## Shared-server mode

Every command that reads the database refuses shared-server mode, and only
`version`, `where` and help pages run (see
[Limits](limits.md#server-mode-proxied-and-shared-server-workspaces)). Some
parts match upstream:

- In a shared-server workspace that has no database, upstream writes
  nothing, and the commands run as upstream does: they report
  `no beads database found` with the hint that names `bd doctor`, and
  `config get` of a key that needs no database prints its value.
- When `.beads/metadata.json` sets `dolt_mode` to `embedded`, upstream prints
  a three-line notice on stderr in shared-server mode, and so does `bdhx`,
  also before the refusals. Like upstream, it reads the metadata of the
  workspace that a `BEADS_DB`, `BD_DB` or `db` setting path selects.
- Like upstream, `where` in shared-server mode reads the issue prefix from
  the embedded database, unless `BEADS_DOLT_SHARED_SERVER` or `dolt_mode`
  makes the workspace a server workspace.
