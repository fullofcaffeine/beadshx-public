# BeadsHX compatibility reference

These pages describe in detail what `bdhx` does today, and where it still
differs from upstream Beads. The compatibility target is upstream `bd`
v1.2.1. Upstream behavior is the authority: "like upstream" on these pages
means that the parity tests check that `bdhx` prints the same output as
upstream for that case.

For a short overview, see the [project README](../../../README.md).

## Pages

| Page | What it covers |
| --- | --- |
| [Read commands](read-commands.md) | The commands that `bdhx` runs, issue prefixes, flags, argument checks and the role warning |
| [Output](output.md) | When commands print JSON, the JSON records, agent mode and colors |
| [Configuration](configuration.md) | The `.beads/.env` file, the `config` commands, and the config, permission and port warnings |
| [Workspace discovery](workspace-discovery.md) | How `bdhx` finds the workspace: `-C`, `BEADS_DIR`, `BEADS_DB`, `--db`, the `db` setting, redirects, `metadata.json` and older layouts |
| [Storage modes](storage-modes.md) | Embedded, server, shared-server and proxied workspaces, database names, the schema version check, strict read-only mode and gate locks |
| [Snapshot extension](snapshot.md) | `bdhx snapshot`, a read-only command that upstream does not have |
| [Known limits](limits.md) | Every known difference from upstream, grouped by topic, with its tracking task |

## Compatibility manifest

[compatibility/manifests/beads-v1.2.1.json](../../../compatibility/manifests/beads-v1.2.1.json)
records the same facts in machine-readable form: one record for each
upstream command, with its implementation and verification state, and one
difference record for each item on [Known limits](limits.md). The
[generated report](../../../compatibility/generated/beads-v1.2.1.md) shows
the totals. `scripts/beadshx/check-compatibility-manifest.sh` fails when a
task ID on the limits page has no difference record, or when a difference
quotes text that the page no longer contains. So update the manifest in the
same change as the page.

## Words used on these pages

- **Workspace:** a `.beads` directory with its configuration and its
  database.
- **Upstream** or **the oracle:** the pinned upstream `bd` v1.2.1 binary. The
  tests build it as `build/bin/bd-upstream`. A BeadsHX release build never
  calls it.
- **Embedded, server, shared-server and proxied:** the four ways to reach
  the database. [Storage modes](storage-modes.md) explains them.
- **Lookup, setup and redirect:**
  [Workspace discovery](workspace-discovery.md#words-used-on-this-page)
  explains them.
- **Not available yet:** the error that `bdhx` prints instead of running a
  case that it cannot match yet, for example one where upstream would write.
  The command exits with code 1 and changes nothing.

## How parity is checked

The parity suite runs each case twice, once with `bdhx` and once with the
oracle, in fresh disposable workspaces that the oracle creates. It compares
stdout, stderr and the exit code. For most cases it also checks that `bdhx`
changed no file in the workspace. Run it with `npm run test:parity` (or
`make beadshx-parity`). The cases are in
[scripts/beadshx/test-parity-smoke.sh](../../../scripts/beadshx/test-parity-smoke.sh).

Some output differs by design, and the suite normalizes it: workspace paths,
durations, times in log lines, and the development identity of `bdhx`. Where
upstream prints in a random order, the suite compares the stable part. Cases
where `bdhx` refuses on purpose run as candidate-only cases: they check the
exact refusal of `bdhx`, and that it wrote nothing.

Server-mode and proxied workspaces need a running Dolt server, which the
parity suite does not start.
[Read-only development preview](../operations/readonly-preview.md) describes
the separate proxied-server qualification.
