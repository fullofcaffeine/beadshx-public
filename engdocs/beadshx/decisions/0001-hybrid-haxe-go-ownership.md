# ADR 0001: Hybrid Haxe and Go ownership

Status: superseded by ADR 0008. Retained as historical context.

## Decision

Haxe owns domain rules, validation, command meaning, handlers, application
services, diagnostics, and public BeadsHX behavior. Go owns only approved
native integration mechanics.

## Alternatives considered

A mechanical Go-to-Haxe translation would preserve the wrong package
boundaries. A Go application core with Haxe wrappers would not test the product
thesis. Removing all Go would reimplement mature native machinery without user
value.

## Authority boundary

Authored Haxe is product-policy authority. Typed Go facades are native
integration authority. Generated Go is a projection.

## Removal test and risks

An island can shrink when haxe.go expresses its API safely and native evidence
stays green. Reopen this decision only if measured vertical slices cannot keep
policy in Haxe without unsafe or materially worse behavior. The main risk is a
second application core growing invisibly in Go; native-boundary reports and
review prevent it.
