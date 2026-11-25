# Configuration

This page describes how `bdhx` reads settings, the `config` commands, and the
warnings that upstream `bd` v1.2.1 prints about configuration. For the
differences that remain, see [Limits](limits.md). The
[Workspace discovery](workspace-discovery.md) page explains the words
"lookup", "setup" and "redirect" that this page uses.

## The .beads/.env file

Like upstream, `bdhx` loads the `.beads/.env` file of the selected workspace
before it reads any setting. A variable in that file counts as if it were set
in the environment, but a variable that the environment sets, even to an
empty value, keeps its value. This applies to the `BD_*` settings, such as
`BD_JSON` and `BD_LIST_LIMIT`, and to `BEADS_*` variables, such as
`BEADS_MAX_ROWS` and `BEADS_DOLT_SHARED_SERVER`.

Which file loads follows upstream:

- When no `-C`, `BEADS_DIR`, `BEADS_DB` or `BD_DB` selects the workspace,
  `BEADS_DIR`, `BEADS_DB` and `BD_DB` in the `.env` file of the workspace
  found from the current directory can select another workspace first. Then
  `bdhx` loads the `.env` file of the directory that upstream sets up first.
- For `where`, `version` and help pages, a `--db`, `BEADS_DB`, `BD_DB` or
  `db` setting path selects it, also when a workspace is found from the
  current directory.
- For a command that reads the database, a `--db` path or the `db` setting
  selects it, or else the workspace found, or else a `BEADS_DB` path.
- For a redirect, this is the file of the target. For a redirect chain, a
  command that reads the database also loads the file of the second target
  after it, as upstream's second setup does, and `where` loads it after its
  first setup; with `-C`, only the second target's file loads.

The file has the same format as upstream's `gotenv`: `KEY=value` or
`KEY: value` lines, an optional `export`, `#` comments, single or double
quotes and `$VAR` expansion. If one line is not valid, `bdhx` ignores the
full file, and prints no warning.

## Config commands

- `config get <key>`, `config list` and `config show` (also `--source`) read
  the database `config` table, `config.yaml`, `config.local.yaml`, the user
  `config.yaml`, `BD_*` variables and the defaults, in upstream's order.
  `config show` also
  lists the `.beads/metadata.json` fields, git's `beads.role` and
  `BEADS_MAX_ROWS`, and leaves out the `kv.` rows. Like upstream, these
  commands print secret values in full, without redaction.
- `config validate` checks the values in `config.yaml` and
  `.beads/metadata.json`, and the sync settings (`federation.remote`, its URL
  and allowed patterns, and `federation.sovereignty`). In an embedded
  workspace, upstream's remote check tries to connect to `127.0.0.1:0`;
  `bdhx` makes the same attempt and prints the same error. A `config.yaml` in
  the Dolt directory that Dolt can read sets the server port, to 3306 when
  the file names none.
- `config drift` checks the git hooks, the Dolt remote and the Dolt server
  state.

`config validate` and `config drift` also run with `--json`, and neither
writes. The `config` subcommands that write are not available yet (see
[Limits](limits.md)).

## Config file warnings

Like upstream, `bdhx` prints `Warning: failed to initialize config: <error>`
first when a `config.yaml` file that it loads at start does not parse. Then
it prints `Warning: failed to reinitialize config for selected beads dir:
<error>` each time upstream sets up the selected workspace and one of its
config files does not parse: `.beads/config.yaml`,
`.beads/config.local.yaml` or the user `config.yaml`. That is once for
`version`, the root help and `bd help <command>`, and twice for `where`. It
is twice for every command that reads the database, or once when a `--db` or
`BEADS_DB` path selects the database or upstream finds no database. A `--db`
value that names a database is not a path, so it gives two warnings. A
`--help` flag prints no warning.

The first setup then prints the shared-server notice. In a redirect chain,
the two setups take the two targets, and each setup reads the config files of
its own target. The notice then comes from the first setup whose target's
`.beads/metadata.json` pins `dolt_mode` embedded.

A `.beads/metadata.json` load error stops the first setup after its warning.
Upstream then runs the command with the settings that loaded, and so does
`bdhx`, for every command that reads the database too. `where` still prints
the issue prefix from the embedded database, as upstream does.

## Permission warning

Like upstream, each setup also prints `Warning: <dir> has permissions 0755
(recommended: 0700). Run: chmod 700 <dir>` on stderr when group or others
have a permission bit on the selected directory. An execute bit alone, as in
`0711`, also counts. The mode shows as four octal digits. The warning comes
after the config warning of the setup and before its shared-server notice or
`.beads/metadata.json` warning, also with `--json`. `bdhx` only reads the
mode; it does not change it.

`<dir>` is the directory as that setup names it:

- A `--db` path, and a `BEADS_DB`, `BD_DB` or `db` setting path for `where`,
  `version` and help pages, give it as the path gives it, for example `.`
  for `--db .beads` when `.beads` has no `metadata.json`.
- For a command that reads the database, a `BEADS_DB` path gives the
  absolute path.
- When `.beads` is a symbolic link, the second setup of such a command names
  the target, and so does the second setup of `where`, which then prints the
  target as the workspace path. With `-C`, both setups of `where`, `version`
  and help pages name the target.
- When a `db` setting selects the directory of `where`, its second setup
  names the absolute path.

## Deprecated dolt_server_port

Like upstream, a command that reads the database prints upstream's
three-line `Warning: dolt_server_port in metadata.json is deprecated ...` on
stderr, also with `--json`, when it takes the Dolt server port from
`dolt_server_port` in `.beads/metadata.json`. This happens when that port is
more than 0 and no earlier source gives a port: `BEADS_DOLT_SERVER_PORT` (any
number), a port more than 0 in `.beads/dolt-server.port`, a `config.yaml`
file in the Dolt directory, or a `dolt.port` setting more than 0. The warning
comes before the output and the errors of the command, and the exit code
does not change. `where`, `version` and help pages print no warning.
