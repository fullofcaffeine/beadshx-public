# Base CI lanes

The bootstrap workflow has seven Linux jobs. Each job writes the exact source and
toolchain locks that governed its result. Each evidence artifact expires after
seven days and includes the Git commit for the run.

| Job | What it proves | What it does not prove |
| --- | --- | --- |
| Haxe and Go bootstrap | The locked compiler generates, checks, builds, and runs the empty BeadsHX binary. | No Beads command is compatible yet. |
| Pinned upstream oracle | The exact Beads v1.2.1 commit builds and its focused native test passes. | This does not retest the complete upstream suite. |
| Identity parity smoke | Both binaries have the expected, distinct bootstrap identities. | This is not behavior parity. |
| License boundaries | Generated output contains the two approved notice files with exact hashes. | Later release work owns full SBOM and archive checks. |
| Output compatibility plan | The command inventory and inherited upstream JSON corpus match the pinned Beads v1.2.1 source. | Explicit text, terminal, mixed-stream, server, signal, and post-state gaps remain unresolved. |
| Tracked tree and BeadsHX history scan | Gitleaks finds no secret in tracked files or commits added after the upstream baseline. | Six reviewed upstream fixture fingerprints remain narrowly ignored. |
| Bootstrap evidence gate | Every required producer job succeeded in the same workflow run. | A green gate does not admit a release platform. |

The local and hosted paths call `scripts/beadshx/ci-lane.sh` for each lane.
This script owns the repository checks. GitHub Actions prepares runners,
schedules jobs, and moves evidence artifacts.

Each hosted job checks the locked runner image before it starts its lane. The
hosted wrapper keeps the lane exit code when it writes evidence. It also keeps
the evidence after a lane fails.

Run `npm run ci:local` to run all seven lanes without `gh`, GitHub credentials,
or a hosted runner. The supported local path uses Bash on Linux or macOS.
Native Windows support is not part of this bootstrap contract.

A clean setup downloads locked tools from GitHub and npm. Thus, the local
command is independent of GitHub Actions, but it is not an offline command.

The local command writes each lane log under `build/evidence/local-ci/`.
`evidence-gate/results.json` contains the shared gate result. The top-level
`results.json` contains the local orchestrator result.

Run `scripts/beadshx/test-ci-lanes.sh` to check the job structure, action pins,
lock reports, failure behavior, and artifact retention. Run
`scripts/beadshx/scan-secrets.sh` to use the locked scanner bytes.
