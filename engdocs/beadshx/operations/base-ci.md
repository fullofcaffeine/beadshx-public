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

The pre-push hook uses this same local policy to check stored author and
committer identities for every outgoing ref. It checks annotated tagger
identities, including nested tags. It reads the actual object IDs supplied by
Git, so pushing another branch or several refs does not borrow the checkout's
`HEAD` identity. Deletions and unchanged refs add no commit identities.

The check walks only commits that the push destination does not already have.
Before it scans, the hook asks the destination for its current refs with
`git ls-remote`. It then excludes every local commit reachable from a ref that
the destination advertises, and the previous object of an updated ref. A push
cannot newly expose a commit that the destination already serves, so older
published history does not block new work. Only the destination's own answer
counts: other local refs, remote-tracking refs, and other remotes never exempt
a commit. If the destination cannot be read, the push is blocked. With an
active policy, incomplete history or an unreadable object also blocks the push;
fetch the required history before retrying. Local replacement objects cannot
substitute identities.

The hook rejects private Beads data refs before calling Beads. Its release-tag
version check and Beads stdin, arguments, and timeout handling stay in place.
A privacy check failure blocks the push even when Beads would skip its own
hook. Without a local policy, personal identity checks remain unavailable.
File-content checks remain the staged and CI scans described above.
Tag messages, commit messages, hosting-service text, and identities created by
a hosting-service merge require separate review. Use a reviewed local merge
and verify its stored metadata before publication; then verify the published
default branch. Local checks do not override branch protection or grant merge
permission.

Hooks can be bypassed by a user and cannot recognize every kind of personal
information. Before making a private repository public, separately audit all
reachable refs, author metadata, PR text, logs, and artifacts. Do not push
private backup branches or use a mirror push to a sanitized public repository.
Existing public upstream contributor attribution is not permission to publish
new private identities.
