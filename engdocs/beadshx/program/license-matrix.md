# BeadsHX license matrix

Status: approved by the requester on 2026-08-15 for implementation and future
release qualification. The durable decision record is `beadshx-m00-05`.
This plan does not replace legal advice for a later distribution change.

| Code or artifact class | License owner | License and files | Generated-output treatment | Required release artifacts | Automated verification |
| --- | --- | --- | --- | --- | --- |
| Pinned Beads source and adapted tests | Beads contributors | MIT in `LICENSE`; dependency notices in `THIRD_PARTY_LICENSES` | Adapted Haxe or Go remains MIT and keeps upstream attribution. | Both files, exact upstream commit, source diff | `check-license-plan.sh` checks the notices and source lock. |
| BeadsHX-authored Haxe and native Go | BeadsHX contributors | MIT in `LICENSE` | Generated forms remain MIT with their source attribution. | Root license and authored-source inventory | `check-license-plan.sh` checks the BeadsHX grant. |
| haxe.go compiler | haxe.go copyright owner | GPL-3.0-only in the locked compiler repository | The compiler stays a build tool and is not part of a BeadsHX product archive. | Compiler source reference, GPL text, exact compiler commit | The source lock check fixes the admitted compiler commit. |
| haxe.go runtime and emitted support | haxe.go copyright owner | Generated-output MIT grant from the locked compiler policy | Generated projects contain `LICENSES/HAXE-GO-GENERATED-MIT.txt`. | Exact notice bytes and policy verification | The check compares the generated notice SHA-256 with the approved hash. |
| Haxe standard-library-derived output | Haxe Foundation | MIT notice from Haxe 4.3.7 | Generated projects contain `LICENSES/HAXE-STDLIB-MIT.txt`. | Haxe version and exact notice bytes | The check compares the generated notice SHA-256 with the approved hash. |
| Vendored Reflaxe compiler source | Reflaxe contributors | MIT at compiler source commit `430b4187a6bf4813cf618fc3a73ccf494a2ab9f5` | Reflaxe is not copied or lowered into the generated project. | Compiler vendor manifest and license bytes | The locked haxe.go policy owns its vendor and release checks. |
| Native Go dependencies, Dolt, SDKs, and tools | Their respective copyright owners | Each dependency keeps its declared license. | Linking does not replace dependency license duties. | Source and binary SBOMs, license inventory, notices | Later release gates must compare the inventory with the built module graph. |
| BeadsHX binaries and archives | Combined governed inputs | MIT for BeadsHX and Beads portions, plus all dependency terms | Archives exclude the GPL compiler and include generated-output notices. | Same-commit build, notices, SBOMs, checksums, attestations, rollback guide | Release admission must fail if any listed artifact or notice is absent. |

The existing haxe.go generated-output approval applies only to the scope and
digest governed by haxe.go. Any changed compiler scope must pass that
repository's approval and verification process again.

Run `scripts/beadshx/check-license-plan.sh` after generation. This bootstrap
check proves the fixed source and generated-notice boundaries. The later
release gate owns complete dependency inventories, SBOMs, and archive checks.
