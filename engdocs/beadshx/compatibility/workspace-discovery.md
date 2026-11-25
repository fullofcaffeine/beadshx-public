# Workspace discovery

Before a command runs, `bdhx` finds the Beads workspace: the `.beads`
directory that holds the configuration and the database. It follows the same
steps as upstream `bd` v1.2.1. This page describes those steps. For the
differences that remain, see
[Limits](limits.md#workspace-selection-and-redirects).

## Words used on this page

- A **lookup** is one search for the workspace. Upstream looks the workspace
  up several times during one command, and `bdhx` does the same.
- A **setup** is the step in which upstream prepares a selected directory. It
  reloads the config files of that directory, loads its `.beads/.env` file,
  and checks its `.beads/metadata.json` and its permissions. `version` and
  help pages run one setup. `where` and every command that reads the database
  run two, with the exceptions that
  [Configuration](configuration.md#config-file-warnings) lists.
- A **redirect** is a `.beads/redirect` file. It names another `.beads`
  directory, the target, that holds the real workspace.

## Selecting a workspace

`-C <dir>` makes `bdhx` look for the workspace from that directory, and
`BEADS_DIR` names the `.beads` directory. Without them, `bdhx` looks from the
current directory upward. A database path can also select the workspace:
`--db`, the `BEADS_DB` and `BD_DB` variables, and the `db` setting in a
`config.yaml` file.

Like upstream, a command that reads the database uses `BEADS_DB` only when no
`--db`, `-C` or `BEADS_DIR` is set and no workspace is found from the current
directory. These commands ignore `BD_DB`. For `where`, `version` and help
pages, `BEADS_DB`, or else `BD_DB`, comes before `-C`, `BEADS_DIR` and the
current directory; only `--db` comes first. The path, absolute or relative to
the current directory, can name the workspace directory (such as `.beads`),
its `embeddeddolt` directory, or a missing file in a `.beads` directory, such
as a legacy `beads.db`. `bdhx` then reads that workspace with its
`config.yaml` and `.env` file. `info` prints the database path that upstream
takes from `BEADS_DB`: the absolute path with symbolic links resolved, or the
database directory inside it. For a missing file, that is the file.

On macOS, a path typed in another letter case, such as
`DB/.BEADS/embeddeddolt` or `DB/.BEADS/beads.db`, selects the same workspace,
as in upstream. Upstream and `bdhx` take the letter case of each name from
the file system there, and also when they derive the directory that a path
selects, so such a path prints as stored. `where` prints it so for a `--db`
path too. For a missing file the names keep the case as typed, as in
upstream.

Like upstream, `bdhx` ignores the `db` setting when `--db`, `-C`,
`BEADS_DB`, `BD_DB` or `BEADS_DIR` selects the workspace. Otherwise `where`
reports the workspace that the `db` setting selects. This can be another
workspace than the one found from the current directory. The path selects the
directory that upstream derives from it: a parent `.beads` directory with
`metadata.json`, a workspace that claims the path, or else the first `.beads`
directory above the path's directory. `where` prints the absolute path of the
workspace there, its prefix and its database. When that directory is not a
workspace, `where` reports the workspace found from the current directory.
`where`, `version` and every command that reads the database take the `json`
setting from the config of the directory that the path selects, also when the
`db` setting comes from the user `config.yaml` and no workspace is found from
the current directory. Every command that reads the database refuses a `db`
setting that names a database (see
[Limits](limits.md#server-mode-proxied-and-shared-server-workspaces)).

For a `--db` path that no workspace claims, `bdhx` takes the first `.beads`
directory beside the path's directory or above it, as upstream does, or else
the path's directory. `where --db sub/data/x` prints `sub/.beads` when that
directory exists.

## Redirects

Like upstream, `bdhx` follows a `.beads/redirect` file each time that one of
upstream's steps looks up the workspace, and it prints upstream's warnings at
each of these lookups. The warnings are for a target that does not exist, for
a redirect chain, and, when `BD_DEBUG_ROUTING` is set, the routing lines. The
warning for a target without a database prints once for each directory. So a
broken redirect prints its warning as many times as upstream does, for
example 9 times for `where` and 11 times for `count`.

Like upstream, `bdhx` opens the database that the redirecting workspace names
in its `dolt_database`, instead of the target's. Without a `--db` path, that
workspace is the `.beads` directory of the Git repository root, also when
`-C` or `BEADS_DIR` selects another workspace. Outside a repository it is
`BEADS_DIR` or the `-C` workspace, and otherwise the first `.beads` directory
above the current directory.

## Redirect chains

When the target of a redirect has its own redirect to another workspace,
upstream warns that it ignores that chain, and its first lookup finds the
first target. Its later lookups start from the first target and follow that
target's redirect. Like upstream, every command that reads the database then
reads the database and the `config.yaml` of the second target, and `info`
prints the path of that database. Such a command also takes the `json`
setting from that `config.yaml`, and its settings from the second target's
`.env` file when the first target's file does not set them. The database
name comes from the redirecting directory, as for one redirect, or else from
the `dolt_database` of the first target, or else from
`BEADS_DOLT_SERVER_DATABASE` in the second target's `.env` file.

`where` reports the workspace that its last lookup finds from the second
target: that target, or the target of its own redirect. It prints the
database in that workspace, also when that workspace redirects again. The
origin line names the directory with the redirect, as upstream does. `where`
takes its `json` setting from the first target, and its second setup prints
the shared-server notice when the second target's `.env` file turns
shared-server mode on.

With `-C`, the first lookup already starts from the first target, so every
command takes its settings from the second target. A `--db` path selects the
first target itself. When the second target's `.beads/metadata.json` does not
decode, upstream finds no database there, and `bdhx` prints the same
`no beads database found` error; with `-C` both print the load warning and
error, and the second setup of `where` prints the warning.

## The metadata.json file

Like upstream, `bdhx` reads the selected workspace's `.beads/metadata.json`
(or, when it does not exist, a legacy `.beads/config.json`) before any
command runs. For `where`, `version` and help pages, that is the directory
that a `--db`, `BEADS_DB`, `BD_DB` or `db` setting path selects, as upstream
derives it. If the file cannot be read or does not decode, `bdhx` prints
upstream's `warning: load ...` line, which names the directory as the path
gives it. Then `where` and every command that reads the database fail with
`Error: loading config: ...` and exit code 1, also with `--json`. The error
texts are Go's own `encoding/json` errors, for example for a number where
upstream expects a string, or for a syntax error. `version`, the root help
and `bd help <command>` print only the warning, and a `--help` flag prints no
warning. Unknown keys, `null` values and repeated keys (the last one counts)
are accepted, as in upstream.

[Storage modes](storage-modes.md) describes how the file selects the storage
mode and the database name.

## Older workspace layouts

Like upstream, `bdhx` refuses older workspace layouts before it opens
anything. After the setup of the workspace, `where` and every command that
reads the database print upstream's `Error: <reason> detected; explicit
migration is required ...` and exit with code 1, also with `--json`.
`version` and help pages run as usual. The reasons are these:

- `historical SQLite workspace`: the workspace has no embedded repository.
  Its `.beads/metadata.json` sets no `dolt_mode` and no `dolt_database`, and
  the file that `sqlite_path`, `database` or else `beads.db` names is not
  empty. A workspace without `.beads/metadata.json` counts when it holds only
  one SQLite file, with its `-wal` and `-shm` files, `issues.jsonl` and
  `embeddeddolt`.
- `legacy Dolt workspace`: an embedded workspace has a `.beads/dolt`
  directory (not a symbolic link) and no embedded repository. When
  `.beads/.local_version` names a `0.x.y` release, the reason adds `from bd
  <version>`. In shared-server mode only a 0.55 to 0.62 release counts.
- `legacy Dolt server workspace`: `dolt_mode` is `server`, and
  `.beads/.local_version` names a 0.55 to 0.62 release, or the workspace has
  `.beads/dolt` and no version from 1.0 or later.

A `backend` other than `dolt` in `.beads/metadata.json` stops these commands
with upstream's error for a removed or an unknown backend. Like upstream, this
guard also reads a legacy `.beads/config.json`, so these errors come before
the refusal of a legacy-only workspace (see
[Limits](limits.md#writes-and-migration)).

Like upstream, a command that reads the database checks the second target of
a redirect chain in the same way, after the setup of that target. When no
workspace is found, `where` and every command that reads the database check
the `.beads` directory that `BEADS_DIR` names, or else each `.beads`
directory from the current directory up to the repository root, also before a
`BEADS_DB` path selects the workspace. Outside a Git repository only the
current directory's `.beads` directory counts, as in upstream. So a `.beads`
directory that holds only a SQLite `vc.db` or a backup database stops them
with the `historical SQLite workspace` error. A legacy `.beads/config.json`
there that does not decode stops them with upstream's `Error: loading config:
...`, without the warning.
