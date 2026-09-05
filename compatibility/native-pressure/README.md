# Go dependency and native-boundary pressure

This inventory answers one porting question: which exported Go APIs can Haxe
consume through precise externs, and which proven unexported, unsafe, CGO, or
lifecycle effects still require a narrow native island?

The generator loads the pinned Beads command package with `go/packages` and
`go/types` under the release-CGO and portable-non-CGO profiles. It follows the
reachable first-party package graph, then records calls from six native
boundary groups into standard-library, external, or cross-boundary APIs. Calls
are deduplicated by boundary and normalized target signature. Every caller and
source location remains in the compressed inventory.

The generator does not treat a named interface's internal methods as callback
or channel pressure. It classifies only types present at the API boundary.
During a macOS-to-Linux CGO analysis, the Go loader can report missing C
metadata for external packages. The check admits only that exact cross-toolchain
diagnostic. All first-party packages must still type-check.

Files in this directory have separate jobs:

- `policy.json` owns semantic boundary groups, feature ranks, dependency
  ownership, and existing compiler-gap links.
- `inventory.json.gz` contains every typed API record and source locator.
- `report.md` is the generated review projection.

The inventory reuses the 13 command profiles, storage capabilities, and 21
native effects. It does not copy those product contracts into a new model.

## Local command

```sh
npm run test:native-pressure
```

The command needs the locked Go and Haxe toolchains. It does not need `gh`,
GitHub Actions, Docker, or network access. It also compiles and runs the
historically named `test/native-pressure/simple_facade` tracer, which proves one
typed `(value, error)` boundary from authored Haxe through generated Go and a
real runtime result. The tracer proves the pipeline only; it does not authorize
a handwritten facade where a precise extern can represent the exported API.
