# Cross-repository program ledger

The file `ledger.tsv` is the canonical decision trail for the BeadsHX port.
Each row records one decision or checkpoint and points to its strongest
evidence. The ledger is append-only. A later row supersedes an incorrect or
outdated row.

## Required references

Each evidence cell contains these references:

- `issue:` names the BeadsHX issue that owns the work.
- `commit:` names the BeadsHX commit that contains the change.
- `artifact:` names one repository file that proves the result.

Use `commit:WORKTREE` until the change has a commit. A worktree row must use
`state:worktree`. After a commit, append a new row with its exact commit and
the final disposition. Do not edit the earlier worktree row.

The evidence cell can also contain `source-commit:` for an upstream, compiler,
or integration source. This value does not replace the BeadsHX commit.

## Result states

Each result cell contains a state and a disposition. The state reports whether
the evidence is still in the worktree or exists in a commit. The disposition
records the program decision, required action, or explicit blocker.

The bootstrap check validates the TSV shape, reference fields, formula safety,
and artifact paths. It rejects a committed state that points to `WORKTREE`.
It also rejects a worktree state that claims an exact commit.

Legal approval, compatibility waivers, release admission, and other requester
decisions remain open until the requester records an explicit disposition.
