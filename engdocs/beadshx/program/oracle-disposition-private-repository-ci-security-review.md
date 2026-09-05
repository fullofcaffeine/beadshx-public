# Oracle disposition: private repository CI and security

## Local baseline

The repository remains private. The reviewed change adds repository hooks,
local CI, hosted CI, secret scanning, and package checks. It does not change
repository visibility or release policy.

Oracle reviewed request `orq_20260815T202844Z_76d4971c` in review mode. The
request required `gpt-5.6-sol` at `xhigh` for local reconciliation. The Oracle
response blocked the staged state before this correction pass.

## Oracle claim matrix

| Oracle claim | Decision | Local result |
| --- | --- | --- |
| The staged Go hook can change files and stage unrelated data. | Retained | The hook now reads index blobs into temporary files. It never changes the worktree or index. It rejects non-regular entries, partial staging, index changes, and concurrent worktree changes. |
| Hosted wrappers can hide lane errors and lose failure evidence. | Retained | One hosted wrapper keeps each lane exit code. It always writes a result, a log, and a lock report before it returns. Artifact uploads use `always()`. |
| The local path guard fails open and parses human patch headers. | Retained | A Python guard reads raw Git records and blob objects. It has no `rg` dependency or environment bypass. Hosted bootstrap scans the BeadsHX commit range. |
| Version labels do not prove the executed tool state. | Retained | Setup always runs `npm ci`. haxe.go must be clean and self-contained. Go workspaces and module replacements are rejected. Pre-commit uses a local locked environment. Gitleaks binary hashes and GolangCI module sums are locked. |
| Five hosted jobs do not check the locked runner image. | Retained | Every hosted job runs the small runner check before its repository lane. |
| Product installation silently changes Git hooks. | Retained | `make install` no longer changes `core.hooksPath`. The hook installer is the only supported hook configuration command. |
| Gitleaks exceptions can hide changed fixture content. | Retained | Each exception now has an exact source-line hash. The check rejects changed bytes or a new exception. CODEOWNERS covers both files. |
| Package inputs can be stale, unsafe, or replaced before verification. | Retained | Packaging always rebuilds the candidate. It rejects symlinks and non-regular files, limits entry sizes, compares source and archive hashes, and verifies a temporary archive before one atomic rename. |
| Checkout credentials and policy-set tests need stricter checks. | Retained | Every checkout disables persisted credentials. Tests compare the exact hook and action sets to the reviewed policy. |
| Native Windows local CI needs separate evidence. | Deferred | The documented local path admits Bash on Linux and macOS. Native Windows remains outside this bootstrap contract. |
| Publication needs all-ref scanning, release controls, and SBOM work. | Deferred | These tasks remain publication and release gates. This private-repository change does not claim them. |

## Integrated conclusion

The block was correct. The old Go hook crossed both worktree and index
boundaries. The old hosted workflow also had weaker failure evidence than the
local command.

Go formatting is now check-only. “Local without GitHub” means that the command
does not use GitHub Actions, `gh`, or GitHub credentials. It does not mean that
a clean setup is offline. Product installation does not configure repository
hooks.

No haxe.go compiler change was necessary. All fixes belong to BeadsHX
repository tooling and package code.

## Verification

The following checks ran on the corrected checkout:

- The real `.githooks/pre-commit` hook passed all configured checks.
- `scripts/beadshx/test-repository-safety.sh` passed its path, Go authority,
  Gitleaks exception, package, and policy-set cases.
- `scripts/beadshx/test-ci-lanes.sh` preserved a controlled lane exit code of
  37 and retained its evidence.
- `scripts/beadshx/run-golangci.sh --new-from-rev=HEAD` reported zero issues.
- `npm run package` passed. Two fresh archives had the same SHA-256 digest.
- `npm run ci:local` passed all six lanes.
- A second local CI run passed with GitHub tokens removed and a failing `gh`
  shim first on `PATH`.

The inherited `TestInstallHooksBeads_WorktreeAccess` fixture problem remains
separate under `beadshx-m01.2`. This disposition does not weaken the Beads
client pin or schema checks.
