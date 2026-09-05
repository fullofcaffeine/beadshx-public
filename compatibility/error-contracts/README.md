# Error compatibility plan

BeadsHX classifies a process result from the complete observation, not from
the exit number alone. The observation includes the command profile, scenario,
exit status, stdout, stderr, and persistent-state result.

This rule matters because pinned Beads uses the same number for different
meanings. Exit 1 covers most failures. Exit 2 can mean a list-flag conflict, a
row-cap refusal, or a sync conflict. Exit 0 can include a partially successful
batch that changed only some requested issues.

[`plan.json`](plan.json) records:

- a closed external class vocabulary that does not expose Go error types;
- the fixed and command-local exit observations in Beads v1.2.1;
- the inherited stdout and stderr routing mechanisms;
- representative semantic, usage, conflict, cancellation, and partial-result
  cases; and
- explicit storage, deadline, internal-defect, and signal gaps.

Exact diagnostic bytes and JSON shapes remain with the M02-02 output plan.
M02-03 interprets those observations. Candidate execution and post-state
comparison remain with M06. A pending candidate or gap is not compatibility
coverage.

## Local validation

Run:

```sh
npm run test:error-contracts
```

The check reads repository files and the local Git object database. It does
not require `gh`, GitHub Actions, Docker, or network access.
