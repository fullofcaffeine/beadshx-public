//go:build cgo

package readonlyfacade

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

// Upstream warns about a config.yaml that does not parse and runs with the
// settings that loaded (cmd/bd/main.go prepareSelectedCommandContext). Haxe
// prints that warning; the store open must still succeed.
func TestOpenStoreRunsWithUnparseableConfigYAML(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("BEADS_DOLT_SHARED_SERVER", "0")
	ctx := context.Background()
	beadsDir := filepath.Join(t.TempDir(), ".beads")
	fixture, err := embeddeddolt.Open(ctx, beadsDir, "broken_config", "main")
	if err != nil {
		t.Fatalf("create embedded fixture: %v", err)
	}
	if err := fixture.Close(); err != nil {
		t.Fatalf("close embedded fixture: %v", err)
	}
	cfg := configfile.DefaultConfig()
	cfg.DoltMode = configfile.DoltModeEmbedded
	cfg.DoltDatabase = "broken_config"
	if err := cfg.Save(beadsDir); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(beadsDir, "config.yaml"), []byte("list: [\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_DIR", filepath.Join(t.TempDir(), "caller-selection"))
	callerSelection := os.Getenv("BEADS_DIR")

	store, path, mode, err := openStore(ctx, beadsDir, false)
	if err != nil {
		t.Fatalf("openStore with an unparseable config.yaml: %v", err)
	}
	t.Cleanup(func() {
		if err := store.Close(); err != nil {
			t.Errorf("close store: %v", err)
		}
	})
	if want := filepath.Join(beadsDir, "embeddeddolt"); path != want {
		t.Fatalf("openStore path = %q, want %q", path, want)
	}
	if mode != "direct" {
		t.Fatalf("openStore mode = %q, want direct", mode)
	}
	if got := os.Getenv("BEADS_DIR"); got != callerSelection {
		t.Fatalf("BEADS_DIR after openStore = %q, want restored %q", got, callerSelection)
	}
}
