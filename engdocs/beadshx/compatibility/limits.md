# Known limits

This page lists every known difference between `bdhx` and upstream `bd`
v1.2.1. The other pages in this folder describe what already matches. A task
ID in parentheses names the Beads task that tracks a difference, where one
exists.

## Writes and migration

- `bdhx` does not write. Upstream commands that create, update, close or sync
  issues, such as `create`, `update`, `close`, `init` and `doctor`, are not
  ported, so `bdhx` prints `Error: unknown command "<name>" for "bd"`. The
  write subcommands of ported groups fail too: `comments add`, `label add`,
  `label remove`, `label propagate`, `config set`, `config set-many`,
  `config unset` and `config apply` report that they are not available yet,
  and `dep add` asks for one of the read subcommands. Writes come with the
  write milestones (M09 and later).
- Without `--readonly`, upstream migrates a database whose schema is behind
  the binary and that has no Dolt remote, and then runs the command. It also
  migrates when the `schema_migrations` table is missing or empty. `bdhx`
  never migrates. It stops with upstream's `--readonly` error and leaves the
  database unchanged.
  When the working set has changes in tables that a pending migration
  touches, upstream's read commands warn about these dirty tables instead of
  a migration, and `bdhx` stops in the same way. Migration parity (M12)
  removes this limit.
- When such a database has a Dolt remote, `bdhx` runs upstream's
  remote-migrate gate (see
  [Storage modes](storage-modes.md#remote-migrate-gate)). Where the gate lets
  upstream write, `bdhx` stops with `Error: <command> is not available yet
  where upstream would migrate a database with a Dolt remote in this build`.
  Upstream migrates with `BD_ALLOW_REMOTE_MIGRATE=1`, and when the cached
  remote is at the same version, v43 or later. The error says `fast-forward`
  instead when `HEAD` is an ancestor of a cached remote at v65 and the working
  set is clean: upstream then fast-forwards to the remote.
- At a gate stop, upstream's reads `list`, `count`, `ready`, `search`,
  `query` and `ping` print the gate's warning and read the database as it
  is. In `bdhx` they read through the native facade, whose strict read-only
  open cannot read a database behind the binary, so they print the same
  warning and then stop with `Error: <command> is not available yet on a
  database behind the binary in this build`, also with
  `BD_IGNORE_SCHEMA_SKEW=1` (beadshx-m08.67).
- Upstream `show` records the issue that it showed in `.beads/last-touched`.
  `bdhx` reads that file, for `show` without an ID, but never writes it
  (beadshx-m08.27).
- In an embedded workspace whose Git repository has a remote, upstream writes
  an automatic backup to `.beads/backup` after a command: the first time, and
  then at most every 15 minutes when the data changed. `bdhx` never writes a
  backup.
- In a workspace that has a legacy `.beads/config.json` and no
  `.beads/metadata.json`, `where` and every command that reads the database
  stop with `Error: <command> is not available yet when the workspace has
  only a legacy config.json in this build`. This also happens when `-C`, a
  `--db` path, the `db` setting or a redirect selects the workspace, and when
  such a workspace is the second target of a redirect chain. Upstream
  rewrites the file as `.beads/metadata.json` and runs the command. `bdhx`
  leaves the file in place. It stops where upstream rewrites the file: a
  command that reads the database after its first setup, and `where`,
  without a database path, after both setups and the lookups before its
  database lookup. So the warnings before the error are the ones that
  upstream prints before the rewrite. A `BEADS_DB` or `BD_DB` path that names
  such a workspace reports that the command is not available yet when that
  variable names this path. Like upstream, the shared-server notice takes the
  `dolt_mode` of the legacy file. `version`, help pages and unknown commands
  run as upstream does. With a `--db` path, upstream also rewrites the file
  for `version` and `bd help <command>`; `bdhx` prints the same output and
  writes nothing. This is a recorded exception
  ([exceptions.md](../program/exceptions.md)), and migration parity (M12)
  removes it.
- `bdhx` prints no tips. Upstream can print a random tip that recommends the
  Beads plugin for Claude Code after `show` and `ready`, and after the flat
  `list` view when agent mode is off. It does this when `CLAUDE_CODE` or
  `ANTHROPIC_CLI` is set or `~/.claude` exists, and the plugin or the
  `bd prime` hooks are not set up. Upstream then records the time of the tip
  in the database, and `bdhx` does not write.
- When a workspace gate lock file is missing, upstream creates it, as an
  empty file with mode 0600, and locks it. `bdhx` does not create it, so it
  reads without that lock and prints the same output. A maintenance command
  that starts during that read can take that lock.
- Upstream opens each workspace gate lock file for writing, and `bdhx` opens
  it read-only. For a lock file that the user can read but not write,
  upstream prints `warning: workspace gate acquisition failed, continuing
  ungated: ...` and reads without the locks. `bdhx` takes the lock and prints
  no warning.

## Server-mode, proxied and shared-server workspaces

[Storage modes](storage-modes.md) explains these modes.

- `dep tree`, `dep cycles`, `blocked`, `comments`, `history`, `graph`,
  `graph check`, `types`, `statuses`, `events tail`, `events export`,
  `config get`, `config list`, `config show`, `config validate` and
  `config drift` read embedded workspaces only. In a server-mode or proxied
  workspace they report that they are not available yet. If the server
  cannot be reached, they print the same store error as upstream. This is
  also true for a server-mode workspace that still has a
  `.beads/embeddeddolt` directory from before. `types --sections` prints its
  fixed list in every mode.
- `snapshot` reads embedded workspaces only. In a server-mode, shared-server
  or proxied workspace and with `--global`, it reports that it is not
  available yet, before it opens anything.
- `label list-all` reports that it is not available yet in a proxied
  workspace.
- In a server-mode or proxied workspace, `ready --explain` cannot read the
  stored `is_blocked` flag or the full dependency tables yet. Its blocked list
  then holds each issue that has an open blocker. This list is different from
  upstream's only when a stored flag does not agree with the dependencies.
  Its cycles then leave out a cycle through an ID that has no issue record.
- In a server-mode or proxied workspace, the records of `stale --json` have
  no `labels` field, because `bdhx` does not read the labels there yet
  (beadshx-m08.46).
- The parity tests have no Dolt server, so they do not compare the schema
  version check of a server-mode or proxied workspace. They compare only
  that it stops at upstream's connection error when the server does not
  answer. In a server-mode workspace, `bdhx` leaves the check to upstream's
  server open in its native code. That code puts `failed to open database: `
  before the error, so `bdhx` does not see a schema refusal there. For a
  database ahead of the binary, `bdhx` then probably prints `Error: failed to
  open database: schema version mismatch: ...` on one line in every output
  mode, where upstream prints its stale-binary message or its JSON error with
  `schema_skew`. With the escape hatch, the warning probably repeats once for
  each native open, such as each list read of a `children` tree. Upstream's
  read-only server open does not check a database that is behind the binary
  (beadshx-m08.62).
- Every command that reads the database reports that it is not available yet
  in shared-server mode, and when the `db` setting names a database. Only
  `version`, `where` and help pages still run. In these cases upstream
  connects to the shared server, which creates `~/.beads/shared-server/dolt`
  and a file under `TMPDIR`, or it opens or creates the database at that
  path. `bdhx` refuses before it opens anything, and writes nothing. In a
  shared-server workspace that has no database, `config show`,
  `config validate` and `config drift` still report that they are not
  available yet, and so does every command when a `--db` path names the
  database. [Storage modes](storage-modes.md#shared-server-mode) describes
  what matches upstream there.
- `config validate` and `config drift` also report that they are not
  available yet with `--global`, and when a Dolt server host, port or
  socket, `BEADS_DOLT_DATA_DIR` or a central server config is set. In these
  cases upstream connects to a server or creates a database.
  `config validate` also reports this when the workspace directory is not
  named `.beads` or holds its own `redirect` file.

## Workspace selection and redirects

[Workspace discovery](workspace-discovery.md) describes what matches.

- When `--db` selects a workspace whose `.beads/metadata.json` cannot be read
  or does not decode, every command that reads the database reports that it
  is not available yet. Upstream then prints the load warning and error, or
  opens or creates a database in another directory. `where` reports this too
  when `bdhx` finds that workspace for a `--db` or `db` setting path, but
  upstream derives another directory from the path.
- When `BEADS_DB` (or, for `where`, `BD_DB`) selects with another path,
  `where` and every command that reads the database report that they are not
  available yet. This applies to a missing path outside a `.beads` directory,
  a directory that is not a workspace, a workspace without an embedded
  database, a server-mode, proxied or redirected workspace, a path deeper in a
  `.beads` directory and a path with a trailing slash. For most of these paths
  upstream creates an embedded database. `version` and help pages still run.
  Before the refusal, `bdhx` sets up the directory that upstream derives from
  the path: like upstream, it loads the `.env` file there and prints the
  config warning and the shared-server notice. When `.beads/metadata.json`
  there does not load, `bdhx` prints upstream's `warning: load ...` line and
  `Error: loading config: ...` instead of the refusal, and a legacy workspace
  layout there stops the command with upstream's error. The refusal is JSON
  when the `json` setting of that directory turns JSON on, as upstream rereads
  it there.
- On macOS, `bdhx` takes the stored letter case of a path from the names that
  its directories list. Upstream first asks the kernel (`F_GETPATH`). This
  can give other names below a directory that cannot be listed, for a hard
  link, and for a name stored in another Unicode normalization. This applies
  to `BEADS_DB`, `BEADS_DIR`, `-C` and redirect targets (beadshx-m08.55).
- `bdhx` follows redirects at each of upstream's workspace lookups, but these
  lookups do not include upstream's Git worktree and jj workspace fallbacks.
- When `bdhx` finds a usage error that upstream finds only in its pre-run or
  command body, it prints no redirect warning before the error.
- Upstream also trusts the macOS Shared folder when it decides whether to
  read a workspace's redirect after a command. `bdhx` does not, so for a
  workspace in that folder it prints the redirect warning two times fewer than
  upstream (beadshx-m08-01.13).
- For a redirect into a detached commit worktree, upstream stops each Git
  command of its branch-worktree choice after 5 seconds. `bdhx` waits for
  Git.
- In a `.beads/.env` file that is not valid UTF-8, `bdhx` changes each
  invalid byte to U+FFFD. Upstream keeps the byte.

## Embedded store layouts

[Storage modes](storage-modes.md) describes what matches.

- In an embedded workspace, every command that reads the database reports
  that it is not available yet when the embedded store has no database with
  the name that `.beads/metadata.json` selects. This applies to `null`, `{}`
  and an empty `dolt_database`, which select `beads`, and to every other
  missing name, also from `BEADS_DOLT_SERVER_DATABASE`. Upstream creates that
  database. `where`, `version` and help pages still run.
- In a workspace without `.beads/metadata.json`, every command that reads the
  database prints upstream's warning and then reports that it is not
  available yet when the embedded store has no `beads` database. Upstream
  creates that database. `bdhx` also reports that the command is not
  available yet when `BEADS_DOLT_SERVER_DATABASE` names another database, and
  when `BEADS_DOLT_SERVER_MODE=1` or the `dolt.mode` setting selects server
  mode. Upstream opens `beads` in these cases, but the native store open
  would not. In shared-server mode, `bdhx` prints the warning before the
  shared-server refusal, as upstream prints it before it reaches the shared
  server.
- In an embedded workspace without `.beads/embeddeddolt`, a data directory
  that `BEADS_DOLT_DATA_DIR` or `dolt_data_dir` names makes upstream create
  the embedded database, unless it is in strict read-only mode. Every command
  that reads the database then reports that it is not available yet for an
  embedded workspace without `.beads/embeddeddolt`.

## Commands and output

- `graph` for one issue or `--all` reports that it is not available yet when
  upstream would look up the `<id>` of an `external:<project>:<id>`
  dependency in another repository. This happens when the first
  `routes.jsonl` rule for the prefix of the ID names another workspace whose
  `metadata.json` names a `dolt_database`, or when contributor auto-routing
  names another repository. Upstream then opens that store read-only and adds
  the issue that it finds there. When it finds none, upstream draws the graph
  without the dependency, so `bdhx` also refuses some graphs that upstream
  draws. `bdhx` reads one database only.
- `show`, `comments`, `dep list` and `dep tree` report that they are not
  available yet when upstream would look up an issue ID that is not in the
  database in another repository: through the first `routes.jsonl` rule for
  the prefix of the ID, when it names another workspace whose
  `metadata.json` names a `dolt_database`, or through contributor
  auto-routing. `list`, `ready` and `children` report it when contributor
  auto-routing selects the planning store of another repository. Upstream
  opens that store read-only. When the routed store does not hold the ID
  either, upstream reports the miss, and when the planning store does not
  open, upstream fails. So `bdhx` also refuses some commands that upstream
  answers with an error. `bdhx` reads one database only; the routed reads
  themselves wait for routing and shared stores (beadshx-m13-07). See
  [Read commands](read-commands.md#routed-reads).
- In a server-mode workspace, contributor auto-routing takes its settings
  only from `config.yaml` and the environment: `bdhx` cannot read the
  database's config table there yet. When only the database sets them,
  `bdhx` reads this workspace where upstream reads another repository
  (beadshx-m08.60). When auto-routing names the workspace itself, `list`,
  `ready` and `children` report that they are not available yet for
  server-mode workspaces, because `bdhx` cannot count the issues for
  upstream's note there.
- With `BD_IGNORE_SCHEMA_SKEW=1` on a database that is ahead of or behind the
  binary, a command that opens the native store more than once prints the
  warning once for each open. Upstream prints it once. In an embedded
  workspace, `list --watch` still does this: it prints the warning once more
  at each refresh (beadshx-m08.65, beadshx-m08.71 for `--ready`).
- `bdhx` renders most `list --format` Go templates itself (see
  [Read commands](read-commands.md#list---format-templates)). Some templates
  need upstream's Go types, for example `{{printf "%T" .Type}}`,
  `{{.Issue.CreatedAt.Year}}`, `{{.Issue.ClosedAt}}`, `{{.Issue.Metadata}}`
  or `{{.Issue}}`. `bdhx` runs these templates in a Go facade on upstream's
  types, so the output is the same, with two differences. When stderr is a
  terminal and `--limit` hides more issues, `bdhx` does not print upstream's
  hint after the output. When the template fails on a later issue, `bdhx`
  prints only the error, and upstream has already printed the lines of the
  issues before it (beadshx-m08.26).
- `bdhx` refuses `ready --claim`, so it never prints upstream's colored
  claim lines.
- On a terminal with colors on, `bdhx` can ask the terminal for its
  background color twice: once when it starts, in the upstream code of the
  Markdown renderer, and once before the first colored view. Upstream asks
  once.
- `events tail --follow` and `events prune` report that they are not
  available yet.
- `config get` of a user-global key (`metrics.*`, `node_id`) and
  `config show` report that they are not available yet when the user
  `config.yaml` exists. `config show` also reports this in a workspace that
  has no database, where upstream creates the embedded database.
- When an issue ID does not match exactly and the database stores no
  `issue_prefix`, `bdhx` uses the prefix from `config.yaml` instead. Upstream
  uses `bd` and then guesses the prefix of each matching issue. With neither
  prefix, `bdhx` does not find a prefixed issue from its hash alone. In a
  server-mode or proxied workspace, `bdhx` does not read the stored prefix
  for this lookup and uses the `config.yaml` prefix; upstream reads the stored
  one.
- Where upstream output order is random (Go map order), the parity tests
  compare the stable part, and `bdhx` prints one fixed order.
- `ready --explain` and `graph check` find cycles with upstream's walk, which
  starts at the issues in a random order. So upstream can start a cycle of
  two or more issues at any one of them, and can list two or more cycles in
  another order. `bdhx` starts the walk at the issues in the byte order of
  their IDs, which gives one of upstream's results.
- For an unknown command, `bdhx` prints no `Did you mean this?` list. Upstream
  lists every command whose name starts with the unknown name, or is at most
  two edits away from it. Most of those commands, such as `gc`, `kv`, `lint`
  and `sql`, are not ported yet, so `bdhx` cannot print the same list until
  they are. The parity tests use unknown names that upstream has no
  suggestion for (beadshx-m08.34).
