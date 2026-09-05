# Cafetera reconciliation baseline

Baseline commit: `c9723630b45bc0ed422fcfbab6b05ddf246d3bc0`.

The live checkout contained pre-existing source, documentation, test, and
tracker changes. BeadsHX did not modify it. Its pinned Beads client passed the
read-only compatibility preflight before issue inspection.

| Existing issue | Current classification | BeadsHX action |
| --- | --- | --- |
| `cafetera-4vzs.80` | Confirmed unresolved and unclaimed. The typed writer seam exists, but the production reader/runner and one native work loop remain open. | Reuse this issue in M19 and add BeadsHX provider evidence. Do not create a competing Caf issue. |
| `cafetera-4vzs.81` | Confirmed unresolved and blocked by `.80`. | Reuse for the CML-composed Brew workflow after the M19 provider gate. |
| `cafetera-4vzs.82` | Confirmed unresolved and blocked by `.81`. | BeadsHX can add provider evidence, but cannot satisfy the required genuinely different task authority by itself. |
| `cafetera-4vzs.86` | Confirmed unresolved and unclaimed. | Keep the clean sequential work-loop owner; relate BeadsHX only when the integration reaches dogfood. |
| `cafetera-o0sg` | Confirmed unresolved native Beads defect. | Reproduce against the pinned upstream binary before any fix. Route a general fix through an upstream-facing Beads change, not a Caf workaround. |

Current architecture already owns TaskPort, WorkContext, Brew policy, a
read-before/write/read-after Beads writer seam, and rebuildable projections.
BeadsHX must extend those owners and preserve the authority split. It must not
copy their semantics into a second Caf module or move live task fields into
CML or graph state.
