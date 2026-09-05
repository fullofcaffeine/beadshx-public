package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSemanticCatalogRejectsUnknownEvidenceSymbol(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	path := filepath.Join(root, "cmd", "bd", "main.go")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("package main\nfunc known() {}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	catalog := semanticCatalog{
		ReviewerRole: "maintainer", SourceClosure: "closure", OutputBoundary: "boundary", ExclusionAuthority: "authority",
		Rules: []semanticRule{{ID: "sem:test", Kind: "environment", Summary: "summary", Evidence: []string{"cmd/bd/main.go:missing"}}},
	}
	err := validateSemanticCatalog(root, []sourceFile{{Path: "cmd/bd/main.go"}}, catalog)
	if err == nil {
		t.Fatal("catalog accepted an unknown evidence symbol")
	}
}
