package main

import (
	"os"
	"path/filepath"
	"testing"
)

// Historical inventory evidence must keep the original compiler even after
// a security update changes the compiler used for the current candidate.
func TestHistoricalToolchainsRemainIndependentOfCandidatePatch(t *testing.T) {
	root := t.TempDir()
	write := func(name, value string) {
		t.Helper()
		file := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(value), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("engdocs/beadshx/program/toolchain-locks.json", `{"common":{"go":"go1.26.10","haxeGoCommit":"compiler-revision"}}`)
	write("upstream/locks/beads-v1.2.1.json", `{"go":"1.26.5","commit":"source-revision"}`)
	var selected policy
	selected.GoVersion = "1.26.5"
	selected.Compatibility.Commit = "source-revision"
	selected.CompilerEvidence.Commit = "compiler-revision"
	if err := validateInventoryToolchains(root, selected); err != nil {
		t.Fatalf("security-patched candidate invalidated historical evidence: %v", err)
	}
	selected.GoVersion = "1.26.10"
	if err := validateInventoryToolchains(root, selected); err == nil {
		t.Fatal("accepted a changed historical Go compiler")
	}
	selected.GoVersion = "1.26.5"
	selected.Compatibility.Commit = "different-source"
	if err := validateInventoryToolchains(root, selected); err == nil {
		t.Fatal("accepted a different historical source")
	}
	selected.Compatibility.Commit = "source-revision"
	selected.CompilerEvidence.Commit = "different-compiler"
	if err := validateInventoryToolchains(root, selected); err == nil {
		t.Fatal("accepted stale Haxe compiler evidence")
	}
}
