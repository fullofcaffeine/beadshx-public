# Output compatibility plan

BeadsHX uses the pinned Beads implementation as its behavior oracle. It does
not maintain a second, hand-written description of every output field.

Three inherited assets have distinct jobs:

- The M02-01 command inventory defines the complete command and output-channel
  denominator.
- `cmd/bd/protocol/testdata/corpus` supplies canonical flat and envelope JSON
  examples for the core lifecycle.
- `tests/oracle-a` runs the same process scenarios against a reference and a
  candidate. BeadsHX will use it when the Haxe candidate implements a slice.

[`plan.json`](plan.json) pins these authorities, defines three field classes,
and names six representative presentation cases. The cases cover plain text,
color and hyperlinks, paging, separate stdout and stderr terminal detection,
prompts, and shell completion. They do not duplicate upstream output bytes.

Five presentation cases remain pending until M06 runs them against the pinned
binary and a real Haxe-owned candidate path. The `legacy-json-stderr-notice`
case is complete: the parity smoke lane gives stdout a pipe and stderr a
pseudo-terminal, then verifies the exact notice and its
`BD_JSON_ENVELOPE=1` suppression against both binaries. A pending case or gap
is not compatibility coverage.

## Adding a Haxe slice

1. Reuse an upstream corpus or Oracle A scenario when it describes the
   behavior.
2. Add one focused scenario only when the upstream assets do not expose the
   required behavior.
3. Compare exit status, stdout, stderr, and persistent state against the pinned
   `bd` binary.
4. Add a normalizer only for one named volatile value. Do not remove unknown
   fields, reorder meaningful arrays, or hide output.
5. Mark a gap complete only after the differential case runs against a real
   Haxe-owned candidate path.

Mixed-stream error classification remains with M02-03. Terminal execution,
signals, state comparison, and server-only behavior remain with M06.

## Local validation

Run:

```sh
npm run test:output-contracts
```

The check reads only repository files and the local Git object database. It
does not require `gh`, GitHub Actions, or network access.
