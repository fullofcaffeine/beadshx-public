# Output

This page describes how `bdhx` chooses and formats its output: JSON, agent
mode for AI agents, and colors. All of it matches upstream `bd` v1.2.1. For
the differences that remain, see [Limits](limits.md#commands-and-output).

## When commands print JSON

Like upstream, every command prints JSON, exactly as with `--json`, when
`json: true` is set in `config.yaml`, `config.local.yaml` or the user
`config.yaml`, or when `BD_JSON` is true. `BD_JSON` is true for `1`, `t`,
`T`, `true`, `True` and `TRUE`, and false for any other value. An empty
`BD_JSON` is ignored. `BD_JSON` outranks the files, and `--json`,
`--json=false` and `--format` outrank both. The `--format` flag of `list` and
`dep tree` does not count, but `--format json` always selects JSON. Help
pages, `--version` and flag errors stay text.

## JSON records

Like upstream, each issue record in JSON output has every field of upstream's
issue record, in upstream's order. Fields that are empty are left out, as
Go's `omitempty` rule does. This applies to `list`, `children`, `query`,
`search`, `ready`, `blocked`, `show` (also `--children`, `--refs` and
`--thread`), `dep list`, `dep tree`, `graph` and `stale`:

- The `labels`, and the `dependencies` of `list`, come after
  `original_size`, as in upstream.
- `show` prints each dependency and dependent as a whole issue record with
  its dependency fields.
- The records of `show --thread` and `stale` include the issue's labels.
- `show --children`, `show --refs` and the `--mol`, `--gated` and `--explain`
  views of `ready` print their keys in sorted order, as upstream does,
  unless `BD_JSON_ENVELOPE=1` is set. `list --skip-labels` also keeps
  upstream's sorted keys.

An empty result prints `[]`, also for `stale`, `ready --explain` and its
`ready` and `blocked` lists. `count` with a `--by-*` flag keeps its grouped
form when no issue matches: `Total: 0`, or `{"groups": [], ...}` in JSON.

## Agent mode

Like upstream, `bdhx` has an agent mode for output that AI agents read.
`BD_AGENT_MODE=1` or any `CLAUDE_CODE` value that is not empty turns it on,
also from the `.beads/.env` file. In agent mode:

- The flat `list` view (`--flat`, also with `--long`) prints one
  `ID: Title` line for each issue. A dependency note in parentheses follows
  when the issue has a parent, a blocker or a dependent. The view prints no
  status icon, priority, type, labels or `--skip-labels` footer.
- When stdout is a terminal, `list` shows 20 issues by default instead of 50.
- `show` prints Markdown text as it is stored, without wrapping.
- The tree view of `list`, `--format` and `--json` do not change.

## Colors

Like upstream, these commands print colors: `list` (every text view, also
`children` and `--watch`), `ready` (the default, `--pretty` and `--plain`
views and their notes), the `query` list, `show` (every text view, also
`--short`, `--children`, `--refs`, `--thread` and `--watch`), `blocked`, the
`--explain`, `--mol` and `--gated` views of `ready`, `dep list`, `dep tree`,
`dep cycles`, `graph` (every text view, also `graph check`), `history`,
`label list`, `label list-all`, `stale`, `orphans`, `status` (also `stats`),
`statuses` and `ping`. Like upstream, `dep tree` prints the `[READY]` and
`[BLOCKED]` marks in bold also when colors are off.

Colors are on when stdout is a terminal, or when `CLICOLOR_FORCE` has any
value that is not empty, also `0` and also with `TERM=dumb`. Colors are off
when `NO_COLOR` is not empty, `CLICOLOR=0` or `BD_GIT_HOOK=1` is set, `TERM`
is `dumb` (without `CLICOLOR_FORCE`), or `--no-color` is given. `bdhx`
decides this from the environment at start, as upstream does, so a value
from the `.beads/.env` file does not change it.

The colors are upstream's 24-bit Ayu colors, whatever `TERM` says, and the
`lipgloss` library prints them. When stdin and stdout are both terminals,
`bdhx` asks the terminal whether its background is dark or light; otherwise
it uses the dark colors. Also when colors are off, `bdhx` changes each tab to
four spaces in the parts that upstream styles, such as the title of a closed
issue.
