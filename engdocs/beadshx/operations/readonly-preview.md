# Read-only development preview

BeadsHX is a development candidate. Keep the pinned upstream `bd` as the
primary task client. This preview does not qualify production database use,
write commands, every Beads flag, or the complete M08 read-only milestone.

## Command coverage

The Haxe command enum admits the following commands. Admission means that a
handler exists. It does not prove compatibility for every argument or backend.

| Commands | Embedded differential coverage | Proxied-server differential coverage |
| --- | --- | --- |
| `list`, `show` | Text, JSON, filters, relationships, and watch cases in the parity corpus | `list --json --all`; `show --json ID` |
| `count` | Count and grouped-count cases | `count --json`; `count --by-status --json` |
| `ready` | Filters, blocked state, molecules, and gate cases | `ready --json --limit 0` |
| `search`, `query` | Search and query cases | `search --json Proxied`; `query status=open --json` |
| `stale`, `orphans` | Stale and orphan cases | `stale --json --days 1`; `orphans --json` |
| `children`, `dep list` | Relationship cases | `children ID --json`; `dep list ID --json` with a nonempty parent relation |
| `where`, `info`, `ping`, `status` | Workspace, diagnostics, and database cases | `where --json`; `info --schema --json`; `ping --json`; `status --json` |
| Root help, `version` | Development identity, parsing, and terminal cases | No database backend required |

The scripts define the exact cases and normalizations. In particular, the
embedded suite normalizes workspace paths and ping durations. Watch checks
separate task state from documented transient embedded-engine files. Development
identity deliberately differs from upstream. Do not interpret those differences
as full byte-for-byte compatibility.

`dep list --direction=up` is not implemented in this profile. Configuration,
comments/history, other dependency and graph commands, and snapshot artifacts
remain outside this preview. Native Go storage bridges remain in the current
implementation; this preview is not completion evidence for the Haxe-only port.

## Reproduce qualification

Use the locked toolchain and a Docker host that can run the pinned Dolt server
image. From the repository root, run:

```sh
npm run bootstrap
npm run build:oracle
npm run test:parity
scripts/beadshx/test-proxied-readonly-contract.sh
scripts/beadshx/test-proxied-readonly.sh
```

Rebuild both binaries before qualification. A binary left in `build/bin` from
an earlier checkout is not evidence for the current source. Record the source
commit, toolchain lock, binary hashes, host, and command logs with each run.

The embedded suite initializes marked temporary workspaces with the upstream
binary. It compares exit codes, stdout, and stderr and checks candidate file
state before and after each read. The server tracer also validates and normalizes ping timings. It uses a temporary workspace
and an isolated test server. It compares decoded JSON, requires empty stderr
and successful exit, and checks the native revision, complete working database hash, working set, proxy identity,
configuration, filenames, file contents, and modes around candidate reads.
A skipped server test fails qualification.

A passing run qualifies only the cases in that run on its recorded host and
backend. Extend the corpus and rerun both backends before extending the claim.
For real-workspace use, first follow the staged gates in
[data-safety.md](data-safety.md). No automated qualification command may target
a primary task database.
