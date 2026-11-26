# Embedded comment detail tracer

Run `bash scripts/beadshx/test-sql-error-contracts.sh --embedded-comments` after toolchain setup. `npm run test:focused` invokes this gate too. The wrapper uses a fresh marked source copy and compiler output, the pinned Go toolchain, CGO, and an isolated home/config directory. It retains a failed fixture and removes a successful one.

The observer creates the complete pinned schema inside its own marked temporary workspace. It seeds legal durable and wisp comments, including an issue-ID collision, then compares the actual native facade with authored `EmbeddedIssueDetailsReader` and `GoReadonlyStore.issueDetails` calls on the same database. Eight cases cover include/omit through both Haxe paths. The direct native store always counts durable comments and independently probes active wisps for bodies; the fixture asserts these distinct policies.

The observer is a `.go.in` template because it calls generated Haxe symbols. The runner copies it only after generation and does not generate another contract in that output tree. Ordinary `go test ./...` does not compile the template as a separate package.

The separate `--scalar-labels` mode runs the 14-case, database-free native assembly regression with its own generated output. The default SQL lane compares the direct body helper and detail/count SQL contract with independent native observations. Earlier UOW-only observations do not establish embedded-store parity.

The embedded test reads back four comment counts through the native driver after the Haxe reads. This detects changed cardinality, not every possible filesystem or database effect. It does not qualify edge hydration, server attachment, or a complete release path.
