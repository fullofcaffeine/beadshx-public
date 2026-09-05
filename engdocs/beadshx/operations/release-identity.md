# Release identity policy

BeadsHX uses a separate identity during development. The development binary is
`bdhx`, and the exact upstream oracle is `bd-upstream`. A development command
must never present itself as upstream `bd`.

The machine-readable policy is `release/identity-policy.json`. It records the
current names, version rules, compatibility source, module paths, build
metadata, user-agent format, and alias conditions.

## Module paths

Early compatibility work keeps the inherited module
`github.com/steveyegge/beads`. The standalone bootstrap tracer uses the
disposable module `github.com/fullofcaffeine/beadshx/generated/bootstrap`.

Before public 1.0, the release task must select one final policy. A binary-only
release can retain the inherited module for compatibility. A published library
must migrate once to `github.com/fullofcaffeine/beadshx`.

The module migration must be one isolated change. It must update imports as one
unit and must not contain behavior changes. Normal port changes must not rename
the module.

## Versions and build metadata

Development packages use `0.0.0-development`. Public versions use SemVer 2.0.0,
and the first admitted public major version is 1.

Release metadata must identify both source lines. It includes the BeadsHX
commit and the exact upstream compatibility version and commit. It also
includes the haxe.go commit, Haxe version, Go version, and dirty-worktree state.

M06 owns the runtime command that prints this metadata. This M01 policy does
not add a version command or claim command compatibility.

## User-agent identity

BeadsHX does not emit a network user agent during bootstrap. A future network
client starts its user agent with `BeadsHX/<version>`. It includes the token
`compat/Beads-v1.2.1+634cbbc4bc58` and must not use an upstream product prefix.

## Optional `bd` alias

The `bd` alias is forbidden during development and initial release work.
`BHX-M21-07` can authorize an explicit alias option only after these tasks are
complete:

- `BHX-M21-03`: non-critical repository soak.
- `BHX-M21-04`: selected daily-workflow soak.
- `BHX-M21-05`: primary-workflow cutover and rollback drill.
- `BHX-M21-06`: public 1.0 release.

The option must be reversible and must continue to report BeadsHX identity.
It must also preserve the direct `bd-upstream` fallback. The upstream fallback
prevents an alias change from stranding an existing Beads workspace.
