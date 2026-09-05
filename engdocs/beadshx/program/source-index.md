# BeadsHX authority source index

This index records the authority material reviewed for the initial BeadsHX
bootstrap. A source lock identifies evidence; it does not promote a proposed
decision to an approved release claim.

## Beads compatibility source

Reviewed at commit `634cbbc4bc580fa5124f63fdf65d137a46d5b4ff`
(`v1.2.1`):

- `AGENTS.md` and `AGENT_INSTRUCTIONS.md`: inherited development, issue,
  storage, PR, build, and session rules.
- `engdocs/PROJECT_CHARTER.md`: Beads owns issue-tracking primitives; Dolt owns
  storage-engine behavior; orchestration remains above Beads; schema changes
  are not the default extension mechanism.
- `engdocs/INTEGRATION_CHARTER.md`: integrations translate external trackers
  into Beads concepts and do not become cross-tracker orchestration.
- `engdocs/TESTING.md`, `engdocs/LINTING.md`, and `scripts/README.md`: use the
  smallest faithful test first, repository-owned wrappers, isolated temporary
  state, and the required lint contract.
- `CONTRIBUTING.md`: keep changes focused, preserve contributor work and
  attribution, and do not include tracker database state in PRs.
- `SECURITY.md`: treat imported content as untrusted, keep credentials out of
  artifacts, and preserve the storage and integration trust boundaries.
- `RELEASING.md`: release evidence is multi-channel, tag-bound, reversible,
  and must be verified rather than inferred from a build.
- `docs/architecture/index.md`: Dolt is the native task-data authority and
  graph/history store; JSONL is interchange, not the operational database.

The sibling `../beads` checkout was also inspected at live commit
`185b339be6d5bf7553dc4af0e8a535055f02de4e`. It contained unrelated untracked
Repomix artifacts and had no reviewed Beads toolchain pin, so its live tracker
was not opened or mutated.

## haxe.go compiler source

Reference release: `v0.54.0` at
`92d458e760a30bcb57f2cefb6202f0996fe1ac71`.

Live implementation baseline: `990d78bcf7a8641ef589cd230b7d69d59beadb84`.
The checkout was dirty before this program and must not be used directly for
BeadsHX compiler edits.

Required BeadsHX compiler revision: `c1e3333d2ce358b451e69b2b1530030bc4083dd5`.
This revision includes the digest-owned existing-module transaction and
gofmt-stable compiler output required for the Haxe-authored `bdhx` entry point,
portable `Array.slice` lowering needed by CLI argument parsing, terminal
`try`-return lowering needed by Haxe-owned filesystem reads, and inherited
generic interface-method lowering, portable `Array.concat` and `Array.indexOf`
lowering, imported extern method-value selector mapping, and Haxe-facing ABI
normalization for captured native string methods needed by typed Haxe query
capabilities.
The current revision also emits exported Go struct fields and follows supported
named-type dependencies across package boundaries. It preserves shared output
ownership, fixes unused imports exposed by the cross-package tracer, and
preserves struct and named-scalar value parameters plus single and tuple value
results at generated extern boundaries. It also preserves concrete anonymous-
record values returned through erased generic map-iterator closures, which is
required by the Haxe-owned `ready --gated` command path.
It now also widens proven native Int32 expressions without redundant generated
conversions and carries source-owned rationale for ordinary file modes that
intentionally respect the process umask.
It also preserves Go value-string slices through the exact
`go.NativeStringSlice` extern, including reads, writes, literals, and generated
bindings for exported `[]string` APIs. This is required by the Haxe-owned
dependency-read path without changing the legacy pointer-string slice ABI.
It also records the reusable full-port ownership boundary: first-party Go
application packages are porting sources, while Go standard-library and
independent third-party packages are precise extern targets. Reusable interop
gaps must be fixed in haxe.go before a consumer retains native glue.
Those changes were reviewed and merged through reflaxe.go PRs #28, #29, #36,
#38, #39, #41, #42, #43, #45, #46, #47, #48, #49, #53, and #54.

Reviewed current authority:

- `AGENTS.md` and `.beads/README.md`: test-first compiler work, typed native
  boundaries, generated-output governance, exact tracker synchronization, and
  isolated worktree/PR delivery.
- `README.md`, `docs/testing-strategy.md`, and
  `docs/portable-canonical-contract.md`: separate portable, Go-native,
  runtime, tooling, and release claims; prove behavior through the correct
  evidence owner.
- `docs/toolchain-policy.md`: Haxe 4.3.7 and Go 1.26.5 are approved exact
  toolchain pins for the relevant line.
- `LICENSING.md`, `license-policy.json`, and `SECURITY.md`: the compiler stays
  GPL-3.0-only; approved generated/runtime portions have separate distribution
  terms; publication and security gates fail closed.
- `docs/release-version-policy.md` and
  `docs/release-readiness-checklist.md`: release artifacts and claims must come
  from the exact admitted source and evidence.

The pinned haxe.go Beads client passed its read-only compatibility preflight.
Searches found no live issue titled for BeadsHX, existing-module mode,
caller-owned `go.mod`, generated import manifests, or native-boundary support.
Before any compiler implementation, search source, history, and open PRs again
and create or update the narrowest live haxe.go issue.

The bootstrap consumes the exact live implementation commit as a clean source
checkout. A raw Git Haxelib install exposes only `src/` and therefore does not
stage haxe.go's canonical `std/go/_std` target overrides. The setup command
reuses objects from `../haxe.go` when available, otherwise clones the same
remote commit, and supplies the source-checkout classpaths explicitly. This is
an integration-mode constraint, not a compiler code-generation defect.

## Cafetera integration source

Reviewed at live commit `c9723630b45bc0ed422fcfbab6b05ddf246d3bc0`.
The checkout was already dirty and remains untouched by this bootstrap.

- `AGENTS.md`, `cafetera-bootstrap-prd.md`, and
  `cafetera-bootstrap-v4.md`: CML owns authored intent, native systems own
  mutable native facts, actions request effects, receipts witness effects, and
  graph views remain rebuildable projections.
- `docs/architecture/task-port-and-brew.md`: TaskPort is the narrow neutral
  task boundary; Beads stays the task authority; Brew is optional policy above
  TaskPort and WorkContext.
- `docs/architecture/work-context-v0.md`: WorkContext records authored context
  policy and derived exact context evidence without owning tasks or sources.

The Cafetera Beads toolchain and read-only database preflight passed. The live
issues `cafetera-4vzs.80`, `.81`, `.82`, `.86`, and `cafetera-o0sg` were open
and unclaimed when inspected. BeadsHX must extend those owners rather than
create competing Caf tasks.

## Program sources

- `beadshx-complete-port-prd.md`: proposed program specification.
- `beadshx-complete-backlog.json`: machine-readable milestone/task source.
- `beadshx-prd-sha256.txt`: verified hashes for both files.

The PRD remains proposed where it requires a legal, publication, release,
platform-admission, or other explicit requester decision. Bootstrap artifacts
must not silently turn those decisions into approval.
