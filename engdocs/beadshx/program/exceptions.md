# Compatibility exception policy

The completion definition in `beadshx-complete-port-prd.md` is the program
contract. Missing evidence is not a green result, and a milestone cannot infer
completion from a successful build or a smaller workflow profile.

An exception must be a visible compatibility divergence. It records:

- affected command, capability, state, mode, and platform;
- user and migration impact;
- reproducing fixture and tests;
- reason the pinned upstream behavior is not implemented unchanged;
- requester disposition and decision date;
- owner, review trigger, and removal or renewal condition;
- rollback and upstream fallback procedure.

Exceptions live in the compatibility manifest and generated report. They do
not hide an unknown or delegated surface, broaden another platform's evidence,
or waive production-data safety, native readback, licensing, provenance, or
recovery requirements.
