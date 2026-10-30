# Security Dependency Exceptions

MCP exception reviewed: 2026-10-30. The website section retains its historical evidence.

This file records dependency advisories that are accepted temporarily because
the affected code is outside the supported execution path. Runtime dependencies
require a separate security review, an owner, and an expiry date.

## Website build toolchain

Scope:

- `website/package.json`
- `website/package-lock.json`
- Docusaurus, webpack, Mermaid, and related static-site build tooling

Status:

- `npm audit --omit=dev` is clean.
- The historical Go audit passed on 2026-07-24 with Go 1.26.5 after the
  `golang.org/x/text` v0.39.0 update. This is not current security evidence;
  the 2026-10-30 dependency audit found newer Go advisories.
- A full `npm audit` still reports build-time advisories through the
  Docusaurus/webpack toolchain, primarily `serialize-javascript`, `uuid`,
  `sockjs`, and transitive Docusaurus packages.

Risk decision:

The website is built into static files and deployed to GitHub Pages. The
production site does not run a Node.js server or load these Node packages at
runtime. The dependencies have been moved to `devDependencies` so production
audits track the actual runtime surface.

Required controls:

- `npm audit --omit=dev` for `website/` must remain clean.
- The Docusaurus dev server must not be exposed publicly.
- Renovate must remain enabled for npm and GitHub Actions updates.
- Full audit findings must be reviewed before each website release and whenever
  Renovate proposes a Docusaurus or webpack-family update.
- Remove this exception when upstream Docusaurus resolves the remaining
  transitive build-tool advisories without a downgrade.


## MCP: dnspython on Python 3.10

- Advisory: [CVE-2026-114605 / GHSA-45c3-73f7-pv4m](https://github.com/rthalley/dnspython/security/advisories/GHSA-45c3-73f7-pv4m).
- Scope: `integrations/beads-mcp`, using its documented `beads-mcp` stdio entrypoint.
- Affected dependency: `dnspython` 2.8.0 on Python 3.10 only.
- Owner: repository maintainer (`fullofcaffeine`).
- Expiry: 2026-11-30 UTC. Resolve the dependency or make an explicit Python
  support decision before this date. Do not renew this exception automatically.
- Tracking: [dependency alert 88](https://github.com/fullofcaffeine/beadshx-public/security/dependabot/88).
  Keep the alert open until the affected dependency is removed or patched.

The advisory concerns excessive CPU use when parsing crafted DNS wire messages.
The fixed 2.9 series requires Python 3.11 or later. The package still supports
Python 3.10, so its lock selects 2.8.0 there and 2.9.1 on newer Python versions.
Package metadata enforces these separate minimum versions for wheel and source
installs, which do not read `uv.lock`.

The security review found no DNS parsing or email-deliverability call in the
first-party MCP code. `server.py` explicitly starts the stdio transport, with
no authentication provider. The dependency path to dnspython runs through
FastMCP, Pydantic's email support, and email-validator. Pydantic 2.13.4 calls
`validate_email(..., check_deliverability=False)`; email-validator imports the
DNS deliverability code only when that check is enabled. This supports an
exception for this execution path. It does not fix the vulnerable dependency.

Validation of the reviewed dependency graph:

- `pip-audit` 2.10.1 found no advisories in the full Python 3.14 dependency set.
  On Python 3.10, it found only the dnspython advisory above.
- The built wheel installed on Python 3.10.20. Its metadata rejected a
  dnspython 2.6.1 constraint. The installed stdio executable completed MCP
  initialization and returned all 18 tools in a fresh temporary workspace.
- Independent agent review checked the dependency path, transport selection,
  conditional version floors, and exception limits.

Before adding DNS parsing or email-deliverability checks, reopen the review.
Other transports, authentication deployments, and dependency changes that alter
this path also invalidate this exception. Do not suppress the alert
or treat this document as approval to process untrusted DNS messages.
