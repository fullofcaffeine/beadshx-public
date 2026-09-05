# Storage capability plan

BeadsHX maps each pinned Beads command to the smallest application capability
that owns its behavior. Backend-specific SQL, staging, retry, and publication
mechanics remain separate from that semantic map.

This separation is important for the Haxe port. Haxe code can depend on typed
capabilities such as issue lifecycle or graph relations without copying the
large Go storage interface. A target adapter can then implement those
capabilities with classic Dolt, embedded Dolt, or a unit of work while
preserving that backend's transaction behavior.

[`plan.json`](plan.json) records:

- one profile for every command root in the pinned command inventory;
- a closed set of application capabilities and transaction requirements;
- the distinct commit, retry, journal, and hook behavior of all three
  registered storage legs; and
- a source-derived census of direct SQL and host-storage escape points.

The profiles are planning boundaries, not compatibility claims. A profile with
more than one transaction requirement contains flag- or subcommand-dependent
behavior that a later vertical slice must narrow. Every explicit gap remains
pending.

## Local validation

Run:

```sh
npm run test:storage-contracts
```

The check rebuilds command-root coverage and the direct-SQL census from the
pinned Git commit. It does not require `gh`, GitHub Actions, Docker, or network
access.
