package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const repositoryRoot = "../../.."

// copyRepository copies the islands and their baseline into a temporary
// repository, so that a test can change them without touching the real tree.
func copyRepository(t *testing.T) string {
	t.Helper()
	repository := t.TempDir()
	if err := os.CopyFS(filepath.Join(repository, islandRoot), os.DirFS(filepath.Join(repositoryRoot, islandRoot))); err != nil {
		t.Fatalf("copy islands: %v", err)
	}
	baseline, err := os.ReadFile(filepath.Join(repositoryRoot, baselinePath))
	if err != nil {
		t.Fatalf("read baseline: %v", err)
	}
	target := filepath.Join(repository, baselinePath)
	if err := os.MkdirAll(filepath.Dir(target), 0o750); err != nil {
		t.Fatalf("create baseline directory: %v", err)
	}
	if err := os.WriteFile(target, baseline, 0o600); err != nil {
		t.Fatalf("write baseline: %v", err)
	}
	return repository
}

// replaceOnce replaces the first old in an island file and fails when old is
// absent, so a moved anchor cannot make a test pass silently.
func replaceOnce(t *testing.T, repository, file, old, replacement string) {
	t.Helper()
	path := filepath.Join(repository, islandRoot, file)
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", file, err)
	}
	if !bytes.Contains(source, []byte(old)) {
		t.Fatalf("%s does not contain %q", file, old)
	}
	updated := strings.Replace(string(source), old, replacement, 1)
	if err := os.WriteFile(path, []byte(updated), 0o600); err != nil {
		t.Fatalf("write %s: %v", file, err)
	}
}

func appendTo(t *testing.T, repository, file, text string) {
	t.Helper()
	path := filepath.Join(repository, islandRoot, file)
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", file, err)
	}
	if err := os.WriteFile(path, append(source, []byte(text)...), 0o600); err != nil {
		t.Fatalf("write %s: %v", file, err)
	}
}

func runGuard(t *testing.T, repository string, update bool) (string, error) {
	t.Helper()
	var stdout bytes.Buffer
	err := run(repository, update, &stdout)
	return stdout.String(), err
}

func requireFailure(t *testing.T, repository string, wants ...string) {
	t.Helper()
	_, err := runGuard(t, repository, false)
	if err == nil {
		t.Fatal("island guard accepted the changed islands")
	}
	for _, want := range wants {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error does not mention %q:\n%v", want, err)
		}
	}
}

func TestCommittedIslandsMatchTheBaseline(t *testing.T) {
	if _, err := runGuard(t, repositoryRoot, false); err != nil {
		t.Fatalf("island guard rejected the committed islands: %v", err)
	}
}

func TestAddedLineFails(t *testing.T) {
	repository := copyRepository(t)
	appendTo(t, repository, "gitfacade/facade.go", "// one more handwritten line\n")
	requireFailure(t, repository, "grew from", "port the behavior to Haxe")
}

func TestAddedImportFails(t *testing.T) {
	repository := copyRepository(t)
	replaceOnce(t, repository, "gitfacade/facade.go", "import (\n", "import (\n\t_ \"net/http\"\n")
	requireFailure(t, repository, `new import "net/http"`)
}

func TestMigratingConfigLoadFails(t *testing.T) {
	repository := copyRepository(t)
	appendTo(t, repository, "workspacefacade/facade.go",
		"\nfunc guardProbe() { _, _ = configfile.Load(\"\") }\n")
	requireFailure(t, repository, "workspacefacade/facade.go", "calls configfile.Load")
}

func TestAliasedMigratingConfigLoadFails(t *testing.T) {
	repository := copyRepository(t)
	replaceOnce(t, repository, "gitfacade/facade.go", "import (\n",
		"import (\n\tcf \"github.com/steveyegge/beads/internal/configfile\"\n")
	appendTo(t, repository, "gitfacade/facade.go", "\nfunc guardProbe() { _, _ = cf.Load(\"\") }\n")
	requireFailure(t, repository, "gitfacade/facade.go", "calls configfile.Load")
}

func TestWritableEmbeddedOpenFails(t *testing.T) {
	repository := copyRepository(t)
	replaceOnce(t, repository, "readonlyfacade/embedded_cgo.go", "embeddeddolt.OpenReadOnly(", "embeddeddolt.Open(")
	requireFailure(t, repository, "readonlyfacade/embedded_cgo.go", "embeddeddolt.Open")
}

func TestWritableServerOpenFails(t *testing.T) {
	repository := copyRepository(t)
	replaceOnce(t, repository, "readonlyfacade/facade.go", "ReadOnly:         true,", "ReadOnly:         false,")
	requireFailure(t, repository, "readonlyfacade/facade.go", "dolt.NewFromConfigWithOptions", "ReadOnly: true")
}

func TestShrinkFailsUntilUpdateLowersTheBaseline(t *testing.T) {
	repository := copyRepository(t)
	replaceOnce(t, repository, "gitfacade/facade.go", "// A non-repository directory is an empty history, matching upstream orphan\n", "")
	requireFailure(t, repository, "the islands shrank (", "baseline lines; 0 imports no longer used)",
		"lower the baseline in this commit: go run ./scripts/beadshx/island-guard --update")
	if _, err := runGuard(t, repository, true); err != nil {
		t.Fatalf("update refused a shrink: %v", err)
	}
	if _, err := runGuard(t, repository, false); err != nil {
		t.Fatalf("baseline was not lowered: %v", err)
	}
}

func TestUnusedImportFailsUntilUpdateLowersTheBaseline(t *testing.T) {
	repository := copyRepository(t)
	baseline := filepath.Join(repository, baselinePath)
	source, err := os.ReadFile(baseline)
	if err != nil {
		t.Fatal(err)
	}
	stale := strings.Replace(string(source), "\"bytes\",", "\"archive/tar\",\n    \"bytes\",", 1)
	if stale == string(source) {
		t.Fatal("baseline does not list bytes")
	}
	if err := os.WriteFile(baseline, []byte(stale), 0o600); err != nil {
		t.Fatal(err)
	}
	requireFailure(t, repository, "1 imports no longer used", "--update")
	if _, err := runGuard(t, repository, true); err != nil {
		t.Fatalf("update refused to drop an unused import: %v", err)
	}
	if _, err := runGuard(t, repository, false); err != nil {
		t.Fatalf("baseline was not lowered: %v", err)
	}
}

func TestUpdateRefusesGrowth(t *testing.T) {
	repository := copyRepository(t)
	before, err := os.ReadFile(filepath.Join(repository, baselinePath))
	if err != nil {
		t.Fatal(err)
	}
	appendTo(t, repository, "gitfacade/facade.go", "// one more handwritten line\n")
	if _, err := runGuard(t, repository, true); err == nil {
		t.Fatal("update raised the baseline")
	}
	after, err := os.ReadFile(filepath.Join(repository, baselinePath))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("refused update still changed the baseline")
	}
}
