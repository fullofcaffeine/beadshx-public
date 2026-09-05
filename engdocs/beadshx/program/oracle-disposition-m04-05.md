# Oracle disposition for BHX-M04-05

## Outcome

Proceed with the catalog-backed nominal design after the current blockers clear.
Do not start BeadsHX implementation from this disposition.

The haxe.go change must use a clean worktree and a reviewed pull request.
BeadsHX can resume this boundary only after that pull request merges and the merged revision is pinned here.

## Local baseline

This disposition processes Oracle request `orq_20260815T184057Z_155e5b95`.
The ledger records project `haxe.go`, agent `beadshx-port-maintainer`, and plan mode.
It requires local model `gpt-5.6-sol` with reasoning level `xhigh` or higher.
The response ended with the recorded completion hash `f2eb17b335c54e21b42d18d71aa4a8cee5e0ac8d25ea75bddc52e2d0261319c4`.

The local review used BeadsHX revision `b7474ec802d4fe812e158f1bb0ae98668ef6afbd`.
It used haxe.go revision `990d78bcf7a8641ef589cd230b7d69d59beadb84`.
Both revisions matched their remote default branches during the review.

`beadshx-m04-05` remains open and blocked by `beadshx-m04`.
That milestone remains blocked by `beadshx-m03`.
The matching haxe.go task, `haxe_go-vfp.8.4.1`, remains in progress with its recorded upstream owner.
No open pull request contained the requested method-set work during this review.

Current `goextern` behavior confirms the reported gap:

- One invocation loads one Go package.
- The declaration model has no package identity, receiver shape, proof reference, or `implements` list.
- Method discovery combines the method sets of `T` and `*T` into one Haxe surface.
- Type mapping removes pointer identity and maps external named types to `Dynamic`.
- Multi-result carrier names depend on the owning type and method.
- The existing `fmt.Fprint` test requires `io.Writer` to remain an `external_named_type` fallback.

Current haxe.go behavior also confirms the useful starting point.
Imported extern classes map to Go pointers, and imported extern interfaces map to Go interfaces.
Ordinary lowering preserves a compatible source expression without a conversion.

## Oracle claim matrix

| Oracle claim | Disposition | Local evidence and consequence |
|---|---|---|
| Use `go/types` as the method-set authority. | Retained | Go receiver rules, embedded methods, and package-private identity cannot be reconstructed safely from rendered strings. |
| Give Haxe a generated nominal `implements` edge. | Retained | Haxe 4.3.7 accepts a matching extern relationship and rejects a mismatched method before target lowering. |
| Use an immutable multi-package catalog before separate package emission. | Retained | Current one-package emission has no shared authority for `bytes.Buffer` and `io.Writer`. The catalog must stay read-only during emission. |
| Make the catalog mandatory for all native extern relationships. | Retained with a scope guard | It is mandatory for generated proof claims and verified authored claims. Existing authored externs remain compatible unless strict catalog mode is selected. |
| Validate proof metadata in haxe.go before Go generation. | Retained | A false `*time.Time -> io.Writer` claim currently reaches the post-generation Go build. Catalog preflight must reject a proof claim earlier. |
| Lower a validated assignment as the original expression. | Retained | A local probe emitted direct `return buffer` for `*bytes.Buffer -> io.Writer`, and `go test` accepted it. |
| Canonicalize multi-result carriers across packages. | Retained | Owner-local carrier names make equal Go method results nominally different in Haxe. The first slice must share the Writer carrier. |
| Use an implicit proof abstract. | Rejected | It adds a conversion surface and risks an incorrect pointer shape for interface carriers. |
| Add structural Haxe interface typing. | Rejected | It cannot preserve Go receiver shape or package-qualified method identity. |
| Record complete source provenance for all loaded packages in the first slice. | Deferred in part | The first slice needs toolchain, build context, module identity, and selected structural API digests. Broader build-input reporting belongs with existing build-report work. |
| Generate every satisfying concrete and interface pair. | Rejected | A manifest must request each public relationship. This keeps the generated API bounded and reviewable. |
| Admit Go value-shaped extern classes now. | Deferred | Current generated extern classes represent pointers. Value representation belongs to `BHX-M04-06`. |
| Add broad support for generics, callbacks, channels, and anonymous interfaces. | Deferred | Separate M04 tasks own these boundaries. Unsupported cases must remain in the deterministic fallback report. |
| Implement the complete plan before BeadsHX resumes this boundary. | Retained | The required haxe.go pull request must merge first. BeadsHX then pins the merged revision and repeats its boundary inventory. |

## Integrated plan

The first haxe.go pull request must prove one complete vertical slice.
Internal commits can separate these stages, but the merged result must include all required contracts.

1. Add committed failing contracts for `*bytes.Buffer -> io.Writer` and the negative receiver cases.
2. Add a versioned catalog manifest for selected packages, named types, native shapes, and requested proof pairs.
3. Load the selected packages together and use `types.Implements` for separate `T` and `*T` proofs.
4. Store structural type facts, package identity, build context, selected API digests, and content-addressed proof identifiers.
5. Emit shared carrier types once from the catalog phase.
6. Emit typed `io.Writer`, typed `fmt.Fprint`, and the proven pointer-shaped `bytes.Buffer implements io.Writer` edge.
7. Keep package emission deterministic and independent of package order.
8. Add haxe.go catalog preflight for proof-bearing metadata and for explicit strict catalog mode.
9. Add an immutable assignment plan that validates exact native identities and returns the existing `GoExpr` unchanged.
10. Preserve the no-catalog fallback report for unsupported and legacy boundaries.
11. Prove positive runtime behavior, receiver differences, signature mismatches, package identity, embedded interfaces, metadata drift, and order independence.
12. Update the generated-file guidance so proof-bearing files are regenerated instead of edited.

The implementation must not recognize `bytes`, `io`, `fmt`, or Beads-specific names in compiler logic.
The canonical Writer case is a fixture for a general package-qualified method-set rule.

The pull request needs a second architecture review because the upstream task uses `thinking:xhigh`.
After the review passes, merge the pull request before any BeadsHX source work uses this feature.

## Verification and unresolved gaps

The local processor ran these checks:

- `go test ./...` in `haxe.go/tools/goextern` passed.
- Haxe 4.3.7 accepted a matching extern class and extern interface relationship.
- Haxe 4.3.7 rejected the same relationship when the method return type differed.
- haxe.go emitted direct `return buffer` for a typed `*bytes.Buffer -> io.Writer` probe.
- `go test ./...` accepted that generated Go probe.
- A false `*time.Time -> io.Writer` claim failed only during haxe.go post-generation Go compilation.

These checks validate the route, but they are temporary probes rather than committed regression tests.
The Oracle response proposed the larger fixture matrix and full quality commands.
Those proposed checks have not run because the implementation does not exist.

The exact metadata names, catalog paths, and support package name remain implementation choices.
They do not block the semantic plan.

Implementation is blocked for two current reasons:

- The upstream haxe.go task already has a recorded owner, and no handoff authorizes a branch takeover.
- The BeadsHX milestone graph blocks M04 work until M03 completes.

No haxe.go source file, branch, or pull request changed during this reconciliation.

Processor: `gpt-5.6-sol`, reasoning level `xhigh`.
