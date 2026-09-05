# Generated-source policy

Authored Haxe is the source of BeadsHX behavior. haxe.go converts that source
to disposable Go during the build. Git ignores the generated Go tree, and a
contributor must not edit that tree to fix a problem.

The repository commits one small fixture for the bootstrap tracer:
`bootstrap-fixture.json`. This fixture records each generated file and its
SHA-256 value. It also records the owning Haxe source, HXML file, compiler lock,
and exact haxe.go revision.

The fixture excludes `_GeneratedFiles.json`. Reflaxe uses this file for
incremental cleanup and writes a changing sequence ID. The file is not Go
source, and packages do not include it.

Run `npm run test:generated` after a Haxe or compiler change. The command
generates Go in a temporary directory and compares all files with the fixture.
If bytes change, the error names the Haxe owners and compiler revision. It also
writes the proposed manifest and byte diff under
`build/evidence/generated-drift/`.

Review the generated Go before you accept a fixture change. Make sure that the
names, imports, evaluation order, notices, and runtime support remain correct.
Then update the fixture in the same commit as the Haxe or compiler change.

The development package includes the complete generated Go tree and its two
approved notices. The package command checks every archived generated file
against this fixture. A future release archive must use the same inclusion and
notice checks. This policy does not make the development package a release.
