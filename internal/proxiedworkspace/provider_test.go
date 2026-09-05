package proxiedworkspace

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/steveyegge/beads/internal/configfile"
)

func TestResolveAbsentFilesUsesOrdinaryDefaults(t *testing.T) {
	topology, err := Resolve(t.TempDir(), "")
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if topology.Database != configfile.DefaultDoltDatabase {
		t.Fatalf("Database = %q, want %q", topology.Database, configfile.DefaultDoltDatabase)
	}
	if topology.TeamServer {
		t.Fatal("TeamServer = true, want false")
	}
	if topology.External != nil {
		t.Fatal("External is non-nil, want managed default")
	}
}

func TestResolveForInspectionRequiresExplicitProxiedMode(t *testing.T) {
	_, err := ResolveForInspection(t.TempDir(), "")
	if err == nil {
		t.Fatal("ResolveForInspection without metadata: got nil, want error")
	}
}

func TestResolveForInspectionDoesNotMigrateLegacyConfig(t *testing.T) {
	beadsDir := t.TempDir()
	legacyPath := filepath.Join(beadsDir, "config.json")
	body := []byte(`{"backend":"dolt","dolt_mode":"proxied-server","dolt_database":"legacy"}`)
	if err := os.WriteFile(legacyPath, body, 0o600); err != nil {
		t.Fatalf("write legacy config: %v", err)
	}

	topology, err := ResolveForInspection(beadsDir, "override")
	if err != nil {
		t.Fatalf("ResolveForInspection: %v", err)
	}
	if topology.Database != "override" {
		t.Fatalf("Database = %q, want override", topology.Database)
	}
	if _, err := os.Stat(configfile.ConfigPath(beadsDir)); !os.IsNotExist(err) {
		t.Fatalf("metadata.json was created during inspection: %v", err)
	}
	got, err := os.ReadFile(legacyPath)
	if err != nil {
		t.Fatalf("read legacy config: %v", err)
	}
	if string(got) != string(body) {
		t.Fatalf("legacy config changed: got %q, want %q", got, body)
	}
}

func TestResolveForInspectionDatabaseOverrideKeepsProjectIdentity(t *testing.T) {
	beadsDir := t.TempDir()
	cfg := &configfile.Config{
		Backend:        configfile.BackendDolt,
		DoltMode:       configfile.DoltModeProxiedServer,
		DoltDatabase:   "configured",
		DoltTeamServer: true,
		ProjectID:      "project-one",
	}
	if err := cfg.Save(beadsDir); err != nil {
		t.Fatalf("save config: %v", err)
	}

	topology, err := ResolveForInspection(beadsDir, "override")
	if err != nil {
		t.Fatalf("ResolveForInspection: %v", err)
	}
	if topology.Database != "override" {
		t.Fatalf("Database = %q, want override", topology.Database)
	}
	if topology.ExpectedProjectID != "project-one" {
		t.Fatalf("ExpectedProjectID = %q, want project-one", topology.ExpectedProjectID)
	}
}
