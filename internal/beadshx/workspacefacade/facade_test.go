package workspacefacade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDiscoverFromSelectsNestedProjectWithoutChangingCWD(t *testing.T) {
	originalCWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	project := createProject(t)
	nested := filepath.Join(project, "nested", "deeper")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("MkdirAll nested directory: %v", err)
	}
	t.Setenv("BEADS_DIR", filepath.Join(t.TempDir(), "original-selection"))
	originalSelection := os.Getenv("BEADS_DIR")

	location, err := DiscoverFrom(nested, "")
	if err != nil {
		t.Fatalf("DiscoverFrom: %v", err)
	}
	wantPath := filepath.Join(project, ".beads")
	if location.Path() != wantPath {
		t.Fatalf("Path() = %q, want %q", location.Path(), wantPath)
	}
	if location.RedirectedFrom() != "" {
		t.Fatalf("RedirectedFrom() = %q, want empty explicit selection", location.RedirectedFrom())
	}
	if got := os.Getenv("BEADS_DIR"); got != originalSelection {
		t.Fatalf("BEADS_DIR after discovery = %q, want restored %q", got, originalSelection)
	}
	if got, err := os.Getwd(); err != nil {
		t.Fatalf("Getwd after discovery: %v", err)
	} else if got != originalCWD {
		t.Fatalf("working directory changed to %q, want %q", got, originalCWD)
	}
}

func TestDiscoverFromCarriesConfiguredListLimit(t *testing.T) {
	project := createProject(t)
	configYAML := []byte("list:\n  limit: 2\n")
	if err := os.WriteFile(filepath.Join(project, ".beads", "config.yaml"), configYAML, 0o600); err != nil {
		t.Fatalf("WriteFile config.yaml: %v", err)
	}

	location, err := DiscoverFrom(project, "")
	if err != nil {
		t.Fatalf("DiscoverFrom: %v", err)
	}
	if !location.ListLimitConfigured() {
		t.Fatal("ListLimitConfigured() = false, want true")
	}
	if location.ListLimit() != 2 {
		t.Fatalf("ListLimit() = %d, want 2", location.ListLimit())
	}
}

func TestDiscoverFromRejectsInvalidSelections(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-directory")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	tests := []struct {
		name      string
		directory string
		want      string
	}{
		{name: "missing", directory: filepath.Join(t.TempDir(), "missing"), want: "no such file or directory"},
		{name: "file", directory: file, want: "not a directory"},
		{name: "no project", directory: t.TempDir(), want: "no beads project found"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			location, err := DiscoverFrom(test.directory, "")
			if err == nil {
				t.Fatalf("DiscoverFrom(%q) returned location %#v, want error", test.directory, location)
			}
			if !strings.Contains(err.Error(), test.want) {
				t.Fatalf("DiscoverFrom(%q) error = %q, want substring %q", test.directory, err, test.want)
			}
		})
	}
}

func TestDiscoverFromEmptySelectionUsesAmbientWorkspace(t *testing.T) {
	project := createProject(t)
	t.Setenv("BEADS_DIR", filepath.Join(project, ".beads"))

	for _, directory := range []string{"", "   "} {
		location, err := DiscoverFrom(directory, "")
		if err != nil {
			t.Fatalf("DiscoverFrom(%q): %v", directory, err)
		}
		if want := filepath.Join(project, ".beads"); location.Path() != want {
			t.Fatalf("DiscoverFrom(%q) Path() = %q, want %q", directory, location.Path(), want)
		}
		if !location.DatabaseMissing() {
			t.Fatalf("DiscoverFrom(%q) did not classify missing embedded data", directory)
		}
	}
}

func TestDiscoverFromDatabasePathSelectsOwningWorkspace(t *testing.T) {
	project := createProject(t)
	database := filepath.Join(project, ".beads", "embeddeddolt")
	if err := os.Mkdir(database, 0o700); err != nil {
		t.Fatalf("Mkdir embedded database: %v", err)
	}

	location, err := DiscoverFrom("", database)
	if err != nil {
		t.Fatalf("DiscoverFrom database path: %v", err)
	}
	if want := filepath.Join(project, ".beads"); location.Path() != want {
		t.Fatalf("Path() = %q, want %q", location.Path(), want)
	}
	if location.DatabasePath() != database {
		t.Fatalf("DatabasePath() = %q, want %q", location.DatabasePath(), database)
	}
	if location.DatabaseName() != "" {
		t.Fatalf("DatabaseName() = %q, want empty path selection", location.DatabaseName())
	}
}

func TestDiscoverFromClassifiesMissingIdentifierAsDatabaseName(t *testing.T) {
	project := createProject(t)
	location, err := DiscoverFrom(project, "alternate_db")
	if err != nil {
		t.Fatalf("DiscoverFrom database name: %v", err)
	}
	if location.DatabaseName() != "alternate_db" {
		t.Fatalf("DatabaseName() = %q, want alternate_db", location.DatabaseName())
	}
	if want := filepath.Join(project, ".beads"); location.Path() != want {
		t.Fatalf("Path() = %q, want %q", location.Path(), want)
	}
}

func TestDiscoverFromPreservesMissingPathSelectionForWhere(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing", "database")
	location, err := DiscoverFrom("", missing)
	if err != nil {
		t.Fatalf("DiscoverFrom missing database path: %v", err)
	}
	if want := filepath.Dir(missing); location.Path() != want {
		t.Fatalf("Path() = %q, want %q", location.Path(), want)
	}
}

func TestDiscoverFromUsesSharedServerDatabasePathWithoutOpeningEmbedded(t *testing.T) {
	project := createProject(t)
	beadsDir := filepath.Join(project, ".beads")
	t.Setenv("BEADS_DOLT_SHARED_SERVER", "1")
	t.Setenv("BEADS_DOLT_AUTO_START", "0")

	location, err := DiscoverFrom(project, "")
	if err != nil {
		t.Fatalf("DiscoverFrom shared-server workspace: %v", err)
	}
	if want := filepath.Join(beadsDir, "dolt"); location.DatabasePath() != want {
		t.Fatalf("DatabasePath() = %q, want %q", location.DatabasePath(), want)
	}
	if location.Prefix() != "" {
		t.Fatalf("Prefix() = %q, want empty without contacting shared server", location.Prefix())
	}
	if location.DatabaseMissing() {
		t.Fatal("shared-server workspace was classified as missing embedded data")
	}
	if _, statErr := os.Stat(filepath.Join(beadsDir, "embeddeddolt")); !os.IsNotExist(statErr) {
		t.Fatalf("discovery created embedded data: %v", statErr)
	}
}

func createProject(t *testing.T) string {
	t.Helper()
	project := t.TempDir()
	beadsDir := filepath.Join(project, ".beads")
	if err := os.Mkdir(beadsDir, 0o700); err != nil {
		t.Fatalf("Mkdir .beads: %v", err)
	}
	metadata := []byte(`{"backend":"dolt"}`)
	if err := os.WriteFile(filepath.Join(beadsDir, "metadata.json"), metadata, 0o600); err != nil {
		t.Fatalf("WriteFile metadata.json: %v", err)
	}
	canonical, err := filepath.EvalSymlinks(project)
	if err != nil {
		t.Fatalf("EvalSymlinks project: %v", err)
	}
	return canonical
}
