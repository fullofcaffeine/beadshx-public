# Query extern audit

These reports are the deterministic `goextern` fallback output for the Go
packages used by the Haxe-owned query slice. They were generated with the
haxe.go commit locked in `upstream/locks/haxe-go.json`:

```text
context
time
github.com/steveyegge/beads/internal/timeparsing
github.com/steveyegge/beads/issueops
```

The query path uses precise externs for `context.Background`, the selected
`time` and `timeparsing` functions, and `issueops.Reader.List`. The
`timeparsing` root is fallback-free. Whole-package reports for `context`,
`time`, and `issueops` also include APIs that query does not call, such as
callbacks and channels; their presence does not authorize `Dynamic` in the
application.

One handwritten Go projection remains: `readonlyfacade.ProjectQueryPage`.
The issueops report records why the full row graph is not a safe direct extern:
`IssueWithCounts` embeds an issue pointer, and the reachable issue record has
pointer, slice, map, and named-value fields that the generator deliberately
omits. The projection copies those fields only. It does not parse the query,
filter, sort, page, choose defaults, render, open a route, or write state.

Regenerate each report with `.toolchains/haxe.go/tools/goextern`, the repository
as `--dir`, `beadshx.audit` as `--haxe-package`, and a disposable or ignored
`--out` directory. Pass the corresponding file here as `--dynamic-report`.
Review generated externs and every fallback before accepting changed bytes.
