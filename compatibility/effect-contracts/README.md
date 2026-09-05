# Native effect contracts

BeadsHX keeps host effects separate from storage semantics. Authored Haxe owns
the command decision, ordering, consent, and user-visible result. A narrow Go
adapter performs native operations. Git, Dolt, hooks, helpers, and remote
services keep their own delegated ownership.

[`plan.json`](plan.json) is the compact compatibility contract. It contains one
record per semantic effect, not one record per syscall. Each record names its
rollback rule, recovery action, credential policy, process policy, test seam,
observer, platform profile, and pinned-source evidence. The 13 command profiles
from the storage plan bind those effects into ordered recipes.

Static source counts are drift alarms only. They ensure that broad classes of
native calls do not change silently at the pinned commit. Runtime traces and
platform qualification remain explicit later gates; a source search is not
treated as behavioral proof.

## Local command

Run the contract check without GitHub, Docker, or network access:

```sh
npm run test:effect-contracts
```

The check reads the pinned Git objects and the existing command and storage
plans. It does not execute Beads, contact a remote service, or alter user data.
