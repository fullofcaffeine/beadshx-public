package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

const databaseLocationProbeEnv = "BEADS_TEST_DATABASE_LOCATION_PROBE"

// Run the actual TestMain boundary with an inherited disposable location.
// The child checks environment and path selection without opening a database.
func TestMainClearsAmbientDatabaseLocation(t *testing.T) {
	if os.Getenv(databaseLocationProbeEnv) == "1" {
		for _, key := range []string{"BEADS_DIR", "BEADS_DB", "BD_DB"} {
			if _, present := os.LookupEnv(key); present {
				t.Errorf("TestMain retained inherited %s", key)
			}
		}
		fixture, err := os.Getwd()
		if err != nil {
			t.Fatal(err)
		}
		beadsDir := filepath.Join(fixture, ".beads")
		for _, key := range []string{"BEADS_DB", "BD_DB"} {
			t.Run(key, func(t *testing.T) {
				t.Setenv(key, filepath.Join(beadsDir, "ambient.db"))
				if got := selectedNoDBBeadsDir(nil); got != beadsDir {
					t.Errorf("explicit %s after startup selected %q, want %q", key, got, beadsDir)
				}
			})
		}
		return
	}
	fixture := t.TempDir()
	if err := os.WriteFile(filepath.Join(fixture, ".beadshx-disposable-fixture"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	beadsDir := filepath.Join(fixture, ".beads")
	if err := os.Mkdir(beadsDir, 0700); err != nil {
		t.Fatal(err)
	}
	// This metadata makes path selection return at its stat-only boundary,
	// without discovering or loading configuration in ancestor directories.
	if err := os.WriteFile(filepath.Join(beadsDir, "metadata.json"), []byte("{}\n"), 0600); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(beadsDir, "ambient.db")
	const contents = "disposable sentinel, not a database\n"
	if err := os.WriteFile(sentinel, []byte(contents), 0600); err != nil {
		t.Fatal(err)
	}
	binary, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, binary, "-test.run=^TestMainClearsAmbientDatabaseLocation$", "-test.count=1")
	cmd.Dir = fixture
	// The child must exercise its startup guard even when the parent uses a
	// prebuilt CLI; otherwise the prebuilt fast path could mask a broken guard.
	cmd.Env = append(os.Environ(), databaseLocationProbeEnv+"=1", "BEADS_DIR="+beadsDir, "BEADS_DB="+sentinel, "BD_DB="+sentinel, "BEADS_TEST_EMBEDDED_DOLT=1", "BEADS_TEST_BD_BINARY=")
	output, runErr := cmd.CombinedOutput()
	if after, err := os.ReadFile(sentinel); err != nil || string(after) != contents {
		t.Fatalf("ambient sentinel changed: %v", err)
	}
	if runErr != nil {
		t.Fatalf("isolated TestMain probe failed: %v\n%s", runErr, output)
	}
}
