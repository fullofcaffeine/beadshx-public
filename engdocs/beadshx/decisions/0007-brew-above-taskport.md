# ADR 0007: Brew stays above TaskPort

Status: accepted for implementation. Brew implementation is not admitted yet.

## Decision

Brew is optional selection, context, verification, closeout, recovery, and
receipt policy above neutral TaskPort and WorkContext contracts. BeadsHX core
must remain fully usable without it.

## Alternatives considered

Making Brew the database creates conflicting truth. Putting Brew policy in
BeadsHX core couples a task provider to one coordinator. Forking Caf's current
semantics creates two owners.

## Authority boundary

TaskPort providers own task operations; WorkContext owns neutral context
artifacts; Brew owns reusable coordination policy; native systems and receipts
own runtime evidence.

## Removal test and risks

A fixture must remove Brew and retain direct `bdhx` and TaskPort operation on
the same database. Reopen package placement only after a second product proves
an independent release cadence. The main risk is Brew-specific fields leaking
into neutral contracts; second-provider conformance controls it.
