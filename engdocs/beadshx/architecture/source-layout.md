# BeadsHX source layout

The layout makes ownership visible. A directory name is not permission to move
behavior across an authority boundary.

| Root | Owner and edit policy |
| --- | --- |
| `src/beadshx/` | Authored Haxe application source. Domain and application policy belongs here. |
| `native/go/` | Hand-authored, typed Go integration islands. Each island needs a necessity statement and tests; no hidden product policy. |
| `generated/go/` | Compiler-owned disposable output. Never hand edit or use as the authored fix location. |
| `compatibility/` | Versioned manifests, scenarios, normalizers, schemas, and generated reports. Green status comes only from evidence. |
| `test/` | BeadsHX unit, semantic, parity, persistence, recovery, migration, performance, platform, and disposable fixture owners. |
| `packages/` | Neutral contracts introduced only at their milestone gate. Brew implementation is not admitted during bootstrap. |
| `caf/` | BeadsHX provider descriptors and Caf-facing assets. They contain authored intent, not live task or host facts. |
| `upstream/` | Exact locks and scripts for the pinned oracle. It is not a second mutable task authority. |
| `release/` | Release policy, packaging, provenance, SBOM, notice, and recovery machinery. |
| `engdocs/beadshx/` | Internal architecture, decisions, operations, and program evidence. Public user documentation stays under the inherited `docs/` publication contract. |

The inherited upstream Go tree remains the exact oracle and native library
baseline during early milestones. Haxe ownership moves in vertical behavior
slices; directories are not translated in bulk.
