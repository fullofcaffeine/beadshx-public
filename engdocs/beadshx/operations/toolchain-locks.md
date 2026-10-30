# Toolchain locks

BeadsHX admits one Linux bootstrap profile before it adds platform-specific
release profiles. The machine-readable authority is
`engdocs/beadshx/program/toolchain-locks.json`.

Run `npm run setup:haxe` on a clean checkout. Then run
`npm run verify:toolchains`. This command checks the exact shared Node, npm,
Haxe, Haxe Formatter, Lix, Go, GolangCI-Lint, pre-commit, Gitleaks, haxe.go,
and Dolt module inputs.

The setup command always runs `npm ci`. The haxe.go checkout must be clean and
must not depend on another Git object store. Go commands use `GOWORK=off` and
reject module replacements. The repository checks the installed Gitleaks
binary against its platform hash.

See `build-commands.md` for the complete BeadsHX build, test, package, and
recovery command surface.

Each hosted job checks the `linux-ci` runner profile before its lane starts.
The bootstrap job also checks every executable that generates or builds the
bootstrap. A runner-image change fails the job until a contributor reviews the
new image manifest and updates the lock.

The Linux values come from GitHub's Ubuntu 24.04 runner manifest. The lock
records the reviewed image version and review date because the manifest moves
when GitHub publishes a new image.

The Linux profile does not admit macOS, Windows, or another architecture.
Each later release profile must add its own compiler, linker, native library,
and packaging-tool locks before it can publish artifacts.

The current build uses Go 1.26.10 for its security fixes. This patch update
supersedes the initial Go 1.26.5 build pin in the port PRD. The Beads v1.2.1
compatibility target and database format remain unchanged.

Historical command and native-boundary inventories still use the original
Go version from `upstream/locks/beads-v1.2.1.json`. Their policies and evidence
record that original compiler. They must not inherit the current build pin,
or claim that old measurements came from a newer compiler.
