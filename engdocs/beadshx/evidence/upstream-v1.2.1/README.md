# Upstream v1.2.1 baseline evidence

This directory contains the sanitized baseline record for
`beadshx-m00-10`. The machine-readable manifest records exact commands,
toolchains, results, skips, host qualifications, and measurements without
publishing workstation paths or personal identifiers.

Raw command logs remain under ignored `build/evidence/upstream-v1.2.1/`.
They are local diagnostic material because upstream tools print temporary and
workstation paths. Promote a raw log only after redaction and an explicit
artifact-retention decision.

## Current result

- The pinned upstream binary builds and the complete normal Go test suite
  passes on Darwin ARM64.
- The published `v1.1.2` predecessor passes upgrade and cross-version smoke.
- The complete authenticated historical migration corpus passes under its
  qualified Ubuntu 24.04 Linux/AMD64 environment: 13 versions and 14 upgrade
  routes from `v0.9.1` through `v1.1.2`.
- The repository policy lane passes under Linux ARM64.
- The active differential regression suite passes against the `v0.49.6`
  baseline. It records 74 top-level passes and 11 documented skips.
- The published `v1.2.1` prerelease has eleven assets. Its checksum table,
  Darwin ARM64 archive, contract corpus, SPDX SBOM, and attestation pass the
  recorded verification.
- The MCP and npm package gates pass from disposable source copies. The first
  MCP attempt records a transient PyPI network error before the clean retry.
- The absent `v1.2.0` release asset remains the documented reason that its
  upgrade-smoke lane cannot start.
- The 30-tag cross-version lane produced 11 passes, 18 skips, and one failure:
  `v0.55.4` correctly requires explicit migration, but the generic smoke test
  incorrectly attempts to open it directly. The authenticated explicit
  migration routes for both `v0.55.4` layouts pass.

These results establish a bootstrap baseline. They do not admit a BeadsHX
platform, release, compatibility percentage, or production migration.
Project license approval remains in `beadshx-m00-05`. Future BeadsHX release
and performance gates remain in their later milestones.
