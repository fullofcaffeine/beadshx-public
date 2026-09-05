# Caf provider assets

Caf-facing descriptors record source identity, capabilities, effect upper
bounds, fallback, and evidence expectations. They do not claim installation,
activation, host state, task state, command success, or receipt success.

`providers/beadshx-task-port.intent.json` is authored intent for a future Caf
provider candidate. It is not a Caf module manifest or provider selection. No
runtime or package input reads it. Delete the file and BeadsHX behavior stays
the same.

Run `npm run test:caf-intent` to validate this boundary. The check also rejects
unknown effects, observed state, local paths, and any build reference to the
descriptor.
