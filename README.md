# BeadsHX

BeadsHX is an experimental Haxe-to-Go port of
[Beads](https://github.com/gastownhall/beads). The current compatibility target
is Beads v1.2.1.

BeadsHX is not a stable replacement for `bd`. The port is incomplete, and no
BeadsHX release is available. Haxe owns new application behavior under
`src/beadshx/`. The project uses the upstream `bd` binary only as a named test
oracle. A BeadsHX release build never delegates commands to that binary.

[![BeadsHX CI](https://github.com/fullofcaffeine/beadshx/actions/workflows/beadshx-bootstrap.yml/badge.svg)](https://github.com/fullofcaffeine/beadshx/actions/workflows/beadshx-bootstrap.yml)
[![License](https://img.shields.io/github/license/fullofcaffeine/beadshx)](LICENSE)

Read [the port specification](beadshx-complete-port-prd.md) and
[the source index](engdocs/beadshx/program/source-index.md) for the current
scope and evidence. Use upstream Beads for production work.

## What BeadsHX runs today

`bdhx` implements these read-only commands in authored Haxe. Parity tests run
each command with `bdhx` and with upstream `bd` v1.2.1 on the same disposable
workspaces, and require the same stdout, stderr and exit code:

- **Workspace and status:** `version`, `where`, `info`, `ping`, `status`
  (also `stats`).
- **Issue queries:** `list`, `show`, `children`, `search`, `query`, `count`,
  `ready`, `stale`, `orphans`, `comments`, `label list`, `label list-all`,
  `history` (also `--events`).
- **Dependencies and graphs:** `dep list`, `dep tree`, `dep cycles`,
  `blocked`, `graph check`, and `graph` for one issue or `--all`, in every
  view (default, `--compact`, `--open`, `--box`, `--dot`, `--html`,
  `--json`).
- **Reference lists:** `types` (also `--sections`), `statuses`. They read
  custom types and statuses from the database, the same `config.yaml` files
  as `config get`, and `BD_TYPES_CUSTOM` and `BD_STATUS_CUSTOM`, in upstream's
  order.
- **Events journal:** `events`, `events tail` (also `--since`, `--limit`),
  `events export` (also `--limit`).
- **Configuration:** `config get <key>`, `config list` and `config show`
  (also `--source`). They read the database `config` table, `config.yaml`,
  `config.local.yaml`, the user `config.yaml`, `BD_*` variables and the
  defaults in upstream's order. `config show` also lists the
  `.beads/metadata.json` fields, git's `beads.role` and `BEADS_MAX_ROWS`, and
  leaves out the `kv.` rows. Like upstream, they print secret values in full,
  without redaction.
- **Configuration checks:** `config validate` checks the values in
  `config.yaml` and `.beads/metadata.json`, and the sync settings
  (`federation.remote`, its URL and allowed patterns, and
  `federation.sovereignty`). `config drift` checks the git hooks, the Dolt
  remote and the Dolt server state. Both also run with `--json`, and neither
  writes.

Like upstream, every command above prints JSON, exactly as with `--json`,
when `json: true` is set in `config.yaml`, `config.local.yaml` or the user
`config.yaml`, or when `BD_JSON` is true. `BD_JSON` is true for `1`, `t`, `T`,
`true`, `True` and `TRUE`, and false for any other value. An empty `BD_JSON`
is ignored. `BD_JSON` outranks the files, and `--json`, `--json=false` and
`--format` outrank both. The `--format` flag of `list` and `dep tree` does not
count, but `--format json` always selects JSON. Help pages, `--version` and
flag errors stay text.

Like upstream, `bdhx` loads the `.beads/.env` file of the selected workspace
before it reads any setting. A variable in that file counts as if it were set
in the environment, but a variable that the environment sets, even to an empty
value, keeps its value. This applies to the `BD_*` settings, such as `BD_JSON`
and `BD_LIST_LIMIT`, and to `BEADS_*` variables, such as `BEADS_MAX_ROWS` and
`BEADS_DOLT_SHARED_SERVER`. When no `-C`, `BEADS_DIR`, `BEADS_DB` or `BD_DB`
selects the workspace, `BEADS_DIR`, `BEADS_DB` and `BD_DB` in the `.env` file
of the workspace found from the current directory can select another
workspace first. Then `bdhx` loads the `.env` file of the selected workspace;
for a redirect, this is the file of the target. The file has the same format
as upstream's `gotenv`: `KEY=value` or `KEY: value` lines, an optional
`export`, `#` comments, single or double quotes and `$VAR` expansion. If one
line is not valid, `bdhx` ignores the full file, and prints no warning.

Like upstream, a command that reads the database uses `BEADS_DB` only when no
`--db`, `-C` or `BEADS_DIR` is set and no workspace is found from the current
directory. These commands ignore `BD_DB`. For `where`, `BEADS_DB`, or else
`BD_DB`, comes before `-C`, `BEADS_DIR` and the current directory; only `--db`
comes first. The path, absolute or relative to the current directory, can name
the workspace directory (such as `.beads`), its `embeddeddolt` directory, or a
missing file in a `.beads` directory, such as a legacy `beads.db`. `bdhx` then
reads that workspace with its `config.yaml` and `.env` file. For such a missing
file, `info` prints that file as the database path, as upstream does.

Like upstream, `bdhx` reads the selected workspace's `.beads/metadata.json`
(or, when it does not exist, a legacy `.beads/config.json`) before any
command runs. If the file cannot be read or does not decode, `bdhx` prints
upstream's `warning: load ...` line. Then `where` and every command that reads
the database fail with `Error: loading config: ...` and exit code 1, also with
`--json`. The error texts are Go's own `encoding/json` errors, for example
for a number where upstream expects a string, or for a syntax error. `version`,
the root help and `bd help <command>` print only the warning, and a `--help`
flag prints no warning. Unknown keys, `null` values and repeated keys (the
last one counts) are accepted, as in upstream. The name of the embedded
database comes from `BEADS_DOLT_SERVER_DATABASE`, or else from
`dolt_database`, or else it is `beads`. As in Dolt, the letter case of the
name does not matter.

When the selected workspace has no `.beads/metadata.json` and no legacy
`.beads/config.json`, every command that reads the database uses the embedded
database `beads`, as upstream does. Before it opens the database, `bdhx` prints
upstream's `warning: no beads configuration found in <dir>; using default
database name "beads"` on stderr, also with `--json`. With `--db`, `<dir>` is
the directory that upstream derives from the path as given. Upstream ignores
`BEADS_DOLT_SERVER_DATABASE` in this case. `where`, `version` and help pages
print no warning.

Like upstream, a command that reads the database prints upstream's three-line
`Warning: dolt_server_port in metadata.json is deprecated ...` on stderr, also
with `--json`, when it takes the Dolt server port from `dolt_server_port` in
`.beads/metadata.json`. This happens when that port is more than 0 and no
earlier source gives a port: `BEADS_DOLT_SERVER_PORT` (any number), a port
more than 0 in `.beads/dolt-server.port`, a `config.yaml` file in the Dolt
directory, or a `dolt.port` setting more than 0. The warning comes before the
output and the errors of the command, and the exit code does not change.
`where`, `version` and help pages print no warning.

Like upstream, `bdhx` prints `Warning: failed to initialize config: <error>`
first when a `config.yaml` file that it loads at start does not parse. Then it
prints `Warning: failed to reinitialize config for selected beads dir:
<error>` each time upstream sets up the selected workspace and one of its
config files does not parse: `.beads/config.yaml`, `.beads/config.local.yaml`
or the user `config.yaml`. That is once for `version`, the root help and
`bd help <command>`, and twice for `where`. It is twice for every command that
reads the database, or once when a `--db` or `BEADS_DB` path selects the
database or upstream finds no database. A `--help` flag prints no warning.
The first setup then prints the shared-server notice. A
`.beads/metadata.json` load error stops the first setup after its warning.
Upstream then runs the command with the settings that loaded, and so does
`bdhx`, for every command that reads the database too. `where` still prints
the issue prefix from the embedded database, as upstream does.

Each command takes the issue prefix from the same source as upstream. `where`
prints `issue-prefix` from `.beads/config.yaml`, or else `issue_prefix` from
that file, or else the `issue_prefix` stored in the database. When an issue ID
does not match exactly, `show` and the other commands that take an issue ID
add and remove the stored `issue_prefix`, also when `config.yaml` names
another prefix. `orphans` takes the `issue-prefix` setting, which
`BD_ISSUE_PREFIX` can set, then the stored prefix, then `bd`. Workspace
discovery reads only `config.yaml`. So commands that do not need the stored
prefix, such as `version` and `count`, do not open the database to read it,
and an exact issue ID does not read it either.

Like upstream, `list`, `ready`, `count`, `query` and `search` check most of
their arguments only after the warnings above and after the database opens. A
`.beads/metadata.json` load error, a missing database or a store error thus
comes first. Errors from the flag parser, such as an unknown flag or a value
that is not a number, still come before all of them. So does the error for a
positional argument to `list`, which takes none. The checks come in
upstream's order:

- `list`: `--skip-labels` with a label filter, `--priority`, `--priority-min`,
  `--priority-max`, `--pinned` with `--no-pinned`, `--parent` with
  `--no-parent`, `--mol-type`, `--wisp-type`, the date filters,
  `--metadata-field`, `--has-metadata-key`, the `--brief` rules, `--deps`,
  `--sort`, `--offset`, and then a negative `--max-rows`.
- `ready`: the `--brief` rules first. Outside a proxied workspace, a positive
  `--offset` fails next, and `--gated`, `--mol` and `--explain` then run
  without the other checks. The default view checks `--mol-type` and the
  `--claim` rules, then a negative `--max-rows`, the metadata filters and
  `--sort`. In a proxied workspace, `ready` reads `--max-rows` and
  `BEADS_MAX_ROWS` after the `--brief` rules. It refuses a cap more than 0
  unless `--claim` is set, then checks a negative `--offset` and the rest.
- `count`: more than one `--by-*` flag, then the date filters.
- `query`: a negative `--offset`, after the check for a missing expression.
- `search`: the check for a missing query, then `--status`, the date filters,
  `--priority-min`, `--priority-max`, `--metadata-field` and
  `--has-metadata-key`. In a proxied workspace, `--status` comes last, and
  the other checks print a JSON error with `--json`. `search` accepts any
  `--sort` value. With a value that it does not know, it keeps the order of
  the database.

`list` and `ready` print the `BEADS_MAX_ROWS` warning where they read
`--max-rows`, so a check that fails before that point prints no warning.
`ready --claim` fails after all of these checks with upstream's
`--readonly` error. `bdhx` prints this error also without `--readonly`,
because it does not write.

In an embedded workspace, every command that reads the database first
compares the highest version in the `schema_migrations` table with the
version of the binary, v65, as upstream does. Errors from the flag parser
still come first, and this check comes before the other checks of the
command's arguments. When the database is ahead of the binary, the command
stops with upstream's
`schema version mismatch: ... Your bd binary is stale` message on stderr, or
with that error as JSON on stderr under JSON output, and exit code 1. When the
database is behind the binary, the command stops with upstream's `--readonly`
error, `Error: failed to open database: schema version mismatch: ... the
read-only open cannot migrate it ...`, in every output mode. A failed read of
the table stops the command with the same `failed to open database` prefix.
`BD_IGNORE_SCHEMA_SKEW=1` or `--ignore-schema-skew` prints upstream's warning
instead, and the command reads the database. `where` prints no stored prefix
when the check stops, as upstream does. `version` does not check.

**BeadsHX extension: `bdhx snapshot`.** This command prints a read-only
snapshot of every issue in an embedded workspace. Upstream `bd` v1.2.1 has no
such command, so this is a recorded extension
([engdocs/beadshx/program/exceptions.md](engdocs/beadshx/program/exceptions.md)).
The root help does not list it; `bdhx snapshot --help` describes it. It takes
only the global selection inputs (`-C`, `--db`, `BEADS_DIR`, `BEADS_DB`).

The artifact uses schema `beadshx-task-snapshot/1`. It is JSON Lines in
UTF-8, with a line feed after every line:

- Line 1 is a header. Its keys are in byte order: `_dolt_branch`
  (`active_branch()`), `_dolt_commit` (`DOLT_HASHOF('HEAD')`), `_dolt_state`
  (`DOLT_HASHOF_DB()`), `_project_id` (left out when the database has none),
  `_records` (the number of issue lines), `_schema`, `_scope` (`all-issues`)
  and `_sort` (`id-bytewise`).
- Every other line is the line that upstream `bd export --all` prints for one
  issue, including wisps, templates, gates and other infrastructure types,
  sorted by issue ID in byte order. Memories and config rows are not included.

The command reads everything in one Dolt read transaction, which it rolls
back. It writes no file and no database row, and stdout stays empty until the
whole snapshot is read. The same `_dolt_state` gives the same bytes in every
directory, time zone and locale. A change to a wisp, which Dolt never commits,
also moves `_dolt_state`. The artifact holds no config row, remote URL,
credential, environment value, path, actor, host name, time of capture or
`bdhx` version. Errors go to stderr and exit with code 1, also with `--json`.

Choose the file yourself, for example in a git-ignored build directory such as
`build/caf/`: `bdhx snapshot > build/caf/tasks.jsonl`. Never write it under
`.beads/`, where upstream keeps its own `issues.jsonl`. The artifact holds
the task text, so do not commit it to a public repository. Upstream
`bd import` skips the header line, so `bd import <artifact>` restores the
issues into a fresh workspace. Upstream import drops a dependency between a
wisp and a durable issue.

Limits:

- `bdhx` does not write yet. Commands that create, update, close or sync
  issues are not ported.
- Without `--readonly`, upstream migrates a database whose schema is behind
  the binary, and then runs the command. `bdhx` never migrates. It stops with
  upstream's `--readonly` error and leaves the database unchanged. Migration
  parity (M12) removes this limit.
- With `BD_IGNORE_SCHEMA_SKEW=1` on a database that is ahead of or behind the
  binary, a command that opens the native store more than once, such as `show`
  with two IDs or `children`, prints the warning once for each open. Upstream
  prints it once.
- `dep tree`, `dep cycles`, `blocked`, `comments`, `history`, `graph`,
  `types`, `statuses`, `events tail`, `events export`, `config get`,
  `config list`, `config show`, `config validate` and `config drift` read
  embedded workspaces only. In a server-mode or proxied workspace they report
  that they are not available yet. If the server cannot be reached, they print
  the same store error as upstream.
  `types --sections` prints its fixed list in every mode.
- `label list-all` reports that it is not available yet in a proxied
  workspace.
- `snapshot` reads embedded workspaces only. In a server-mode, shared-server
  or proxied workspace and with `--global`, it reports that it is not
  available yet, before it opens anything.
- `events tail --follow` and `events prune` report that they are not
  available yet.
- `config set`, `set-many`, `unset` and `apply` report that they are not
  available yet. `config get` of a user-global key
  (`metrics.*`, `node_id`) and `config show` report that they are not
  available yet when the user `config.yaml` exists.
- `config show` reports that it is not available yet in a workspace that has
  no database (upstream creates the embedded database there).
- When `--db` selects a workspace whose `.beads/metadata.json` cannot be read
  or does not decode, `where` and every command that reads the database
  report that they are not available yet. For `where`, `BEADS_DB`, `BD_DB`
  and the `db` setting count too. Upstream then prints the path as given, or
  opens or creates a database in another directory. In these cases `version`
  and help pages print no warning.
- When `BEADS_DB` (or, for `where`, `BD_DB`) selects with another path,
  `where` and every command that reads the database report that they are not
  available yet. This applies to a missing path outside a `.beads` directory,
  a directory that is not a workspace, a workspace without an embedded
  database, a server-mode, proxied or redirected workspace, a path deeper in a
  `.beads` directory and a path with a trailing slash. For most of these paths
  upstream creates an embedded database. `version` and help pages still run.
- In a workspace that has a legacy `.beads/config.json` and no
  `.beads/metadata.json`, `where` and every command that reads the database
  stop with `Error: <command> is not available yet when the workspace has
  only a legacy config.json in this build`, also when `-C`, a `--db` path or a
  redirect selects the workspace. Upstream rewrites the file as
  `.beads/metadata.json` and runs them. `bdhx` leaves the file in place.
  `version`, help pages and unknown commands run as upstream does. With a
  `--db` path, upstream also rewrites the file for `version` and
  `bd help <command>`; `bdhx` prints the same output and writes nothing.
  Migration parity (M12) removes this limit.
- In an embedded workspace, every command that reads the database reports
  that it is not available yet when the embedded store has no database with
  the name that `.beads/metadata.json` selects. This applies to `null`, `{}`
  and an empty `dolt_database`, which select `beads`, and to every other
  missing name, also from `BEADS_DOLT_SERVER_DATABASE`. Upstream creates that
  database. With `--readonly` or the `readonly` setting, upstream does not
  create it, and `bdhx` prints the same open error. A redirect can make
  upstream open the database that the redirecting workspace names instead of
  the target's; `bdhx` then reports that it is not available yet. `where`,
  `version` and help pages still run.
- In a workspace without `.beads/metadata.json`, every command that reads the
  database prints upstream's warning and then reports that it is not
  available yet when the embedded store has no `beads` database. Upstream
  creates that database. With `--readonly` or the `readonly` setting,
  `bdhx` prints the same open error as upstream. `bdhx` also reports that the
  command is not available yet when `BEADS_DOLT_SERVER_DATABASE` names another
  database, when `BEADS_DOLT_SERVER_MODE=1` or the `dolt.mode` setting selects
  server mode, and when upstream takes a `.beads` directory above the
  directory of a `--db` path. Upstream opens `beads` in these cases (for
  `--db`, in that other directory), but the native store open would not.
- Every command above that reads the database reports that it is not
  available yet in shared-server mode and when the `db` setting names a
  database. Only `version`, `where` and help pages still run. In these cases
  upstream connects to the shared server, which creates
  `~/.beads/shared-server/dolt` and a file under `TMPDIR`, or it opens or
  creates the database at that path. `bdhx` refuses before it opens anything,
  and writes nothing. Shared-server mode comes from `dolt.shared-server` in
  `config.yaml`, `config.local.yaml` or the user `config.yaml`, or from
  `BEADS_DOLT_SHARED_SERVER` or `BD_DOLT_SHARED_SERVER`. Like upstream, `bdhx`
  ignores the `db` setting when `--db`, `-C`, `BEADS_DB`, `BD_DB` or
  `BEADS_DIR` selects the workspace. In a shared-server workspace that has no
  database, upstream writes nothing, and these commands run as upstream does:
  they report `no beads database found` with the hint that names `bd doctor`,
  and `config get` of a key that needs no database prints its value.
  `config show`, `config validate` and `config drift` still report that they
  are not available yet there, and so does every command when a `--db` path
  names the database. When `.beads/metadata.json` sets `dolt_mode` to
  `embedded`, upstream prints a three-line notice on stderr in shared-server
  mode, and so does `bdhx`, also before these refusals. Like upstream, it reads
  the metadata of the workspace that a `BEADS_DB`, `BD_DB` or `db` setting path
  selects. `bdhx` does not print the notice before it refuses a `BEADS_DB` path
  that it cannot follow for a command that reads the database.
  Like upstream, `where` in shared-server mode reads the issue prefix from the
  embedded database, unless `BEADS_DOLT_SHARED_SERVER` or `dolt_mode` makes the
  workspace a server workspace.
- `config validate` and `config drift` also report that they are not
  available yet with `--global`, when `.beads/metadata.json` names a backend
  other than Dolt, and when a Dolt server host, port or
  socket, `BEADS_DOLT_DATA_DIR` or a central server config is set. In these
  cases upstream connects to a server or creates a database. `config validate`
  also reports this when the workspace directory is not named `.beads` or
  holds its own `redirect` file.
  In an embedded workspace upstream's remote check tries to connect to
  `127.0.0.1:0`; `bdhx` makes the same attempt and prints the same error.
- When the Dolt directory has a `config.yaml` file, `bdhx` takes it as the
  source of the server port and prints no `dolt_server_port` warning.
  Upstream also prints the warning when Dolt cannot parse that file, or when
  the file sets the port to 0 or less.
- When an issue ID does not match exactly and the database stores no
  `issue_prefix`, `bdhx` uses the prefix from `config.yaml` instead. Upstream
  uses `bd` and then guesses the prefix of each matching issue. With neither
  prefix, `bdhx` does not find a prefixed issue from its hash alone. In a
  server-mode or proxied workspace, `bdhx` does not read the stored prefix
  for this lookup and uses the `config.yaml` prefix; upstream reads the stored
  one.
- In a `.beads/.env` file that is not valid UTF-8, `bdhx` changes each
  invalid byte to U+FFFD. Upstream keeps the byte.
- Where upstream output order is random (Go map order), the parity tests
  compare the stable part, and `bdhx` prints one fixed order.

Run the parity suite with `make beadshx-parity`; it lives in
[scripts/beadshx/test-parity-smoke.sh](scripts/beadshx/test-parity-smoke.sh).

The handwritten Go islands under `internal/beadshx/` may only shrink.
`make beadshx-test-native-pressure` fails when their non-test lines or imports
grow above
[compatibility/native-islands/baseline.json](compatibility/native-islands/baseline.json),
or when an island calls `configfile.Load` or opens a writable store. After a
deletion, it fails until `go run ./scripts/beadshx/island-guard --update`
lowers the baseline in the same commit.

## Upstream Beads overview

The text below describes the upstream Beads product. BeadsHX keeps this
documentation because upstream behavior is the compatibility authority.

# bd - Beads

**Distributed graph issue tracker for AI agents, powered by [Dolt](https://github.com/dolthub/dolt).**

**Platforms:** macOS, Linux, Windows, FreeBSD

[![Go Report Card](https://goreportcard.com/badge/github.com/steveyegge/beads)](https://goreportcard.com/report/github.com/steveyegge/beads)
[![Upstream release](https://img.shields.io/github/v/release/gastownhall/beads)](https://github.com/gastownhall/beads/releases)
[![npm version](https://img.shields.io/npm/v/@beads/bd)](https://www.npmjs.com/package/@beads/bd)
[![PyPI](https://img.shields.io/pypi/v/beads-mcp)](https://pypi.org/project/beads-mcp/)

**Docs:** https://beads.gascity.com/

Beads provides a persistent, structured memory for coding agents. It replaces messy markdown plans with a dependency-aware graph, allowing agents to handle long-horizon tasks without losing context.

```mermaid
flowchart LR
    create["bd create<br/>new bead"] --> depgraph["dependency<br/>graph"]
    depgraph --> ready["bd ready<br/>claimable work"]
    ready --> claim["bd update --claim<br/>agent takes it"]
    claim --> close["bd close<br/>work done"]
    close -->|blockers released| ready
    depgraph <-->|"bd dolt push / pull"| remote[("other machines<br/>and agents")]
```

## ⚡ Upstream Beads Quick Start

```bash
# Install beads CLI (system-wide - don't clone this repo into your project)
curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash

# Initialize in YOUR project
cd your-project
bd init

# Optional: refresh or install richer instructions for your agent
bd setup codex    # Codex CLI - installs skill, AGENTS.md guidance, and hooks
bd setup claude   # Claude Code - installs hooks/settings
bd setup factory  # Factory.ai Droid - creates/updates AGENTS.md
```

**Note:** Beads is a CLI tool you install once and use everywhere. You don't need to clone this repository into your project.

`bd init` creates or updates `AGENTS.md` by default so agents can discover the beads workflow, and also installs project Claude/Codex integrations unless you pass `--skip-agents` or `--stealth`. Use `bd setup --list` to see supported integrations, including `bd setup codex`, `bd setup factory`, `bd setup claude`, `bd setup mux`, `bd setup cursor`, and more. See [Agent and IDE setup](docs/getting-started/ide-setup.md).

Manual copy-paste is only for unsupported agents, existing projects where you cannot rerun `bd init`/`bd setup`, or custom instruction files. In those cases, run `bd onboard` and paste the printed snippet into the file your agent reads.

If your agent is not covered by `bd setup`, add this minimal `AGENTS.md` section:

```markdown
This project uses bd (beads) for issue tracking.

- Run `bd prime` for workflow context and command guidance.
- Use `bd ready`, `bd show <id>`, `bd update <id> --claim`, and `bd close <id>`.
- Use `bd remember "insight"` for persistent project memory; do not create MEMORY.md files.
- Do not use markdown TODO lists for task tracking.
```

## 🛠 Features

* **[Dolt](https://github.com/dolthub/dolt)-Powered:** Version-controlled SQL database with cell-level merge, native branching, and built-in sync via Dolt remotes.
* **Agent-Optimized:** JSON output, dependency tracking, and auto-ready task detection.
* **Zero Conflict:** Hash-based IDs (`bd-a1b2`) prevent merge collisions in multi-agent/multi-branch workflows.
* **Compaction:** Semantic "memory decay" summarizes old closed tasks to save context window.
* **Messaging:** Message issue type with threading (`--thread`), ephemeral lifecycle, and mail delegation.
* **Graph Links:** `relates-to`, `duplicates`, `supersedes`, and `replies-to` for knowledge graphs.

## 📖 Essential Commands

| Command | Action |
| --- | --- |
| `bd ready` | List tasks with no open blockers. |
| `bd create "Title" -p 0` | Create a P0 task. |
| `bd update <id> --claim` | Atomically claim a task (sets assignee + in_progress). |
| `bd dep add <child> <parent>` | Link tasks (blocks, related, parent-child). |
| `bd show <id>` | View task details and audit trail. |
| `bd prime` | Print agent workflow context and persistent memories. |
| `bd remember "insight"` | Store project memory that `bd prime` injects later. |

## 🔗 Hierarchy & Workflow

Beads supports hierarchical IDs for epics:

* `bd-a3f8` (Epic)
* `bd-a3f8.1` (Task)
* `bd-a3f8.1.1` (Sub-task)

**Stealth Mode:** Run `bd init --stealth` to use Beads locally without committing files to the main repo. Perfect for personal use on shared projects. See [Git-Free Usage](#-git-free-usage) below.

**Contributor vs Maintainer:** When working on open-source projects:

* **Contributors** (forked repos): Run `bd init --contributor` to route planning issues to a separate repo (e.g., `~/.beads-planning`). Keeps experimental work out of PRs.
* **Maintainers** (write access): Beads auto-detects maintainer role via SSH URLs or HTTPS with credentials. Only need `git config beads.role maintainer` if using GitHub HTTPS without credentials but you have write access.

## 📦 Installation

```bash
brew install beads           # macOS / Linux (recommended)
npm install -g @beads/bd     # Node.js users
```

**Other methods:** [install script](docs/getting-started/installation.md#quick-install-script-all-platforms) | [go install](docs/getting-started/installation.md#a-note-on-go-install-capability) | [from source](docs/getting-started/installation.md#build-dependencies-contributors-only) | [Windows](docs/getting-started/installation.md#windows-11) | [Arch AUR](docs/getting-started/installation.md#linux)

**Requirements:** macOS, Linux, Windows, or FreeBSD. See [docs/getting-started/installation.md](docs/getting-started/installation.md) for complete installation guide.

**Upgrading?** Replacing the binary is not always the whole story. Short
version: sync remote-backed databases with your current `bd`, back up with
`bd export --all`, upgrade the binary, then run `bd info --whats-new`,
`bd hooks install`, and `bd version`. If the upgrade crosses a schema
migration on a remote-backed database, exactly one designated clone runs
`bd migrate` and `bd dolt push`; other clones install the new binary
and run `bd bootstrap`. See the full
[upgrade guide](https://beads.gascity.com/getting-started/upgrading)
or [docs/getting-started/installation.md](docs/getting-started/installation.md#updating-bd).

### Security And Verification

Before trusting any downloaded binary, verify its checksum against the release `checksums.txt`.

The install scripts verify release checksums before install. For manual installs, do this verification yourself before first run.

On macOS, `scripts/install.sh` preserves the downloaded signature by default. Local ad-hoc re-signing is explicit opt-in via `BEADS_INSTALL_RESIGN_MACOS=1`.

See [docs/reference/antivirus.md](docs/reference/antivirus.md) for Windows AV false-positive guidance and verification workflow.

## 💾 Storage Modes

Beads uses [Dolt](https://github.com/dolthub/dolt) as its database. Two modes:

- **Embedded (default)** — `bd init`. Dolt runs in-process, data lives in
  `.beads/embeddeddolt/`, single writer. Recommended for most users.
- **Server** — `bd init --server`. Connects to an external `dolt sql-server`
  for multiple concurrent writers; data lives in `.beads/dolt/`.

Cross-machine sync uses `bd dolt push` / `bd dolt pull` against
`refs/dolt/data` on your git remote; `.beads/issues.jsonl` is an export for
viewers and interchange, not the source of truth or a backup. Back up and
migrate between modes with `bd backup`; reclaim space with `bd prune` /
`bd purge`.

Full detail — connection flags, sockets, maintenance, backup, and migration —
in the [Dolt backend guide](docs/architecture/dolt.md).

### Schema Version Guard

`bd` checks the database schema version at open time. If the database has been
migrated by a newer binary and an older binary tries to open it, `bd` exits
with an actionable error rather than issuing queries that fail with cryptic SQL
errors:

````
schema version mismatch: database is at v45, binary knows up to v42 (3 migrations ahead)

  Your bd binary is stale. Queries for dropped or renamed columns will fail
  with cryptic SQL errors (e.g. "column X could not be found in any table in scope").

  Rebuild from main:
    CGO_ENABLED=0 go build -tags gms_pure_go ./cmd/bd

  Or install the latest release:
    CGO_ENABLED=0 go install -tags gms_pure_go github.com/steveyegge/beads/cmd/bd@latest

  To proceed despite the risk (some read commands may still work):
    BD_IGNORE_SCHEMA_SKEW=1 bd <command>
    bd --ignore-schema-skew <command>
````

**When this fires:** only when the database schema is *ahead* of the binary
(a newer binary migrated the database; this binary doesn't know those
migrations). Normal upgrades, where the binary migrates the database forward,
are unaffected.

**Escape hatch:** `BD_IGNORE_SCHEMA_SKEW=1` (or `--ignore-schema-skew`) bypasses
the guard with a warning on stderr. Use this only if you know the forward
migrations are additive and safe for your specific workload.

## 🌐 Community Tools

See [docs/community-tools.md](docs/community-tools.md) for a curated list of community-built UIs, extensions, and integrations—including terminal interfaces, web UIs, editor extensions, and native apps.

See [docs/related-projects.md](docs/related-projects.md) for adjacent or complementary projects that solve different problems in the same neighborhood.

## 🚀 Git-Free Usage

Beads works without git. The Dolt database is the storage backend — git
integration (hooks, repo discovery, identity) is optional.

```bash
# Initialize without git
export BEADS_DIR=/path/to/your/project/.beads
bd init --quiet --stealth

# All core commands work with zero git calls
bd create "Fix auth bug" -p 1 -t bug
bd ready --json
bd update bd-a1b2 --claim
bd prime
bd close bd-a1b2 "Fixed"
```

`BEADS_DIR` tells bd where to put the `.beads/` database directory,
bypassing git repo discovery. `--stealth` sets `no-git-ops: true` in
config, disabling all git hook installation and git operations.

This is useful for:
- **Non-git VCS** (Sapling, Jujutsu, Piper) — no `.git/` directory needed
- **Monorepos** — point `BEADS_DIR` at a specific subdirectory
- **CI/CD** — isolated task tracking without repo-level side effects
- **Evaluation/testing** — ephemeral databases in `/tmp`

## 📝 Documentation

* [Documentation site](https://beads.gascity.com/) | [Installing](docs/getting-started/installation.md) | [Sync Concepts](docs/core-concepts/sync-concepts.md) | [Agent Workflow](AGENT_INSTRUCTIONS.md) | [Copilot CLI Setup](docs/integrations/copilot-cli.md) | [Copilot VS Code MCP](docs/integrations/github-copilot.md) | [Articles](ARTICLES.md) | [Sync Branch Mode](docs/reference/protected-branches.md) | [Troubleshooting](docs/reference/troubleshooting.md) | [FAQ](docs/reference/faq.md)
* [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/gastownhall/beads)
