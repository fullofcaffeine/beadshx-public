# ADR 0006: Caf integration is a replaceable provider

Status: accepted for implementation.

## Decision

BeadsHX extends Cafetera's existing Beads integration, TaskPort, WorkContext,
and rebuildable projection owners. Caf descriptors record authored selection
intent and effect limits, never live installation, host, task, or receipt facts.

## Alternatives considered

A second Beads semantic module would duplicate ownership. Treating module
selection as installation would fabricate native facts. A graph write path
would turn a disposable projection into task authority.

## Authority boundary

Caf CML selects exact providers and policy. Native observations prove what is
installed and what happened. Task mutations route through TaskPort actions and
native readback.

## Removal test and risks

The early no-effect descriptor can be deleted without changing BeadsHX or any
database. Reopen the provider shape only against the live Caf contracts and
issues. The risk is stale parallel semantics; explicit cross-repository locks
and reuse of existing issue owners control it.
