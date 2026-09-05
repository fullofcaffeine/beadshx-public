# Daily workflow compatibility profile

This directory defines the first useful Beadshx compatibility slice. D0 is the
small set of commands needed for normal repository maintenance. It is a work
order, not a smaller compatibility promise. Every command in the pinned Beads
inventory remains required.

`profile.json` uses only command and flag IDs from the M02-01 inventory. It also
links D0 to the output, error, storage, and effect contracts that already own
those behaviors. The profile does not copy their definitions.

The usage evidence is deliberately reduced. It records a source class, dates at
coarse resolution, recognized command names, counts, and the resulting ranking.
It does not contain raw history, arguments, issue IDs, paths, free text,
environment values, URLs, tokens, or unmatched lines. Recompute a future review
with the same privacy rule.

The proposed policy puts `sync` in D1. Backup is also a D1 command, but a verified
recoverable backup is required before any dogfood write stage. Canonical command
and flag names gate D0; aliases and short flags stay in the full compatibility
scope. Automation and JSON output come first, while selected human-readable
output cases remain part of D0.

Run the focused check locally:

```sh
npm run test:daily-workflow
```

Add `--require-approved` when the repository-owner decision is required:

```sh
./scripts/beadshx/test-daily-workflow.sh --require-approved
```
