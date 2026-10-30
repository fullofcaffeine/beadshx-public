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

## Commit privacy checks

Run `npm run hooks:install` in each checkout. The versioned pre-commit hook
checks staged files for secrets, private runtime files, and machine-local paths.
The secret check uses a frozen copy of the Git index, validates exceptions
against those same staged bytes, and selects the pinned scanner's built-in
rules. Inline suppression comments and environment-supplied scanner rules do
not bypass the check. The CI secret lane scans the committed tree and the
BeadsHX commit range; it is not an audit of every remote branch or GitHub text.

To reject personal names, private email addresses, or private service URLs,
create `info/private-content-patterns.json` inside the directory reported by
`git rev-parse --git-common-dir`. Keep it local with mode `0600`. Its format is
`{"patterns":["private value to reject"]}`. Use exact values, not regular
expressions. The guard checks changed staged blobs, filenames, and the pending
commit's author and committer identities. It does not print matched values.
The file is shared by linked worktrees and is never committed or uploaded.
A malformed policy blocks the commit; an absent policy leaves only the shared
path and runtime-file checks active. CI cannot check local-only private values.

Hooks can be bypassed by a user and cannot recognize every kind of personal
information. Before making a private repository public, separately audit all
reachable refs, author metadata, PR text, logs, and artifacts. Do not push
private backup branches or use a mirror push to a sanitized public repository.
Existing public upstream contributor attribution is not permission to publish
new private identities.
