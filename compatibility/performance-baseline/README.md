# Upstream performance baseline

This directory measures Beads v1.2.1 as a reference. It does not define a
BeadsHX performance budget.

`policy.json` is the workload and fixture registry. A captured run records the
exact source commit, binary digest, machine profile, fixed environment, fixture
digest, and every raw sample. The generated report compares repeated samples;
it never turns a single timing into a performance claim.

The published evidence contains two independent runs from the same native
Darwin ARM64 machine. Each run measures 37 workloads ten times after one
untimed setup run. The native Linux AMD64 migration workload is marked
unavailable on this host. The harness does not replace it with emulation.

The workload set covers clean, warm, and no-change builds. It also covers
startup, reads, writes, local sync, backup and restore, current-schema
migration, large output, benchmark discovery, and selected storage benchmarks.
Selected Go benchmarks retain iterations, time, bytes, and allocations per
operation.

The harness uses disposable directories only. It disables metrics, event
flushes, hooks, editors, pagers, update checks, automatic import, and public
network access. Read workloads use a fresh fixture copy. Write workloads use a
separate fresh copy for each sample. Setup and validation are outside the timed
region.

Sync uses a local filesystem Dolt remote and two disposable replicas. Backup
validation restores every artifact and compares a full logical export. Physical
backup digests can differ because Dolt writes storage metadata. The harness
retains those digests but does not use them as a logical equality claim.

The server benchmarks use the repository-pinned Dolt 2.2.0 binary. The server
listens on loopback with an ephemeral port. It never uses Docker or a shared
server.

Profiles that cannot run on the current host stay explicit. The harness does
not replace an embedded database with a remote database, treat an emulated
machine as a native host, or claim an operating-system cold cache.

## Evidence layout

`runs/<run-id>/manifest.json` records the source, machine, binary, server,
environment, and fixture identities. `samples/*.jsonl` retains each raw sample.
`summary.json` regenerates from those samples. `artifact-index.json` protects
every published file with a SHA-256 digest and byte count.

`comparison.json` compares both runs without assigning pass or fail to timing
differences. It reports elapsed means, medians, p95 values, coefficients of
variation, and each later mean relative to the first run.

The checker rejects missing samples, one-off measurements, changed artifact
hashes, stale summaries, different machine identities, and common private path
markers.

## Local commands

```sh
npm run baseline:upstream-performance -- --run-id darwin-arm64-a
scripts/beadshx/performance-baseline.sh comparison
npm run test:upstream-performance
```

Set `--source-repository` when the Beads source is not available at `../beads`.
The capture command also requires the pinned Dolt binary under `.toolchains`.

Capture is intentionally separate from normal CI because it takes many
minutes. Local and hosted CI run the same fast evidence checker. The checker
uses committed raw evidence and does not need GitHub CLI, Docker, a Dolt
server, or network access.
