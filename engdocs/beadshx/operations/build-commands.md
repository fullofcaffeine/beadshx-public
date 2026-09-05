# BeadsHX build commands

Use the `npm` commands in this document for BeadsHX work. The inherited
Makefile still builds and tests the unchanged upstream program. It is not the
BeadsHX command authority.

Each BeadsHX command is non-interactive. It writes one JSON result to standard
output. Human-readable tool output goes to the ignored
`build/evidence/commands/<command>.log` file.

```json
{"schemaVersion":1,"command":"build","status":"pass","exitCode":0,"log":"build/evidence/commands/build.log"}
```

A failed command uses `status: "fail"`, records the nonzero exit code, and
returns that same exit code to the caller.

## Command reference

| Command | Purpose |
| --- | --- |
| `npm run setup:haxe` | Install the exact Haxe, Lix, and haxe.go inputs. |
| `npm run bootstrap` | Verify locks and policy, generate Go, build the development binary, and run the bootstrap checks. |
| `npm run generate` | Generate disposable Go source from authored Haxe. |
| `npm run build` | Format, test, and compile the generated Go module. |
| `npm run build:oracle` | Build the pinned upstream `bd` oracle in a temporary Git worktree. |
| `npm run inventory:commands` | Regenerate the complete pinned v1.2.1 command, flag, and source-obligation inventory. |
| `npm run test:inventory` | Rebuild the inventory in clean Linux profiles and reject drift or incomplete coverage. |
| `npm run test:output-contracts` | Validate the pinned command inventory, inherited upstream JSON corpus, and explicit compatibility gaps. |
| `npm run test:error-contracts` | Validate the profile-scoped exit observations, external error classes, diagnostic routes, and explicit execution gaps. |
| `npm run test:storage-contracts` | Validate command capability ownership, backend transaction boundaries, and the source-derived direct-SQL census. |
| `npm run test:schema-migrations` | Validate the two migration lanes, repair graph, semantic reversibility, and generated test-pair closure. |
| `npm run schema:migration-pairs` | Generate the 128 pinned migration test pairs as JSON without changing a database. |
| `npm run test:focused` | Run the focused bootstrap, toolchain rejection, and data-safety tests. |
| `npm run test:generated` | Regenerate Go and detect byte drift against the committed ownership fixture. |
| `npm run test:identity` | Reject upstream impersonation, identity drift, or an early `bd` alias. |
| `npm run test:caf-intent` | Validate the unselected, non-executing Caf provider intent and reject observed facts. |
| `npm run test:parity` | Compare only the admitted development identities. This command does not claim behavior parity. |
| `npm test` | Run the complete current BeadsHX bootstrap, oracle, and identity-parity suite. |
| `npm run ci:local` | Run the same seven repository lanes that GitHub Actions calls. This command does not require GitHub or `gh`. |
| `npm run format` | Format authored Haxe and Go in the native and disposable generated trees. |
| `npm run lint` | Check BeadsHX shell syntax and run the complete bootstrap policy check. CI adds locked ShellCheck analysis. |
| `npm run package` | Create the deterministic development bootstrap ZIP. It is not a release package. |
| `npm run clean` | Remove generated Go, BeadsHX binaries, and the development ZIP. |
| `npm run hooks:install` | Install the versioned repository hooks after it checks the pinned Beads client and developer tools. |

The package is written to
`build/packages/beadshx-development-bootstrap.zip`. It contains the
development binary, generated Go source, licenses, source locks, and toolchain
locks. Its fixed entry order and timestamps make repeated packages identical
when their inputs are identical. It does not identify itself as upstream
`bd`, and it is not release or compatibility evidence.

`npm run ci:local` stores one log and one lock report for each lane. It does
not require `gh`, GitHub credentials, or a hosted runner. A clean setup still
downloads the locked npm, compiler, and scanner inputs.

The supported local CI path uses Bash on Linux or macOS. Native Windows CI is
not part of the bootstrap contract.

Command inventory generation also requires Docker. It compiles the exact
Linux/AMD64 CGO and non-CGO probes in the digest-pinned Go container. It then
runs the probe binaries with networking disabled and with empty, monitored
HOME, XDG, temporary, and working directories. Dependency and build caches
live under the operating system user-cache directory, outside the repository;
they cannot enter package discovery or the committed inventory.

Equivalent `make beadshx-*` targets exist for contributors who use Make. Use
`make beadshx-ci-local` for the local CI path. The `npm` names are the canonical
documented surface.
