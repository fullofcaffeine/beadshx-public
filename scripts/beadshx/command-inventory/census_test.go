package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCensusFindsStructuralAndSemanticObligations(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	path := filepath.Join(root, "cmd", "bd", "sample.go")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	content := `//go:build cgo

package main

import (
	"os"
	"github.com/spf13/cobra"
)

var child = &cobra.Command{
	Use: "child",
	Hidden: true,
	ValidArgsFunction: completeChild,
}

func init() {
	rootCmd.AddCommand(child)
	child.Flags().String("format", "", "format")
	_ = child.MarkFlagRequired("format")
	_ = child.RegisterFlagCompletionFunc("format", completeFormat)
	_ = os.Getenv("BD_NAME")
	_ = os.Stdin
	_ = os.Stdout
}
`
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	policies := map[string]string{
		"build-constraint":         "profile-matrix",
		"command-registration":     "runtime-structure",
		"command-metadata":         "runtime-structure",
		"flag-registration":        "runtime-structure",
		"flag-or-command-metadata": "runtime-structure",
		"completion-registration":  "reviewed-source",
		"environment-input":        "reviewed-source",
		"stdin-input":              "reviewed-source",
		"output-channel":           "reviewed-source",
	}
	got, err := censusSources(root, []sourceFile{{Path: "cmd/bd/sample.go", ActiveProfiles: []string{"release-cgo"}}}, policies)
	if err != nil {
		t.Fatal(err)
	}
	wantKinds := map[string]bool{
		"build-constraint": true, "command-registration": true, "command-metadata": true,
		"flag-registration": true, "flag-or-command-metadata": true,
		"completion-registration": true, "environment-input": true,
		"stdin-input": true, "output-channel": true,
	}
	for _, obligation := range got {
		delete(wantKinds, obligation.Kind)
		if obligation.Resolution == "" {
			t.Fatalf("%s has no resolution", obligation.Kind)
		}
		if obligation.Path != "cmd/bd/sample.go" {
			t.Fatalf("unexpected path %q", obligation.Path)
		}
	}
	if len(wantKinds) != 0 {
		t.Fatalf("missing obligation kinds: %#v", wantKinds)
	}
}

func TestCensusIDsIgnoreScratchRoot(t *testing.T) {
	t.Parallel()
	const relative = "cmd/bd/sample.go"
	const content = "package main\nimport \"os\"\nfunc f() { _ = os.Getenv(\"BD_NAME\") }\n"
	makeRoot := func() string {
		root := t.TempDir()
		path := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return root
	}
	files := []sourceFile{{Path: relative, ActiveProfiles: []string{"release-cgo"}}}
	policies := map[string]string{"environment-input": "reviewed-source"}
	left, err := censusSources(makeRoot(), files, policies)
	if err != nil {
		t.Fatal(err)
	}
	right, err := censusSources(makeRoot(), files, policies)
	if err != nil {
		t.Fatal(err)
	}
	if len(left) != 1 || len(right) != 1 || left[0].ID != right[0].ID {
		t.Fatalf("scratch roots changed obligation identity: %#v %#v", left, right)
	}
}
