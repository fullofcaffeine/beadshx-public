# Agent Instructions

## BeadsHX program overlay

BeadsHX is a compatibility fork of Beads v1.2.1. Haxe owns the complete
first-party Beads implementation. Haxe consumes Go standard-library and
independent third-party APIs through precise externs by default. Small typed Go
facades are exceptions only for proven third-party or platform boundaries; an
upstream Beads package is porting source, not a permanent native dependency.
The upstream Beads behavior and database format remain the compatibility
authority until a visible, approved divergence says otherwise.

Read `beadshx-complete-port-prd.md`, `engdocs/beadshx/program/source-index.md`,
and `engdocs/beadshx/operations/data-safety.md` before changing BeadsHX behavior. The upstream
instructions below still govern inherited Go code unless this overlay is more
specific.

### Source and generated-code ownership

- Authored Haxe under `src/beadshx/` is the preferred source for domain rules,
  command handlers, validation, diagnostics, application services, and public
  BeadsHX behavior.
- Consume exported Go standard-library and independent third-party libraries
  through precise Haxe externs first. Use haxe.go's deterministic binding
  generator and fallback report when they fit the package.
- Do not classify upstream Beads product code as a permanent external library
  merely because it exports a Go API. Packages that own Beads application,
  domain, command, validation, query, dependency, graph, or rendering semantics
  are porting sources: authored Haxe must replace that behavior before the
  corresponding compatibility task can close.
- An extern over an upstream Beads semantic API can be used as explicit,
  removal-tracked tracer scaffolding. It is not final port evidence. Final
  release paths must not depend on upstream Beads first-party Go packages,
  including command, issueops, storage, unit-of-work, domain, validation,
  rendering, configuration, sync, or integration implementations. Port those
  behaviors to authored Haxe and reach only standard-library, driver, CGO,
  platform, or independent third-party APIs through precise externs.
- Before adding or expanding handwritten Go, prove that the pinned compiler
  cannot represent the required safe boundary with a reduced, library-neutral
  fixture.
- Fix each reusable haxe.go gap in an isolated worktree and pull request. Run
  the compiler repository's required checks, review the generated Go, and
  merge the pull request before BeadsHX consumes the change.
- After a compiler merge, update the exact BeadsHX compiler lock. Regenerate
  the Go output and prove the focused compiler fixture and real BeadsHX path.
- Keep handwritten native Go only for a proven independent third-party or
  platform boundary that a reusable haxe.go compiler or SDK improvement cannot
  safely represent. An unexported upstream Beads API does not qualify: port the
  first-party behavior to Haxe and bind the lower standard-library or
  independent driver API instead. Each native island must satisfy the PRD's
  native-island test, remain narrow and typed, and contain no product policy.
- Generated Go is disposable compiler output. Never hand edit it to make a
  check pass.
- Keep the upstream oracle available as an explicitly named binary. A release
  build must never delegate a command to it.

### Production-data safety

- Never run automated, destructive, migration, recovery, parity-write, or
  fault-injection tests against a primary Beads database.
- Create test workspaces under a fresh temporary directory and require the
  repository's disposable-fixture marker before a destructive test starts.
- Treat `BEADS_DB` as insufficient isolation for `bd init`; initialization and
  all later commands must run inside the disposable workspace.
- Back up before migration or recovery experiments. A successful process exit
  never proves a write; read the result back through the native authority.
- Do not bypass schema checks, use `--ignore-schema-skew`, or let an ambient
  `bd` binary choose the database client.

### Private Beads tracking remote

- The public code repository is not a Beads data remote. Never push
  `refs/dolt/data` or `__dolt_remote_info__` to its Git origin.
- Before `bd dolt push` or `bd dolt pull`, make sure that the configured Beads
  remote is the approved private maintainer sidecar. Use `--no-adopt` for
  every push. Never let `bd` derive a data remote from the public Git origin.
- Keep the private sidecar URL and issue data out of tracked files, logs,
  pull requests, and public CI evidence.

### Haxe rules

- Use Haxe 4.3.7 and precise Haxe types. Optional structure fields use `?`.
- Do not use `Dynamic`, `Any`, `Reflect`, `untyped`, unchecked `cast`, or raw
  Go injection as design shortcuts. Contain unavoidable foreign boundaries,
  validate immediately, and return concrete types.
- Parse JSON, CLI, filesystem, configuration, compiler, and native data at
  explicit typed boundaries.
- Prefer module-level functions for stateless module-owned behavior, named
  record-shaped inputs, exhaustive variants, typed adapters, and concise
  Why/What/How HaxeDoc for non-obvious boundaries.
- For meaningful behavior, start with the smallest faithful failing contract,
  then prove one Haxe-to-generated-Go-to-native-runtime tracer bullet.

### Repository commands

The BeadsHX-specific command surface is introduced incrementally under M01.
Until those wrappers exist, use the inherited upstream commands only for the
unchanged pinned oracle and follow `engdocs/TESTING.md`. Do not claim that a
BeadsHX command or compatibility lane exists merely because upstream passes.

<!-- bd-doctor-divergence: ok -->

See [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) for full instructions.

This file exists for compatibility with tools that look for AGENTS.md.

The marker above tells `bd doctor` that the intentional divergence between
this file and `CLAUDE.md` (different audiences, different reading orders) is
expected and should not be flagged.

## Key Sections

- **Issue Tracking** - How to use bd for work management
- **Development Guidelines** - Code standards and testing
- **Project Scope** - Read [engdocs/PROJECT_CHARTER.md](engdocs/PROJECT_CHARTER.md) before adding new feature surface area
- **Visual Design System** - Status icons, colors, and semantic styling for CLI output
- **Contributor Protection** - Read [CONTRIBUTING.md](CONTRIBUTING.md) before handling external PRs
- **Maintainer PR Guidelines** - Read [PR_MAINTAINER_GUIDELINES.md](PR_MAINTAINER_GUIDELINES.md) before triaging, landing, or closing PRs

## Project Scope

Before adding new feature surface area, read
[engdocs/PROJECT_CHARTER.md](engdocs/PROJECT_CHARTER.md). Beads owns issue tracking
primitives and should not encode orchestration-layer policy, become a storage
engine, or casually expand the database schema when metadata would work.

## PR Safety for Agents

Before triaging, reviewing, landing, closing, or otherwise maintaining PRs, read
[PR_MAINTAINER_GUIDELINES.md](PR_MAINTAINER_GUIDELINES.md). The maintainer
policy is to maximize community throughput: find useful contributor value,
absorb or transform it locally when practical, preserve attribution, and use
request-changes only as a last resort.

Before implementing work, opening a PR, or merging/closing a PR, run the PR
preflight:
```bash
scripts/pr-preflight.sh --search "<topic keywords>" --repo gastownhall/beads
scripts/pr-preflight.sh <pr-number> --repo gastownhall/beads
```

External contributor PRs have priority. Review and build on their branch when
possible, preserve their tests and attribution, and never close or supersede
their PR silently. If a rewrite is unavoidable, explain why on the original PR
and credit their design/tests.

## Visual Design Anti-Patterns

**NEVER use emoji-style icons** (🔴🟠🟡🔵⚪) in CLI output. They cause cognitive overload.

**ALWAYS use small Unicode symbols** with semantic colors (status uses symbols; priority uses labels):
- Status: `○ ◐ ● ✓ ❄`
- Priority: `P0`–`P4` label with color (no status glyph)

See [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) for full development guidelines.

## Storage Boundary

The canonical storage boundary is in
[engdocs/PROJECT_CHARTER.md](engdocs/PROJECT_CHARTER.md#storage-boundary). In short:
Beads talks to storage through a driver interface (`dolthub/driver` for Dolt).
Do not add beads-side flocks, engine introspection, storage-specific retry or
crash-recovery logic, or public SDK return types that leak driver internals.
If the boundary is too narrow, widen the interface or route the issue to the
driver instead of patching around it in beads.

A live application of this rule: `bd doctor` support for embedded mode is
enabled one subcommand at a time, each human-vetted (GH#3794). Do not lift the
embedded-mode gate in `cmd/bd/doctor.go` wholesale, and keep database-layer
checks and fixes server-gated until the driver interface covers them.

## Agent Warning: Interactive Commands

**DO NOT use `bd edit`** - it opens an interactive editor ($EDITOR) which AI agents cannot use.

Use `bd update` with flags instead:
```bash
bd update <id> --description "new description"
bd update <id> --title "new title"
bd update <id> --design "design notes"
bd update <id> --notes "additional notes"
bd update <id> --acceptance "acceptance criteria"

# Use stdin for descriptions with special characters (backticks, !, nested quotes)
echo 'Description with `backticks` and "quotes"' | bd create "Title" --description=-
echo 'Updated text' | bd update <id> --description=-
```

## Testing

Use [engdocs/TESTING.md](engdocs/TESTING.md) for the canonical commands,
test-design guidance, and PR-readiness gates.

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

## Landing the Plane (Session Completion)

**When ending a work session** (or when the user says "let's land the
plane"), you MUST complete ALL steps below. Work is NOT complete until
`git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed):
   - `make ci-pr-lint` (required zero-finding formatting and lint wrapper)
   - `make test` (and `make test-icu-path` only if you intentionally need the ICU regex path)
   - File a P0 issue if quality gates are broken
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up**:
   ```bash
   git stash clear                    # Remove old stashes
   git remote prune origin            # Clean up deleted remote branches
   ```
6. **Verify** - All changes committed AND pushed, no untracked files remain
7. **Hand off** - Choose a follow-up issue and give the user a prompt for
   the next session, e.g. "Continue work on bd-X: [issue title]. [Brief
   context about what's been done and what's next]"

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

Close with a summary for the user: what was completed this session, issues
filed for follow-up, quality-gate status, confirmation everything is pushed,
and the recommended prompt for the next session.

<!-- BEGIN BEADS INTEGRATION v:1 profile:full hash:bacef91e -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Quality
- Use `--acceptance` and `--design` fields when creating issues
- Use `--validate` to check description completeness

### Lifecycle
- `bd defer <id>` / `bd supersede <id>` for issue management
- `bd stale` / `bd orphans` / `bd lint` for hygiene
- `bd human <id>` to flag for human decisions
- `bd formula list` / `bd mol pour <name>` for structured workflows

### Sync

bd stores issue history in Dolt:

- Each write auto-commits to Dolt history
- Use `bd dolt push`/`bd dolt pull` for remote sync
- Do not treat `.beads/issues.jsonl` as the sync protocol

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and https://github.com/gastownhall/beads/blob/main/docs/getting-started/quickstart.md.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.

<!-- END BEADS INTEGRATION -->
